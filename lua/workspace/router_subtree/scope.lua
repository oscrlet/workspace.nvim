-- Resolve a search scope string to a list of root paths
local M = {}

--- Resolve a scope identifier to a list of directory roots.
---@param scope string  "tab" | "workspace" | "cwd" | "scoped" | "single"
---@return string[]
function M.resolve(scope)
  if scope == "tab" then
    local ok, tab_mod = pcall(require, "workspace.tab")
    if not ok then return {} end
    local projects = tab_mod.projects() or {}
    local roots = {}
    for _, p in ipairs(projects) do
      if p.root then table.insert(roots, p.root) end
    end
    return roots

  elseif scope == "workspace" then
    local ok, sess = pcall(require, "workspace.session")
    if not ok then return {} end
    local ids = sess.projects() or {}
    local registry = require("workspace.project.registry")
    local roots = {}
    for _, id in ipairs(ids) do
      local p = registry.get(id)
      if p and p.root then table.insert(roots, p.root) end
    end
    return roots

  elseif scope == "cwd" then
    return { vim.fn.getcwd() }

  else
    -- scoped / single scopes require prior ctx.workspace.search_roots
    -- set by the search_pick node; fall back to cwd
    return { vim.fn.getcwd() }
  end
end

return M
