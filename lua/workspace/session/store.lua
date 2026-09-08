--- workspace/session/store.lua
--- Atomic JSON IO for session files.
local M = {}

-- Allow tests to inject alternative dir.
M._dir = nil

local path_util = require("workspace.util.path")

--- Return session directory.
---@return string
function M.dir()
  if M._dir then return M._dir end
  return path_util.data_dir() .. "/sessions"
end

--- Return absolute path for a session file.
---@param name string
---@return string
function M.path(name)
  return M.dir() .. "/" .. name .. ".json"
end

--- Ensure session directory exists.
local function ensure_dir()
  path_util.ensure_dir(M.dir())
end

--- Read a session by name.
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

--- Atomically write session data.
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

  local rok, rerr = vim.uv.fs_rename(tmp, p)
  if not rok then
    return false, "rename failed: " .. tostring(rerr)
  end
  return true, nil
end

--- Delete a session file.
---@param name string
function M.delete(name)
  os.remove(M.path(name))
end

--- Rename a session.
---@param old string
---@param new string
---@return boolean, string|nil
function M.rename(old, new)
  local src = M.path(old)
  local dst = M.path(new)
  local ok, err = os.rename(src, dst)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

--- List all sessions in the directory.
---@return { name: string, modified_at: number, tab_count: number, project_count: number }[]
function M.list()
  ensure_dir()
  local d = M.dir()
  local results = {}
  -- Use vim.fn.glob to list *.json files.
  local pattern = d .. "/*.json"
  local files = vim.fn.glob(pattern, false, true)
  for _, filepath in ipairs(files) do
    local fname = vim.fs.basename(filepath):match("^(.*)%.json$")
    if fname then
      local mtime = vim.fn.getftime(filepath)
      local tab_count     = 0
      local project_count = 0
      local f = io.open(filepath, "r")
      if f then
        local raw = f:read("*a")
        f:close()
        local ok, decoded = pcall(vim.json.decode, raw)
        if ok and type(decoded) == "table" and type(decoded.tabs) == "table" then
          tab_count = #decoded.tabs
          local seen = {}
          for _, tab in ipairs(decoded.tabs) do
            if type(tab.project_ids) == "table" then
              for _, pid in ipairs(tab.project_ids) do
                if not seen[pid] then
                  seen[pid] = true
                  project_count = project_count + 1
                end
              end
            end
          end
        end
      end
      results[#results + 1] = {
        name          = fname,
        modified_at   = mtime,
        tab_count     = tab_count,
        project_count = project_count,
      }
    end
  end
  table.sort(results, function(a, b)
    return (a.modified_at or 0) > (b.modified_at or 0)
  end)
  return results
end

return M
