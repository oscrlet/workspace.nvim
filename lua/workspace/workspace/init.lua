local M = {}

local api = require("workspace.workspace.api")
local snapshot = require("workspace.workspace.snapshot")

-- Re-export api functions
M.new_tab = api.new_tab
M.close_tab = api.close_tab
M.switch_tab = api.switch_tab
M.tabs = api.tabs
M.active = api.active
M.active_index = api.active_index
M.reorder_tabs = api.reorder_tabs

-- Re-export snapshot functions
M.snapshot = snapshot.snapshot
M.restore = snapshot.restore

return M
