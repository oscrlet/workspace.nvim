-- Workspace ops sub-tree nodes (§3.6)
local M = {}

M.workspace_ops = {
  title = "Workspace Ops",
  items = {
    { id = "new_tab",     label = "New tab",               text = "new_tab New tab",              target_node = "workspace_ops_new_tab" },
    { id = "close_tab",   label = "Close current tab",     text = "close_tab Close current tab" },
    { id = "switch_tab",  label = "Switch tab",            text = "switch_tab Switch tab",         target_node = "workspace_ops_tab_list" },
    { id = "move_tab",    label = "Move tab (reorder)",    text = "move_tab Move tab (reorder)",   target_node = "workspace_ops_move_tab" },
    { id = "list",        label = "List tabs",             text = "list List tabs",                target_node = "workspace_ops_tab_list" },
    { id = "projects",    label = "All session projects",  text = "projects All session projects", target_node = "workspace_ops_projects" },
  },
  on_confirm = function(item)
    if item.id == "new_tab" then
      return "workspace_ops_new_tab"
    elseif item.id == "close_tab" then
      require("workspace.workspace").close_tab(nil)
      return nil
    elseif item.id == "switch_tab" or item.id == "list" then
      return "workspace_ops_tab_list"
    elseif item.id == "move_tab" then
      return "workspace_ops_move_tab"
    elseif item.id == "projects" then
      return "workspace_ops_projects"
    end
  end,
  -- F11: action menu.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_ops_new_tab = {
  title = "New Tab — Pick Initial Project",
  items = function()
    local result = {}
    for _, p in ipairs(require("workspace.project").list()) do
      result[#result + 1] = vim.tbl_extend("force", p, {
        label = p.name or p.id,
        text  = (p.name or p.id) .. " " .. (p.root or ""),
      })
    end
    table.insert(result, 1, { id = "__empty__", label = "Empty tab (no project)", text = "Empty tab (no project)" })
    return result
  end,
  on_confirm = function(item)
    if item.id == "__empty__" then
      require("workspace.workspace").new_tab({})
    else
      require("workspace.workspace").new_tab({ project_id = item.id })
    end
    return nil
  end,
  -- F11: project picker for new tab.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_ops_tab_list = {
  title = "Tabs",
  items = function()
    local result = {}
    for _, t in ipairs(require("workspace.workspace").tabs()) do
      result[#result + 1] = vim.tbl_extend("force", t, {
        text = (t.label or ("Tab " .. (t.order or ""))) .. " (" .. #(t.project_ids or {}) .. " projects)",
      })
    end
    return result
  end,
  preview = require("workspace.router_subtree.preview").tab,
  on_confirm = function(item)
    require("workspace.workspace").switch_tab(item.order)
    return nil
  end,
  actions = {
    { key = "<C-d>", desc = "Close",
      run = function(item) require("workspace.workspace").close_tab(item.order) end,
      after = "stay" },
    { key = "<C-r>", desc = "Rename",
      run = function(item)
        vim.ui.input({ prompt = "Label: " }, function(l)
          if l then require("workspace.tab").rename(item.order, l) end
        end)
      end, after = "stay" },
  },
  -- F11: tab list with detail preview.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_ops_move_tab = {
  title = "Move Tab (reorder)",
  items = function()
    local result = {}
    for _, t in ipairs(require("workspace.workspace").tabs()) do
      result[#result + 1] = vim.tbl_extend("force", t, {
        text = (t.label or ("Tab " .. (t.order or ""))) .. " (" .. #(t.project_ids or {}) .. " projects)",
      })
    end
    return result
  end,
  on_confirm = function(item)
    vim.ui.input({ prompt = "Move to position: " }, function(pos)
      local n = tonumber(pos)
      if n then require("workspace.workspace").reorder_tabs(item.order, n) end
    end)
    return nil
  end,
  -- F11: short list with input prompt.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_ops_projects = {
  title = "All Session Projects",
  items = function()
    local ids = require("workspace.session").projects()
    local registry = require("workspace.project.registry")
    local result = {}
    for _, id in ipairs(ids) do
      local p = registry.get(id)
      if p then
        result[#result + 1] = {
          id    = id,
          label = p.name or id,
          name  = p.name,
          root  = p.root,
          text  = (p.name or id) .. " " .. (p.root or ""),
        }
      end
    end
    return result
  end,
  preview = require("workspace.router_subtree.preview").project,
  on_confirm = function(item)
    require("workspace.session").focus_project(item.id)
    return nil
  end,
  -- F11: list with project preview.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

return M
