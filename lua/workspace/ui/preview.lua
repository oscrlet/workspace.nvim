--- workspace/ui/preview.lua
--- Preview UI helpers for router.nvim integration.
local M = {}

local tab_state = require("workspace.tab.state")
local tab_api = require("workspace.tab.api")
local session_api = require("workspace.session.api")
local project_mod = require("workspace.project")

--- Run an external command and return its output if non-empty and successful.
---@param argv string[]
---@return string[]|nil
local function run_systemlist(argv)
  local ok, out = pcall(vim.fn.systemlist, argv)
  if ok and type(out) == "table" and #out > 0 and vim.v.shell_error == 0 then
    return out
  end
  return nil
end

--- Builtin readdir-based tree fallback.
---@param expanded_root string
---@return string[]
local function builtin_tree(expanded_root)
  local ok_readdir, entries = pcall(vim.fn.readdir, expanded_root)
  if ok_readdir and type(entries) == "table" then
    local result = { expanded_root, "" }
    table.sort(entries)
    for _, entry in ipairs(entries) do
      local path = expanded_root .. "/" .. entry
      local marker = vim.fn.isdirectory(path) == 1 and "/" or ""
      result[#result + 1] = "  " .. entry .. marker
    end
    return result
  end
  return { "(unable to read " .. expanded_root .. ")" }
end

--- Return tree lines for a project root.
--- Honors `cfg.project.preview.command` ("eza" | "tree" | "fd" | "builtin").
--- Missing binary falls back to next available, then builtin readdir.
---@param root string
---@param depth number|nil  defaults to 2
---@return string[]
function M.project_tree(root, depth)
  if not root or root == "" then
    return { "(empty root)" }
  end

  local expanded_root = vim.fn.expand(root)
  if vim.fn.isdirectory(expanded_root) == 0 then
    return { "(not a directory: " .. expanded_root .. ")" }
  end

  depth = depth or 2

  local cmd_pref = "eza"
  local ok_cfg, cfg = pcall(function() return require("workspace.config").get() end)
  if ok_cfg and cfg and cfg.project and cfg.project.preview and cfg.project.preview.command then
    cmd_pref = cfg.project.preview.command
  end

  local function try_eza()
    if vim.fn.executable("eza") == 1 then
      return run_systemlist({ "eza", "--tree", "--level=" .. depth, "--color=never", expanded_root })
    end
  end
  local function try_tree()
    if vim.fn.executable("tree") == 1 then
      return run_systemlist({ "tree", "-L", tostring(depth), "--noreport", expanded_root })
    end
  end
  local function try_fd()
    if vim.fn.executable("fd") == 1 then
      return run_systemlist({ "fd", ".", expanded_root, "--max-depth", tostring(depth) })
    end
  end

  -- Order: preferred → other binaries → builtin.
  local order
  if cmd_pref == "tree" then
    order = { try_tree, try_eza, try_fd }
  elseif cmd_pref == "fd" then
    order = { try_fd, try_eza, try_tree }
  elseif cmd_pref == "builtin" then
    order = {}
  else -- "eza" (default) or unknown
    order = { try_eza, try_tree, try_fd }
  end

  for _, fn in ipairs(order) do
    local out = fn()
    if out then return out end
  end

  return builtin_tree(expanded_root)
end

--- Return tree lines showing tabs and projects in a session.
---@param name string
---@return string[]
function M.session_tree(name)
  if not name or name == "" then
    return { "(empty session name)" }
  end

  local result = { "Session: " .. name }

  -- Load session to get its tabs
  local store = require("workspace.session.store")
  local ok, data = pcall(store.read, name)
  if not ok or not data then
    result[#result + 1] = "  (unable to load session)"
    return result
  end

  -- Extract tabs from snapshot
  if not data.tabs or not type(data.tabs) == "table" then
    result[#result + 1] = "  (no tabs in snapshot)"
    return result
  end

  for i, tab_snap in ipairs(data.tabs) do
    local tab_label = tab_snap.label or ("Tab " .. (tab_snap.order or i))
    result[#result + 1] = "  Tab " .. i .. ": " .. tab_label
    if tab_snap.project_ids and type(tab_snap.project_ids) == "table" then
      for _, proj_id in ipairs(tab_snap.project_ids) do
        local proj = project_mod.get(proj_id)
        local proj_name = proj and proj.name or proj_id
        if proj_id == tab_snap.active_project_id then
          result[#result + 1] = "    * " .. proj_name
        else
          result[#result + 1] = "      " .. proj_name
        end
      end
    end
  end

  return result
end

--- Return detail lines for a tab.
---@param tab table TabSession
---@return string[]
function M.tab_detail(tab)
  local result = {}

  if not tab then
    return { "(no tab)" }
  end

  -- cwd
  result[#result + 1] = "cwd: " .. (tab.cwd or "(none)")

  -- project list
  local proj_names = {}
  if tab.project_ids and type(tab.project_ids) == "table" then
    for _, proj_id in ipairs(tab.project_ids) do
      local proj = project_mod.get(proj_id)
      local name = proj and proj.name or proj_id
      proj_names[#proj_names + 1] = name
    end
  end
  result[#result + 1] = "projects: " .. table.concat(proj_names, ", ")

  -- active project
  local active_name = "(none)"
  if tab.active_project_id then
    local proj = project_mod.get(tab.active_project_id)
    active_name = proj and proj.name or tab.active_project_id
  end
  result[#result + 1] = "active: " .. active_name

  return result
end

return M
