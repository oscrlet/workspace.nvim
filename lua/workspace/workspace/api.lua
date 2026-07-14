--- workspace/workspace/api.lua
--- Workspace-level tab lifecycle operations.
local M = {}

local ws_state = require("workspace.workspace.state")
local tab_state = require("workspace.tab.state")
local tab_api   = require("workspace.tab.api")

--- Open a new vim tab and register it.
---@param opts { project_id?: string, label?: string, cwd?: string }|nil
---@return table TabSession
function M.new_tab(opts)
  opts = opts or {}
  vim.cmd("tabnew")
  local nr  = vim.api.nvim_get_current_tabpage()
  local tab = tab_state.ensure(nr)
  if opts.label then
    tab.label = opts.label
  end
  if opts.cwd then
    tab_api.set_cwd(nr, opts.cwd)
  end
  if opts.project_id then
    tab_api.add_project(nr, opts.project_id)
    tab_api.switch_active(opts.project_id, nr)
  end
  ws_state.set_active_tab_id(tab.id)
  return tab
end

--- Close a tab by index (nil = current).
---@param idx number|nil  1-based vim tab index
function M.close_tab(idx)
  if idx then
    vim.cmd(idx .. "tabclose")
  else
    vim.cmd("tabclose")
    -- Clean up state for closed tab.
    -- We can't know which tabnr was removed easily; let autocmds handle via TabClosed.
  end
end

--- Switch to a tab by 1-based index.
---@param idx number
function M.switch_tab(idx)
  vim.cmd(idx .. "tabnext")
  local nr  = vim.api.nvim_get_current_tabpage()
  local tab = tab_state.ensure(nr)
  ws_state.set_active_tab_id(tab.id)
end

--- Return all tabs sorted by order.
---@return table[]
function M.tabs()
  return ws_state.tabs()
end

--- Return the active TabSession (current vim tabpage).
---@return table
function M.active()
  local nr = vim.api.nvim_get_current_tabpage()
  return tab_state.ensure(nr)
end

--- Return 1-based index of current tab in sorted tabs list.
---@return number
function M.active_index()
  local active_nr = vim.api.nvim_get_current_tabpage()
  local tabs = ws_state.tabs()
  for i, t in ipairs(tabs) do
    if t.tabnr == active_nr then return i end
  end
  return 1
end

--- Reorder tabs: swap order fields between two 1-based indices.
---@param from number
---@param to   number
function M.reorder_tabs(from, to)
  local tabs = ws_state.tabs()
  local ta = tabs[from]
  local tb = tabs[to]
  if ta and tb then
    tab_api.reorder(ta.tabnr, tb.tabnr)
    vim.cmd(to .. "tabmove")
  end
end

return M
