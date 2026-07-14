--- workspace/integration/persist.lua
--- Subscribe to the 8 reactive workspace mutation events and persist the
--- tab/project metadata layer (state.json) on a debounce, regardless of
--- whether a named session is active. Cold-start `setup()` rehydrates the
--- in-memory tab_state from disk before any user command runs.
local M = {}

local MUTATION_EVENTS = {
  "WorkspaceTabProjectAdded",
  "WorkspaceTabProjectRemoved",
  "WorkspaceTabActiveChanged",
  "WorkspaceTabCwdChanged",
  "WorkspaceTabRenamed",
  "WorkspaceTabReordered",
  "WorkspaceProjectRegistered",
  "WorkspaceProjectUpdated",
  "WorkspaceProjectUnregistered",
}

local _timer

-- Always-on diagnostic log. Trace exactly when do_write runs and what
-- snapshot_meta sees. /tmp/wsp-persist.log is wiped on M.setup().
local LOG_PATH = "/tmp/wsp-persist.log"
local function dlog(msg)
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  f:write(os.date("%H:%M:%S "))
  f:write(msg)
  f:write("\n")
  f:close()
end

local function flush()
  if _timer then
    pcall(vim.fn.timer_stop, _timer)
    _timer = nil
  end
end

local function do_write()
  local snapshot = require("workspace.workspace.snapshot")
  local persist  = require("workspace.state.persist")
  local ok, snap = pcall(snapshot.snapshot_meta)
  if not ok or type(snap) ~= "table" then
    dlog("do_write: snapshot_meta failed " .. tostring(snap))
    return
  end
  local tab_state_count = #require("workspace.tab.state").all()
  dlog(string.format(
    "do_write: tab_state.all=%d snap.tabs=%d",
    tab_state_count, #(snap.tabs or {})))
  local wok, werr = persist.write(snap)
  if not wok then
    dlog("do_write: write failed " .. tostring(werr))
    require("workspace.util.log").error("persist.write failed: " .. tostring(werr))
  end
end

--- Setup the persistent-state subscriber + immediate cold-start rehydrate.
---@param cfg table workspace config
function M.setup(cfg)
  cfg = cfg or {}
  local ps = cfg.persistent_state
  if ps and ps.enabled == false then
    return
  end

  -- Truncate diagnostic log per setup invocation.
  local f = io.open(LOG_PATH, "w")
  if f then f:close() end
  dlog("setup() invoked")

  local sess_cfg  = cfg.session or {}
  local debounce_ms = (ps and ps.debounce_ms) or sess_cfg.autosave_debounce_ms or 500

  -- Cold-start rehydrate: pull state.json into tab_state BEFORE any user
  -- command can run. Non-disruptive: does not open new tabs / replace
  -- buffers, only fills in metadata (label/cwd/project_ids/active).
  pcall(function()
    local persist = require("workspace.state.persist")
    local snap = persist.read()
    if snap then
      dlog("rehydrate: snap.tabs=" .. #(snap.tabs or {}))
      require("workspace.workspace.snapshot").restore_meta(snap)
      dlog("rehydrate: tab_state.all=" .. #require("workspace.tab.state").all())
    else
      dlog("rehydrate: state.json absent or empty")
    end
  end)

  local function debounced()
    -- Skip writes while exiting; VimLeavePre handler does the final flush.
    if vim.v.exiting ~= vim.NIL then return end
    -- Re-read live config so toggling at runtime works.
    local live_ok, live_cfg = pcall(function() return require("workspace.config").get() end)
    if live_ok and live_cfg and live_cfg.persistent_state
        and live_cfg.persistent_state.enabled == false then
      return
    end
    flush()
    _timer = vim.fn.timer_start(debounce_ms, function()
      _timer = nil
      do_write()
    end)
  end

  local group = vim.api.nvim_create_augroup("WorkspacePersistState", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      flush()
      do_write()
    end,
  })

  for _, ev in ipairs(MUTATION_EVENTS) do
    local pat = ev
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = pat,
      callback = function()
        dlog("event " .. pat .. " — tab_state.all=" ..
          #require("workspace.tab.state").all())
        debounced()
      end,
    })
  end

  -- Expose for tests.
  M._debounced = debounced
  M._flush     = flush
  M._do_write  = do_write
end

--- Tear down the augroup (test helper).
function M._teardown()
  flush()
  pcall(vim.api.nvim_del_augroup_by_name, "WorkspacePersistState")
end

return M
