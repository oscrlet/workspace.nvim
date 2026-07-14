--- workspace/workspace/state.lua
--- Workspace-level state: active tab tracking.
local M = {}

local _active_tab_id = nil  -- uuid of active tab

--- Return all tabs sorted by order (delegates to tab.state).
---@return table[]
function M.tabs()
  return require("workspace.tab.state").all()
end

--- Get active tab uuid.
---@return string|nil
function M.active_tab_id()
  return _active_tab_id
end

--- Set active tab uuid.
---@param uuid string|nil
function M.set_active_tab_id(uuid)
  _active_tab_id = uuid
end

--- Reset (for testing).
function M._reset()
  _active_tab_id = nil
end

return M
