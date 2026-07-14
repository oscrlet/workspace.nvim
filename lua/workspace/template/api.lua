--- workspace/template/api.lua
--- High-level template API: save tab + load tab.
local M = {}

local store = require("workspace.template.store")
local tab_api = require("workspace.tab.api")
local tab_state = require("workspace.tab.state")

local function resolve_tabnr(tab_idx)
  if tab_idx then return tab_idx end
  return vim.api.nvim_get_current_tabpage()
end

--- Capture current tab state and save as template.
---@param name string
---@param tab_idx number|nil
---@return boolean, string|nil
function M.save_as(name, tab_idx)
  local nr = resolve_tabnr(tab_idx)
  local tab = tab_state.by_tabnr(nr)
  if not tab then
    return false, "tab not found"
  end

  local data = {
    cwd              = tab.cwd or vim.fn.getcwd(),
    project_ids      = vim.deepcopy(tab.project_ids or {}),
    active_project_id = tab.active_project_id,
    nvim_state       = tab.nvim_state or "",
  }

  local ok, err = store.write(name, data)
  if not ok then
    return false, err
  end
  return true, nil
end

--- Load template and create new tab with captured state.
---@param name string
---@return boolean, string|nil
function M.load(name)
  local data, err = store.read(name)
  if err ~= nil or not data then
    return false, err or "template not found"
  end

  -- Create new tab.
  local ws_api = require("workspace.workspace.api")
  local ok, tab_err = pcall(function()
    ws_api.new_tab({})
  end)
  if not ok then
    return false, "failed to create new tab: " .. tostring(tab_err)
  end

  local nr = vim.api.nvim_get_current_tabpage()
  local tab = tab_state.ensure(nr)
  if not tab then
    return false, "failed to initialize tab"
  end

  -- Restore cwd.
  if data.cwd and data.cwd ~= "" then
    pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(data.cwd))
    tab.cwd = data.cwd
  end

  -- Add projects.
  if data.project_ids and #data.project_ids > 0 then
    for _, pid in ipairs(data.project_ids) do
      tab_api.add_project(nr, pid)
    end
  end

  -- Switch active project if available.
  if data.active_project_id and data.active_project_id ~= "" then
    pcall(function()
      tab_api.switch_active(data.active_project_id, nr)
    end)
  end

  -- Persist nvim_state on the tab record; restore is handled by
  -- workspace/snapshot.lua's winlayout decoder, not here.
  if data.nvim_state and data.nvim_state ~= "" then
    tab.nvim_state = data.nvim_state
  end

  return true, nil
end

--- List all templates.
---@return { name: string, modified_at: number }[]
function M.list()
  return store.list()
end

--- Delete a template.
---@param name string
---@return boolean, string|nil
function M.delete(name)
  return store.delete(name)
end

return M
