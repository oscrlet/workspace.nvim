--- workspace/tab/api.lua
--- High-level tab mutation API.
local M = {}

local state = require("workspace.tab.state")

local function events()
  return require("workspace.tab.events")
end

local function project_mod()
  return require("workspace.project")
end

--- Resolve tabnr: nil → current tab.
---@param tab_idx number|nil
---@return number
local function resolve_tabnr(tab_idx)
  if tab_idx then return tab_idx end
  return vim.api.nvim_get_current_tabpage()
end

--- Fire event, pcall-safe.
local function fire(name, data)
  pcall(function() events().fire(name, data) end)
end

--- Add a project_id to a tab (creates tab state if absent).
--- Pure data mutation: does not switch active or change cwd.
--- Higher-level callers (e.g. `add_project_to_active`) layer on the
--- IDE-style "first project becomes active" behaviour.
---@param tab_idx number|nil  nil = current
---@param project_id string
function M.add_project(tab_idx, project_id)
  local nr  = resolve_tabnr(tab_idx)
  local tab = state.ensure(nr)
  -- Deduplicate.
  for _, id in ipairs(tab.project_ids) do
    if id == project_id then return end
  end
  tab.project_ids[#tab.project_ids + 1] = project_id
  fire("ProjectAdded", { tabnr = nr, project_id = project_id })
end

--- Add project to active (current) tab. When the tab had no projects
--- before this add, focus the new project (set as active + :tcd to
--- its root). User-facing entry — picker confirms route through here.
---@param project_id string
function M.add_project_to_active(project_id)
  local nr = resolve_tabnr(nil)
  local tab = state.ensure(nr)
  local was_empty = #tab.project_ids == 0
  M.add_project(nil, project_id)
  if was_empty then
    M.switch_active(project_id)
  end
end

--- Remove a project_id from a tab.
---@param tab_idx number|nil
---@param project_id string
function M.remove_project(tab_idx, project_id)
  local nr  = resolve_tabnr(tab_idx)
  local tab = state.by_tabnr(nr)
  if not tab then return end
  local new = {}
  for _, id in ipairs(tab.project_ids) do
    if id ~= project_id then new[#new + 1] = id end
  end
  tab.project_ids = new
  if tab.active_project_id == project_id then
    tab.active_project_id = new[1]
  end
  fire("ProjectRemoved", { tabnr = nr, project_id = project_id })
end

--- Switch active project on a tab; :tcd to project root.
---@param project_id string
---@param tab_idx number|nil
function M.switch_active(project_id, tab_idx)
  local nr  = resolve_tabnr(tab_idx)
  local tab = state.ensure(nr)
  tab.active_project_id = project_id
  -- tcd to project root when available.
  local proj = project_mod().get(project_id)
  if proj and proj.root then
    local ok, err = pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(proj.root))
    if not ok then
      require("workspace.util.log").warn("switch_active tcd failed: " .. tostring(err))
    else
      tab.cwd = proj.root
    end
  end
  fire("ActiveChanged", { tabnr = nr, project_id = project_id })
end

--- Set cwd for a tab without switching active project.
---@param tab_idx number|nil
---@param path string
function M.set_cwd(tab_idx, path)
  local nr  = resolve_tabnr(tab_idx)
  local tab = state.ensure(nr)
  tab.cwd = path
  local ok, err = pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(path))
  if not ok then
    require("workspace.util.log").warn("set_cwd tcd failed: " .. tostring(err))
  end
  fire("CwdChanged", { tabnr = nr, cwd = path })
end

--- Return Project objects for a tab.
---@param tab_idx number|nil
---@return table[]
function M.projects(tab_idx)
  local nr  = resolve_tabnr(tab_idx)
  local tab = state.by_tabnr(nr)
  if not tab then return {} end
  local result = {}
  local pm = project_mod()
  for _, id in ipairs(tab.project_ids) do
    local proj = pm.get(id)
    if proj then result[#result + 1] = proj end
  end
  return result
end

--- Return TabSession for current tab.
---@return table
function M.current()
  return state.ensure(vim.api.nvim_get_current_tabpage())
end

--- Return root paths for all projects on a tab.
---@param tab_idx number|nil
---@return string[]
function M.scope_roots(tab_idx)
  local projs = M.projects(tab_idx)
  local roots = {}
  for _, p in ipairs(projs) do
    if p.root then roots[#roots + 1] = p.root end
  end
  return roots
end

--- Rename a tab (sets label).
---@param tab_idx number|nil
---@param label string
function M.rename(tab_idx, label)
  local nr  = resolve_tabnr(tab_idx)
  local tab = state.ensure(nr)
  tab.label = label
  fire("Renamed", { tabnr = nr, label = label })
end

--- Swap order fields between two tabs (by tabnr).
---@param from number tabnr
---@param to   number tabnr
function M.reorder(from, to)
  local ta = state.by_tabnr(from)
  local tb = state.by_tabnr(to)
  if ta and tb then
    ta.order, tb.order = tb.order, ta.order
    fire("Reordered", { from = from, to = to })
  end
end

return M
