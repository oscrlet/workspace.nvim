--- workspace/project/api.lua
--- Higher-level project operations layered on top of the registry.
local M = {}

local registry = require("workspace.project.registry")

--- Move (re-root) an existing project to a new on-disk path.
--- Validates inputs then delegates to `registry.update`, which already
--- persists state and fires the `WorkspaceProjectUpdated` autocmd.
---
---@param id string
---@param new_path string  Path to a directory that already exists.
---@return boolean ok
---@return string|nil err
function M.move(id, new_path)
  if type(id) ~= "string" or id == "" then
    return false, "move: id must be a non-empty string"
  end
  if type(new_path) ~= "string" or new_path == "" then
    return false, "move: new_path must be a non-empty string"
  end

  local proj = registry.get(id)
  if not proj then
    return false, "move: project '" .. id .. "' not found"
  end

  -- Expand ~/ and resolve to a real path; reject relative paths that don't
  -- resolve to an existing directory.
  local expanded = vim.fn.expand(new_path)
  local real = (vim.uv and vim.uv.fs_realpath and vim.uv.fs_realpath(expanded)) or expanded

  if vim.fn.isdirectory(real) ~= 1 then
    return false, "move: directory does not exist: " .. tostring(new_path)
  end

  local ok, err = pcall(registry.update, id, { root = real })
  if not ok then
    return false, "move: registry update failed: " .. tostring(err)
  end
  return true, nil
end

return M
