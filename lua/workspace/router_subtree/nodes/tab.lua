-- Tab sub-tree nodes (§3.5)
local M = {}

M.workspace_tab = {
  title = "Tab Actions (current tab)",
  items = {
    { id = "add_project",    label = "Add project",           text = "add_project Add project",           target_node = "workspace_project_list" },
    { id = "switch_project", label = "Switch active project", text = "switch_project Switch active project", target_node = "workspace_tab_projects" },
    { id = "remove_project", label = "Remove project",        text = "remove_project Remove project",       target_node = "workspace_tab_remove_project" },
    { id = "projects",       label = "List tab projects",     text = "projects List tab projects",          target_node = "workspace_tab_projects" },
    { id = "rename",         label = "Rename tab",            text = "rename Rename tab" },
    { id = "template_save",  label = "Save tab as template",  text = "template_save Save tab as template",  target_node = "workspace_tab_template_save" },
    { id = "template_load",  label = "Load tab template",     text = "template_load Load tab template",     target_node = "workspace_tab_template_load" },
  },
  on_confirm = function(item, ctx)
    ctx.workspace = ctx.workspace or {}
    if item.id == "add_project" then
      ctx.workspace.intent = "add_to_tab"
      return "workspace_project_list"
    elseif item.id == "switch_project" then
      ctx.workspace.intent = "switch_active"
      return "workspace_tab_projects"
    elseif item.id == "remove_project" then
      return "workspace_tab_remove_project"
    elseif item.id == "projects" then
      return "workspace_tab_projects"
    elseif item.id == "rename" then
      vim.ui.input({ prompt = "Tab label: " }, function(l)
        if l then require("workspace.tab").rename(nil, l) end
      end)
      return nil
    elseif item.id == "template_save" then
      return "workspace_tab_template_save"
    elseif item.id == "template_load" then
      return "workspace_tab_template_load"
    end
  end,
  -- F11: action menu.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_tab_projects = {
  title = "Tab Projects",
  items = function()
    local result = {}
    for _, p in ipairs(require("workspace.tab").projects()) do
      result[#result + 1] = vim.tbl_extend("force", p, {
        text = (p.name or p.id) .. " " .. (p.root or ""),
      })
    end
    return result
  end,
  preview = require("workspace.router_subtree.preview").project,
  on_confirm = function(item, ctx)
    ctx.workspace = ctx.workspace or {}
    local intent = ctx.workspace.intent or "switch_active"
    if intent == "switch_active" then
      require("workspace.tab").switch_active(item.id)
    elseif intent == "remove" then
      require("workspace.tab").remove_project(nil, item.id)
    end
    return nil
  end,
  actions = {
    { key = "<C-s>", desc = "Switch active",
      run = function(item) require("workspace.tab").switch_active(item.id) end,
      after = "close" },
    { key = "<C-d>", desc = "Remove from tab",
      run = function(item) require("workspace.tab").remove_project(nil, item.id) end,
      after = "stay" },
  },
  -- F11: list with preview.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_tab_remove_project = {
  title = "Remove Project from Tab",
  items = function()
    local result = {}
    for _, p in ipairs(require("workspace.tab").projects()) do
      result[#result + 1] = vim.tbl_extend("force", p, {
        text = (p.name or p.id) .. " " .. (p.root or ""),
      })
    end
    return result
  end,
  on_confirm = function(item)
    require("workspace.tab").remove_project(nil, item.id)
    return nil
  end,
  -- F11: short list.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_tab_template_save = {
  title = "Save Tab as Template",
  items = function()
    -- provide current tab name and existing template names as candidates
    local ok, tapi = pcall(require, "workspace.template.api")
    if not ok then return {} end
    local result = {}
    for _, t in ipairs(tapi.list()) do
      result[#result + 1] = vim.tbl_extend("force", t, {
        text = t.name or "",
      })
    end
    return result
  end,
  on_confirm = function(item)
    local ok, tapi = pcall(require, "workspace.template.api")
    if ok then tapi.save_as(item.name) end
    return nil
  end,
  actions = {
    { key = "<C-i>", desc = "Type new template name",
      run = function()
        vim.ui.input({ prompt = "Template name: " }, function(n)
          if n then
            local ok, tapi = pcall(require, "workspace.template.api")
            if ok then tapi.save_as(n) end
          end
        end)
      end, after = "close" },
  },
  -- F11: small action menu.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_tab_template_load = {
  title = "Load Tab Template",
  items = function()
    local ok, tapi = pcall(require, "workspace.template.api")
    if not ok then return {} end
    local result = {}
    for _, t in ipairs(tapi.list()) do
      result[#result + 1] = vim.tbl_extend("force", t, {
        text = t.name or "",
      })
    end
    return result
  end,
  on_confirm = function(item)
    local ok, tapi = pcall(require, "workspace.template.api")
    if ok then tapi.load(item.name) end
    return nil
  end,
  -- F11: small list.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

return M
