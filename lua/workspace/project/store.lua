--- workspace/project/store.lua
--- Atomic JSON IO for projects.json.
--- Path is overridable via M._path for unit tests.
local M = {}

-- Allow tests to inject an alternative path.
M._path = nil

--- Resolve the absolute path to projects.json. Honors cfg.data_dir via
--- workspace.util.path.data_dir() so tests and host setup overrides apply.
---@return string
function M.path()
  if M._path then return M._path end
  return require("workspace.util.path").data_dir() .. "/projects.json"
end

--- Ensure parent directory exists.
---@param filepath string
local function ensure_dir(filepath)
  local dir = vim.fs.dirname(filepath)
  if dir then
    vim.fn.mkdir(dir, "p")
  end
end

--- Read and return store data. Returns default when file missing.
--- On corrupt JSON: notify ERROR, attempt .bak restore, return default on failure.
---@return { version: integer, projects: table }
function M.read()
  local default = { version = 1, projects = {} }
  local p = M.path()

  local f, err = io.open(p, "r")
  if not f then
    -- File not found is normal on first run.
    return default
  end

  local raw = f:read("*a")
  f:close()

  if raw == nil or raw == "" then
    return default
  end

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    vim.notify(
      string.format("[workspace] projects.json corrupt: %s — attempting backup restore", tostring(decoded)),
      vim.log.levels.ERROR
    )
    local restored = M.recover_from_bak()
    if restored then
      return M.read()
    end
    return default
  end

  -- Ensure required keys exist.
  if type(decoded.projects) ~= "table" then decoded.projects = {} end
  if type(decoded.version) ~= "number" then decoded.version = 1 end
  return decoded
end

--- Atomically write `data` to projects.json via tmp+rename.
---@param data table
---@return boolean ok, string? err
function M.write(data)
  local p = M.path()
  ensure_dir(p)

  local encoded
  local ok, result = pcall(vim.json.encode, data)
  if not ok then
    return false, "json encode error: " .. tostring(result)
  end
  encoded = result

  -- Write to a sibling .tmp file then rename atomically.
  local tmp = p .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then
    return false, "cannot open tmp file: " .. tostring(err)
  end
  f:write(encoded)
  f:close()

  -- Write backup of current file before replacing.
  local bak = p .. ".bak"
  local cur = io.open(p, "r")
  if cur then
    local contents = cur:read("*a")
    cur:close()
    local bf = io.open(bak, "w")
    if bf then
      bf:write(contents)
      bf:close()
    end
  end

  -- Atomic rename.
  local rok, rerr = vim.uv.fs_rename(tmp, p)
  if not rok then
    return false, "rename failed: " .. tostring(rerr)
  end

  return true, nil
end

--- Attempt to restore projects.json from .bak.
---@return boolean  true if restore succeeded
function M.recover_from_bak()
  local p = M.path()
  local bak = p .. ".bak"

  local f = io.open(bak, "r")
  if not f then return false end
  local raw = f:read("*a")
  f:close()

  -- Validate backup is parseable JSON.
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    vim.notify("[workspace] .bak also corrupt — starting fresh", vim.log.levels.WARN)
    return false
  end

  -- Overwrite main file with backup contents.
  local wf, werr = io.open(p, "w")
  if not wf then
    vim.notify("[workspace] cannot write restored backup: " .. tostring(werr), vim.log.levels.ERROR)
    return false
  end
  wf:write(raw)
  wf:close()

  vim.notify("[workspace] projects.json restored from backup", vim.log.levels.WARN)
  return true
end

return M
