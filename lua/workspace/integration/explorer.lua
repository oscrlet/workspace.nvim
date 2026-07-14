--- workspace/integration/explorer.lua
--- Snacks.explorer integration (Scheme C).
---
--- When the active project on the current tab changes, reposition any open
--- Snacks.explorer sidebar to the new project's root. Also exposes
--- `pick_root_for_explorer()` for a quick picker that switches the explorer's
--- root WITHOUT mutating the tab's active project.
local M = {}

--- Detect whether a Snacks.explorer picker is currently open.
--- Exposed (M._tree_open) so specs can stub it.
function M._tree_open()
  local ok, snacks = pcall(function() return _G.Snacks end)
  if not ok or not snacks or not snacks.picker or not snacks.picker.get then
    return false
  end
  local pickers = snacks.picker.get({ source = "explorer" })
  return pickers and pickers[1] ~= nil
end

local function call_explorer(opts)
  local snacks = _G.Snacks
  if not snacks or not snacks.picker or not snacks.picker.explorer then return end
  pcall(snacks.picker.explorer, opts or {})
end

--- Configure Snacks.explorer integration. Idempotent.
function M.setup()
  local cfg = require("workspace.config").get()
  local exp_cfg = (cfg.ui and cfg.ui.explorer) or {}

  if exp_cfg.auto_follow_active_project == false then
    -- Opt out: tear down any prior augroup and bail.
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceExplorerFollow")
    return
  end

  local group = vim.api.nvim_create_augroup("WorkspaceExplorerFollow", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "WorkspaceTabActiveChanged",
    callback = function(args)
      if not M._tree_open() then return end

      local data = (args and args.data) or {}
      local project_id = data.project_id
      if not project_id then return end

      local root
      local ok_pm, pm = pcall(require, "workspace.project")
      if ok_pm and pm and pm.get then
        local p = pm.get(project_id)
        if p and p.root then root = p.root end
      end
      if not root or root == "" then return end

      pcall(call_explorer, { cwd = root })
    end,
  })
end

--- Picker: choose a project from the current tab's project list and reposition
--- Snacks.explorer to that root. Does NOT change the tab's active project.
function M.pick_root_for_explorer()
  local tab = require("workspace.tab")
  local projects = tab.projects() or {}
  if #projects == 0 then
    vim.notify("[workspace] no projects on this tab", vim.log.levels.WARN)
    return
  end

  vim.ui.select(projects, {
    prompt = "Explorer root:",
    format_item = function(p)
      return (p.name or p.id or "?") .. "  " .. (p.root or "")
    end,
  }, function(choice)
    if not choice or not choice.root then return end
    call_explorer({ cwd = choice.root })
  end)
end

return M
