--- workspace/session/state.lua
--- Current session name + lockfile management.
local M = {}

local path_util = require("workspace.util.path")

local _current = nil  -- current session name

--- Current session name.
---@return string|nil
function M.current()
  return _current
end

--- Set current session name.
---@param name string|nil
function M.set_current(name)
  _current = name
end

--- Lock dir path.
---@return string
local function lock_dir()
  return path_util.data_dir() .. "/sessions/.locks"
end

--- Lock file path for a session.
---@param name string
---@return string
local function lock_path(name)
  return lock_dir() .. "/" .. name .. ".lock"
end

--- Acquire lock for session name.
--- Returns false if an existing lockfile contains a live PID.
---@param name string
---@return boolean
function M.acquire_lock(name)
  vim.fn.mkdir(lock_dir(), "p")
  local p = lock_path(name)
  local f = io.open(p, "r")
  if f then
    local pid_str = f:read("*a")
    f:close()
    local pid = tonumber(pid_str)
    if pid then
      -- Signal 0 probes process existence without a POSIX shell command.
      -- EPERM also means the process exists, but belongs to another user.
      local result, _, code = vim.uv.kill(pid, 0)
      local alive = result == 0 or code == "EPERM"
      if alive then
        return false
      end
    end
    -- Stale lock; remove it.
    os.remove(p)
  end
  -- Write our PID.
  local wf, err = io.open(p, "w")
  if not wf then
    require("workspace.util.log").warn("acquire_lock: cannot write lockfile: " .. tostring(err))
    return true  -- Non-fatal; allow operation.
  end
  wf:write(tostring(vim.fn.getpid()))
  wf:close()
  return true
end

--- Release lock for session name.
---@param name string
function M.release_lock(name)
  os.remove(lock_path(name))
end

--- Reset (for testing).
function M._reset()
  _current = nil
end

return M
