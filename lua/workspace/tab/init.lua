local M = {}

local api = require("workspace.tab.api")
local state = require("workspace.tab.state")

-- Re-export api functions
M.add_project = api.add_project
M.add_project_to_active = api.add_project_to_active
M.remove_project = api.remove_project
M.switch_active = api.switch_active
M.set_cwd = api.set_cwd
M.projects = api.projects
M.current = api.current
M.scope_roots = api.scope_roots
M.rename = api.rename
M.reorder = api.reorder

-- Re-export state accessors
M.all = state.all
M.by_uuid = state.by_uuid
M.by_tabnr = state.by_tabnr

return M
