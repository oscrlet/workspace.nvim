--- workspace/state/persist.lua
--- Atomic JSON IO for persistent tab/project metadata (state.json).
---
--- This is the persistent counterpart of named-session snapshots; it stores
--- the tab metadata layer (label/order/cwd/project_ids/active_project_id)
--- WITHOUT the buffer/winlayout `nvim_state` payload. Always written on the
--- 8 reactive mutation events regardless of whether a session is active, so
--- tab state survives restarts even from cold-start no-session usage.
local M = {}

-- Allow tests to inject alternate dir (overrides cfg.data_dir lookup).
M._dir = nil

local path_util = require("workspace.util.path")

--- Return the directory holding state.json (uses cfg.data_dir).
---@return string
function M.dir()
  if M._dir then return M._dir end
  return path_util.data_dir()
end

--- Absolute path of state.json.
---@return string
function M.path()
  return M.dir() .. "/state.json"
end

local function ensure_dir()
  path_util.ensure_dir(M.dir())
end

--- Read state.json. Returns `nil, err` on missing/corrupt file (non-fatal).
---@return table|nil, string|nil
function M.read()
  local p = M.path()
  local f = io.open(p, "r")
  if not f then
    return nil, "no state file: " .. p
  end
  local raw = f:read("*a")
  f:close()
  if not raw or raw == "" then
    return nil, "empty state file"
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    require("workspace.util.log").error("state.persist.read: json decode error: " .. tostring(decoded))
    return nil, "json decode error"
  end
  return decoded, nil
end

--- Atomically write state.json (tmp + rename).
---@param snap table
---@return boolean, string|nil
function M.write(snap)
  if type(snap) ~= "table" then
    return false, "snap must be a table"
  end
  ensure_dir()
  local p   = M.path()
  local tmp = p .. ".tmp"
  local ok, encoded = pcall(vim.json.encode, snap)
  if not ok then
    return false, "json encode error: " .. tostring(encoded)
  end
  local f, err = io.open(tmp, "w")
  if not f then
    return false, "cannot open tmp: " .. tostring(err)
  end
  f:write(encoded)
  f:close()
  local rok, rerr = vim.uv.fs_rename(tmp, p)
  if not rok then
    return false, "rename failed: " .. tostring(rerr)
  end
  return true, nil
end

--- Test helper.
function M._reset()
  M._dir = nil
end

return M
