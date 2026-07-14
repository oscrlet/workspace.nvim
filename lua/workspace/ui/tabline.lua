--- workspace/ui/tabline.lua
--- Tabline UI helpers.
local M = {}

local tab_state = require("workspace.tab.state")
local project_mod = require("workspace.project")

--- Return display name for a tab.
--- Priority: tab.label > active project name > cwd basename > "Tab N"
---@param tabnr number
---@return string
function M.tab_name(tabnr)
  local tab = tab_state.by_tabnr(tabnr)

  -- If tab.label is set, use it
  if tab and tab.label and tab.label ~= "" then
    return tab.label
  end

  -- Try active project name
  if tab and tab.active_project_id then
    local proj = project_mod.get(tab.active_project_id)
    if proj and proj.name then
      return proj.name
    end
  end

  -- Fallback to cwd basename
  if tab and tab.cwd then
    local basename = vim.fn.fnamemodify(tab.cwd, ":t")
    if basename and basename ~= "" then
      return basename
    end
  end

  -- Last resort: "Tab N"
  return "Tab " .. tabnr
end

return M
