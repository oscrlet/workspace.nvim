--- Public root-scope queries for host integrations.
local M = {}

local function roots_for_projects(projects)
  local roots, seen = {}, {}
  for _, item in ipairs(projects) do
    local root = item and item.root
    if root and not seen[root] then
      seen[root] = true
      roots[#roots + 1] = root
    end
  end
  return roots
end

local function projects_for_ids(ids)
  local project = require("workspace.project")
  local projects = {}
  for _, id in ipairs(ids) do
    local item = project.get(id)
    if item then projects[#projects + 1] = item end
  end
  return projects
end

--- Return project roots for a tab (current tab when omitted).
---@param tabnr number|nil
---@return string[]
function M.tab_roots(tabnr)
  return roots_for_projects(require("workspace.tab").projects(tabnr))
end

--- Return the unique project roots in the current session.
---@return string[]
function M.session_roots()
  return roots_for_projects(projects_for_ids(require("workspace.session").projects()))
end

--- Return unique roots for the selected project ids.
---@param ids string[]|nil Omit to include every registered project.
---@return string[]
function M.project_roots(ids)
  local project = require("workspace.project")
  if ids == nil then
    return roots_for_projects(project.list())
  end
  return roots_for_projects(projects_for_ids(ids))
end

return M
