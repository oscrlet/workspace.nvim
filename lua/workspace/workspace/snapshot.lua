--- workspace/workspace/snapshot.lua
--- Capture and restore full workspace state across tabs.
local M = {}

local ws_state  = require("workspace.workspace.state")
local ws_api    = require("workspace.workspace.api")
local tab_state = require("workspace.tab.state")
local tab_api   = require("workspace.tab.api")
local snapshot_dispatch = require("workspace.snapshot")

--- Capture current workspace state.
---@return table  { version=1, tabs=TabEntry[], active_tab_id }
function M.snapshot()
  local tabs = ws_state.tabs()
  local entries = {}
  for _, tab in ipairs(tabs) do
    local cfg = require("workspace.config").get()
    local nvim_state = snapshot_dispatch.capture(tab.tabnr, cfg)
    entries[#entries + 1] = {
      id               = tab.id,
      label            = tab.label,
      order            = tab.order,
      cwd              = tab.cwd,
      project_ids      = vim.deepcopy(tab.project_ids),
      active_project_id = tab.active_project_id,
      nvim_state       = nvim_state,
    }
  end
  local active_id = ws_state.active_tab_id()
  local active_idx
  for i, tab in ipairs(tabs) do
    if tab.id == active_id then
      active_idx = i
      break
    end
  end
  -- Capture all globally-listed buffers so hidden buffers (those `badd`-ed
  -- but never window-displayed) survive restore. Per-tab nvim_state only
  -- captures windows; this list is the rest.
  local listed_buffers = {}
  do
    local seen = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[b].buflisted then
        local n = vim.api.nvim_buf_get_name(b)
        if n ~= "" and not seen[n] then
          local stat = vim.uv and vim.uv.fs_stat and vim.uv.fs_stat(n)
            or vim.loop.fs_stat(n)
          if stat then
            seen[n] = true
            listed_buffers[#listed_buffers + 1] = n
          end
        end
      end
    end
  end
  return {
    version          = 1,
    tabs             = entries,
    active_tab_id    = active_id,    -- legacy, keep for old loaders
    active_tab_index = active_idx,
    listed_buffers   = listed_buffers,
  }
end

--- Capture the metadata-only slice of workspace state.
--- Same shape as `snapshot()` but omits the buffer/winlayout payload:
---   * each tab's `nvim_state` is `""` (no winlayout capture)
---   * top-level `listed_buffers` is `nil` (no global buffer list)
--- Used for the persistent `state.json` layer, which lives independently of
--- named sessions and survives cold-start no-session mutations.
---@return table  { version=1, tabs=TabEntry[], active_tab_id, active_tab_index }
function M.snapshot_meta()
  local tabs = ws_state.tabs()
  local entries = {}
  for _, tab in ipairs(tabs) do
    entries[#entries + 1] = {
      id               = tab.id,
      label            = tab.label,
      order            = tab.order,
      cwd              = tab.cwd,
      project_ids      = vim.deepcopy(tab.project_ids),
      active_project_id = tab.active_project_id,
      nvim_state       = "",
    }
  end
  local active_id = ws_state.active_tab_id()
  local active_idx
  for i, tab in ipairs(tabs) do
    if tab.id == active_id then
      active_idx = i
      break
    end
  end
  return {
    version          = 1,
    tabs             = entries,
    active_tab_id    = active_id,
    active_tab_index = active_idx,
  }
end

--- Non-disruptively rehydrate tab metadata from a snapshot_meta() blob.
--- Unlike `restore()` this does NOT spawn new tabs, run `tabonly`, replace
--- buffer/window layout, or `:badd` files. It only repopulates the in-memory
--- `tab_state` and `ws_state.active_tab_id` so subsequent UI/router calls see
--- the persisted projects/labels.
---
--- Strategy: iterate snap.tabs in order, mapping each entry onto the i-th
--- existing nvim tabpage where one exists; entries beyond the current tab
--- count are skipped (caller may later open more tabs manually). When only a
--- single tab is open at cold-start (the typical case), this hydrates that
--- tab with the first persisted entry.
---@param snap table
function M.restore_meta(snap)
  if type(snap) ~= "table" or type(snap.tabs) ~= "table" then
    return
  end
  local pages = vim.api.nvim_list_tabpages()
  local project = require("workspace.project")
  local cfg = require("workspace.config").get()
  local log = require("workspace.util.log")

  for i, entry in ipairs(snap.tabs) do
    local nr = pages[i]
    if not nr then break end
    -- Reset/seed tab_state for this tabnr.
    tab_state.remove(nr)
    local tab = tab_state.ensure(nr)
    tab._snap_id = entry.id
    -- Best-effort: align the in-memory uuid with the persisted one so later
    -- writes round-trip the same id (helps cross-restart user references).
    if entry.id and entry.id ~= "" then
      -- tab_state.ensure already assigned a fresh uuid; rewrite it.
      -- Internal state isn't exposed but `tab.id`/`tab.uuid` are mutable on the
      -- returned record. tab_state stores by tabnr so this is safe.
      tab.id   = entry.id
      tab.uuid = entry.id
    end
    tab.label = entry.label
    tab.order = entry.order or tab.order
    tab.cwd   = entry.cwd or tab.cwd
    tab.project_ids = {}
    for _, pid in ipairs(entry.project_ids or {}) do
      if not project.get(pid) and cfg.project and cfg.project.auto_register_on_load then
        local root = entry.cwd
        if not root or root == "" then
          root = vim.fn.getcwd()
        end
        local ok = pcall(project.register, {
          path = root, id = pid, name = pid,
          meta = { auto = "state_rehydrate" },
        })
        if not ok then
          log.warn("restore_meta: auto-register '" .. pid .. "' failed")
        end
      end
      tab.project_ids[#tab.project_ids + 1] = pid
    end
    if entry.active_project_id then
      tab.active_project_id = entry.active_project_id
    end
  end

  -- Active tab id: prefer index-based mapping into existing tabpages.
  if snap.active_tab_index and pages[snap.active_tab_index] then
    local nr = pages[snap.active_tab_index]
    local tab = tab_state.by_tabnr(nr)
    if tab then ws_state.set_active_tab_id(tab.id) end
  elseif snap.active_tab_id then
    ws_state.set_active_tab_id(snap.active_tab_id)
  end
end

--- Restore workspace from a snapshot.
---@param snap table  { version, tabs, active_tab_id }
function M.restore(snap)
  if type(snap) ~= "table" or type(snap.tabs) ~= "table" then
    require("workspace.util.log").error("snapshot.restore: invalid snapshot")
    return
  end

  -- Close all existing tabs except the first (vim requires ≥1 tab).
  local existing = vim.api.nvim_list_tabpages()
  -- We'll create new tabs first, then remove old ones.
  local old_tabs = vim.deepcopy(existing)

  -- Create tabs for snapshot entries.
  local new_tab_map = {}  -- snap entry index -> tabnr
  for i, entry in ipairs(snap.tabs) do
    if i == 1 then
      -- Reuse first existing tab instead of opening a new one.
      local nr = old_tabs[1]
      tab_state.remove(nr)
      local tab = tab_state.ensure(nr)
      tab._snap_id = entry.id
      new_tab_map[i] = nr
    else
      vim.cmd("tabnew")
      local nr = vim.api.nvim_get_current_tabpage()
      tab_state.remove(nr)
      local tab = tab_state.ensure(nr)
      tab._snap_id = entry.id
      new_tab_map[i] = nr
    end
    local nr  = new_tab_map[i]
    local tab = tab_state.by_tabnr(nr)
    -- Restore fields.
    tab.label  = entry.label
    tab.order  = entry.order
    tab.cwd    = entry.cwd or tab.cwd
    -- Restore project associations.
    tab.project_ids = {}
    local cfg = require("workspace.config").get()
    local project = require("workspace.project")
    local log = require("workspace.util.log")
    for _, pid in ipairs(entry.project_ids or {}) do
      if not project.get(pid) and cfg.project and cfg.project.auto_register_on_load then
        local root = entry.cwd
        if not root or root == "" then
          root = vim.fn.getcwd()
          log.warn("auto-register project '" .. pid .. "': entry.cwd missing, falling back to cwd=" .. root)
        end
        local ok, err = pcall(project.register, {
          path = root,
          id   = pid,
          name = pid,
          meta = { auto = "session_load" },
        })
        if ok then
          log.warn("auto-registered project '" .. pid .. "' from session load (root=" .. root .. ")")
        else
          log.error("auto-register project '" .. pid .. "' failed: " .. tostring(err))
        end
      end
      tab_api.add_project(nr, pid)
    end
    if entry.active_project_id then
      tab.active_project_id = entry.active_project_id
    end
    -- Apply cwd.
    if entry.cwd then
      pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(entry.cwd))
    end
    -- Restore nvim_state via the winlayout backend (current default).
    -- Two on-disk forms are supported:
    --   * kind = "winlayout" (current)
    --   * kind = "files"      (legacy; handled by winlayout backend too)
    if entry.nvim_state and entry.nvim_state ~= "" then
      local ok_dec, decoded = pcall(vim.json.decode, entry.nvim_state)
      local idx = vim.api.nvim_tabpage_get_number(nr)
      if ok_dec and type(decoded) == "table" then
        pcall(vim.cmd, idx .. "tabnext")
        snapshot_dispatch.restore(decoded, nr)
      end
    end
  end

  -- Close surplus old tabs (all old tabs beyond the first that we reused).
  -- Navigate away first to avoid closing the active tab prematurely.
  if #old_tabs > 1 then
    -- Switch to first new tab.
    vim.cmd("1tabnext")
    for i = 2, #old_tabs do
      local nr = old_tabs[i]
      -- Check it still exists.
      local pages = vim.api.nvim_list_tabpages()
      local exists = false
      for _, p in ipairs(pages) do
        if p == nr then exists = true; break end
      end
      if exists then
        -- Find its index and close.
        local idx = vim.api.nvim_tabpage_get_number(nr)
        pcall(vim.cmd, idx .. "tabclose")
        -- Remove from state.
        tab_state.remove(nr)
      end
    end
  end

  -- Resolve active tab: prefer index-based lookup, fall back to legacy id scan.
  local function focus(nr)
    if not nr then return end
    local tab = tab_state.by_tabnr(nr)
    if not tab then return end
    ws_state.set_active_tab_id(tab.id)
    pcall(vim.cmd, vim.api.nvim_tabpage_get_number(nr) .. "tabnext")
  end

  if snap.active_tab_index then
    focus(new_tab_map[snap.active_tab_index])
  elseif snap.active_tab_id then
    for i, entry in ipairs(snap.tabs) do
      if entry.id == snap.active_tab_id then
        focus(new_tab_map[i])
        break
      end
    end
  end

  -- Re-add any globally listed buffers that the per-tab winlayout did not
  -- cover (e.g. files the user `:badd`-ed but never opened in a window).
  for _, f in ipairs(snap.listed_buffers or {}) do
    pcall(vim.cmd, "badd " .. vim.fn.fnameescape(f))
  end
end

return M
