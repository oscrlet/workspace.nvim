--- workspace/template/store.lua
--- Atomic JSON IO for template files.
local M = {}

-- Allow tests to inject alternative dir.
M._dir = nil

local path_util = require("workspace.util.path")

-- One-time legacy migration: templates/ -> tab_templates/.
-- Kept idempotent so users upgrading later still get migrated once.
local _migrated = false

--- Reset migration flag (test-only helper).
function M._reset_migration()
  _migrated = false
end

local function ensure_migrated(target)
  if _migrated then return end
  _migrated = true
  -- Skip migration if tests injected a custom dir.
  if M._dir then return end
  local legacy = path_util.data_dir() .. "/templates"
  local uv = vim.uv or vim.loop
  if uv.fs_stat(legacy) and not uv.fs_stat(target) then
    local ok = pcall(uv.fs_rename, legacy, target)
    if ok then
      pcall(function()
        require("workspace.util.log").info(
          "[workspace] migrated templates/ -> tab_templates/"
        )
      end)
    end
  end
end

--- Return template directory.
---@return string
function M.dir()
  if M._dir then return M._dir end
  local target = path_util.data_dir() .. "/tab_templates"
  ensure_migrated(target)
  return target
end

--- Return absolute path for a template file.
---@param name string
---@return string
function M.path(name)
  return M.dir() .. "/" .. name .. ".json"
end

--- Ensure template directory exists.
local function ensure_dir()
  path_util.ensure_dir(M.dir())
end

--- Read a template by name.
---@param name string
---@return table|nil, string|nil  data, err
function M.read(name)
  ensure_dir()
  local p = M.path(name)
  local f, err = io.open(p, "r")
  if not f then
    return nil, "cannot open " .. p .. ": " .. tostring(err)
  end
  local raw = f:read("*a")
  f:close()
  if not raw or raw == "" then
    return nil, "empty file"
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return nil, "json decode error: " .. tostring(decoded)
  end
  return decoded, nil
end

--- Atomically write template data.
---@param name string
---@param data table
---@return boolean, string|nil
function M.write(name, data)
  ensure_dir()
  local p   = M.path(name)
  local tmp = p .. ".tmp"

  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    return false, "json encode error: " .. tostring(encoded)
  end

  local f, err = io.open(tmp, "w")
  if not f then
    return false, "cannot open tmp: " .. tostring(err)
  end
  f:write(encoded)
  f:close()

  local rok, rerr = os.rename(tmp, p)
  if not rok then
    return false, "rename failed: " .. tostring(rerr)
  end
  return true, nil
end

--- Delete a template file.
---@param name string
---@return boolean, string|nil
function M.delete(name)
  local p = M.path(name)
  local ok = os.remove(p)
  if ok then
    return true, nil
  end
  return false, "failed to delete template"
end

--- List all templates in the directory.
---@return { name: string, modified_at: number }[]
function M.list()
  ensure_dir()
  local d = M.dir()
  local results = {}
  -- Use vim.fn.glob to list *.json files.
  local pattern = d .. "/*.json"
  local files = vim.fn.glob(pattern, false, true)
  for _, filepath in ipairs(files) do
    local fname = filepath:match("([^/]+)%.json$")
    if fname then
      local mtime = vim.fn.getftime(filepath)
      results[#results + 1] = {
        name        = fname,
        modified_at = mtime,
      }
    end
  end
  table.sort(results, function(a, b)
    return (a.modified_at or 0) > (b.modified_at or 0)
  end)
  return results
end

return M
