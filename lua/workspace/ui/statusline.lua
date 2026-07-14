--- workspace/ui/statusline.lua
--- Statusline UI helpers.
local M = {}

local session_api = require("workspace.session.api")
local tab_api = require("workspace.tab.api")
local tabline = require("workspace.ui.tabline")

--- Return current session name.
---@return string|nil
function M.session_name()
  local name = session_api.current()
  if not name or name == "" then
    return nil
  end
  return vim.fn.fnamemodify(name, ":t")
end

--- Return label for current tab.
---@return string
function M.tab_label()
  local current_tabnr = vim.api.nvim_get_current_tabpage()
  return tabline.tab_name(current_tabnr)
end

--- Return name of current tab's active project.
---@return string|nil
function M.active_project()
  local tab = tab_api.current()
  if not tab or not tab.active_project_id then
    return nil
  end
  local proj = require("workspace.project").get(tab.active_project_id)
  if proj then
    return proj.name
  end
  return nil
end

--- Return count of projects on current tab.
---@return number
function M.project_count()
  local tab = tab_api.current()
  if not tab or not tab.project_ids then
    return 0
  end
  return #tab.project_ids
end

return M
