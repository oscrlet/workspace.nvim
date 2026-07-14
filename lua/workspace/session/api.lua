--- workspace/session/api.lua
--- Session lifecycle operations.
local M = {}

local store     = require("workspace.session.store")
local ss        = require("workspace.session.state")
local tab_state = require("workspace.tab.state")

local function snapshot_mod()
  return require("workspace.workspace.snapshot")
end

local function ws_api()
  return require("workspace.workspace.api")
end

--- Save current workspace state as a named session.
--- Uses current session name if name omitted.
---@param name string|nil
---@return boolean, string|nil
function M.save(name)
  name = name or ss.current()
  if not name or name == "" then
    return false, "no session name given"
  end
  local snap = snapshot_mod().snapshot()
  local ok, err = store.write(name, snap)
  if ok then
    ss.set_current(name)
    pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "WorkspaceSessionSaved", data = { name = name } })
  end
  return ok, err
end

--- Internal: actual load logic shared between sync and prompt paths.
---@param name string
---@return boolean, string|nil
local function do_load(name)
  if not ss.acquire_lock(name) then
    return false, "session '" .. name .. "' is locked by another process"
  end
  local data, err = store.read(name)
  if not data then
    ss.release_lock(name)
    return false, err
  end
  local ok, restore_err = pcall(snapshot_mod().restore, data)
  ss.release_lock(name)
  if not ok then
    return false, "restore failed: " .. tostring(restore_err)
  end
  ss.set_current(name)
  -- Mirror the just-loaded session into the persistent state.json so the
  -- two layers stay coherent. Best-effort; failure here is non-fatal.
  pcall(function()
    local cfg_ok, cfg = pcall(function() return require("workspace.config").get() end)
    local enabled = (not cfg_ok) or (not cfg) or (not cfg.persistent_state)
      or cfg.persistent_state.enabled ~= false
    if enabled then
      local snap_meta = snapshot_mod().snapshot_meta()
      require("workspace.state.persist").write(snap_meta)
    end
  end)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "WorkspaceSessionLoaded", data = { name = name } })
  return true, nil
end

--- Load a session by name and restore workspace state.
--- When `cfg.session.confirm_before_load == true` and `opts.force` is not set,
--- prompts the user via `vim.ui.select`. In prompt mode the actual load runs
--- inside the select callback; the return value is `true` to signal that the
--- prompt was dispatched (callers needing the real outcome should pass force=true).
---@param name string
---@param opts table|nil  { force = boolean }
---@return boolean, string|nil
function M.load(name, opts)
  opts = opts or {}
  local cfg_ok, cfg = pcall(function() return require("workspace.config").get() end)
  local need_confirm = cfg_ok and cfg and cfg.session and cfg.session.confirm_before_load == true
  if need_confirm and not opts.force then
    -- vim.ui.select is overridden by integration/ui_select.lua to render
    -- through the router-styled Snacks picker; the call site stays
    -- vendor-neutral.
    vim.ui.select({ "Load", "Cancel" }, { prompt = "Load session '" .. name .. "'?" }, function(choice)
      if choice == "Load" then
        do_load(name)
      end
    end)
    return true, nil
  end
  return do_load(name)
end

--- Delete a session.
---@param name string
function M.delete(name)
  if ss.current() == name then
    ss.set_current(nil)
  end
  store.delete(name)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "WorkspaceSessionDeleted", data = { name = name } })
end

--- List sessions.
---@return table[]
function M.list()
  return store.list()
end

--- Current session name.
---@return string|nil
function M.current()
  return ss.current()
end

--- Rename a session.
---@param old string
---@param new string
---@return boolean, string|nil
function M.rename(old, new)
  if ss.current() == old then
    ss.set_current(new)
  end
  local ok, err = store.rename(old, new)
  if ok then
    pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "WorkspaceSessionRenamed", data = { from = old, to = new } })
  end
  return ok, err
end

--- Check if session file exists.
---@param name string
---@return boolean
function M.exists(name)
  local f = io.open(store.path(name), "r")
  if f then f:close(); return true end
  return false
end

--- Union of all project_ids across all tabs.
---@return string[]
function M.projects()
  local seen   = {}
  local result = {}
  for _, tab in ipairs(tab_state.all()) do
    for _, pid in ipairs(tab.project_ids or {}) do
      if not seen[pid] then
        seen[pid]            = true
        result[#result + 1] = pid
      end
    end
  end
  return result
end

--- Focus a project: find its tab, switch to it, make it active.
---@param id string
function M.focus_project(id)
  local wsa = ws_api()
  local tabs = tab_state.all()
  for _, tab in ipairs(tabs) do
    for _, pid in ipairs(tab.project_ids or {}) do
      if pid == id then
        -- Switch to this tab.
        local idx = vim.api.nvim_tabpage_get_number(tab.tabnr)
        wsa.switch_tab(idx)
        require("workspace.tab.api").switch_active(id, tab.tabnr)
        return
      end
    end
  end
  require("workspace.util.log").warn("focus_project: project '" .. id .. "' not found in any tab")
end

--- Return sorted list of session names with current marked.
---@return { name: string, current: boolean }[]
function M.save_candidates()
  local items   = store.list()
  local cur     = ss.current()
  local result  = {}
  local cur_in  = false
  for _, item in ipairs(items) do
    result[#result + 1] = { name = item.name, current = (item.name == cur) }
    if item.name == cur then cur_in = true end
  end
  if cur and not cur_in then
    table.insert(result, 1, { name = cur, current = true })
  end
  return result
end

return M
