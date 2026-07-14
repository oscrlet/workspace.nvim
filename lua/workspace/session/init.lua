local M = {}

local api = require("workspace.session.api")
local state = require("workspace.session.state")

-- Re-export api functions
M.save = api.save
M.load = api.load
M.delete = api.delete
M.list = api.list
M.current = api.current
M.rename = api.rename
M.exists = api.exists
M.projects = api.projects
M.focus_project = api.focus_project
M.save_candidates = api.save_candidates

-- session.path(name) → abs file path (proxies store.path for router yank actions)
M.path = function(name)
  return require("workspace.session.store").path(name)
end

--- Format an epoch-seconds timestamp as a relative human-readable string.
--- Pure function; `now` is optional (defaults to os.time()) for testability.
--- Buckets:
---   < 5s    → "just now"
---   < 60s   → "%ds ago"
---   < 60m   → "%dm ago"
---   < 24h   → "%dh ago"
---   < 30d   → "%dd ago"
---   ≥ 30d   → os.date("%Y-%m-%d", epoch_sec)
---@param epoch_sec integer
---@param now integer|nil
---@return string
M.format_relative = function(epoch_sec, now)
  if type(epoch_sec) ~= "number" then return "" end
  now = now or os.time()
  local diff = now - epoch_sec
  if diff < 0 then diff = 0 end
  if diff < 5 then
    return "just now"
  elseif diff < 60 then
    return string.format("%ds ago", diff)
  elseif diff < 3600 then
    return string.format("%dm ago", math.floor(diff / 60))
  elseif diff < 86400 then
    return string.format("%dh ago", math.floor(diff / 3600))
  elseif diff < 86400 * 30 then
    return string.format("%dd ago", math.floor(diff / 86400))
  else
    return os.date("%Y-%m-%d", epoch_sec)
  end
end

-- session.current_info() → { name, path, exists, modified_at, modified_at_rel } | nil
M.current_info = function()
  local name = api.current()
  if not name then return nil end
  local p = require("workspace.session.store").path(name)
  local stat = vim.uv.fs_stat(p)
  local mtime = stat and stat.mtime.sec or nil
  return {
    name = name,
    path = p,
    exists = stat ~= nil,
    modified_at = mtime,
    modified_at_rel = mtime and M.format_relative(mtime) or nil,
  }
end

return M
