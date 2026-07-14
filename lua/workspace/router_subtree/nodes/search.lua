-- Search sub-tree nodes (§3.7)
local M = {}

M.workspace_search = {
  title = "Search",
  items = {
    { id = "tab",       label = "Current tab projects",         text = "tab Current tab projects",                 target_node = "workspace_search_kind" },
    { id = "workspace", label = "All session projects",         text = "workspace All session projects",           target_node = "workspace_search_kind" },
    { id = "scoped",    label = "Pick projects (multi-select)", text = "scoped Pick projects (multi-select)",      target_node = "workspace_search_pick" },
    { id = "single",    label = "Pick one project",             text = "single Pick one project",                  target_node = "workspace_search_pick" },
    { id = "cwd",       label = "Current directory",            text = "cwd Current directory",                    target_node = "workspace_search_kind" },
  },
  on_confirm = function(item, ctx)
    ctx.workspace = ctx.workspace or {}
    ctx.workspace.search_scope = item.id
    if item.id == "scoped" or item.id == "single" then
      ctx.workspace.intent = "search_scope"
      ctx.workspace.multi  = (item.id == "scoped")
      return "workspace_search_pick"
    end
    return "workspace_search_kind"
  end,
  -- F11: scope chooser action menu.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_search_pick = {
  title = function(ctx)
    return (ctx.workspace and ctx.workspace.multi)
      and "Pick Projects (Tab=multi)"
      or  "Pick Project"
  end,
  items = function()
    local ids = require("workspace.session").projects()
    local registry = require("workspace.project.registry")
    local result = {}
    for _, id in ipairs(ids) do
      local p = registry.get(id)
      if p then
        result[#result + 1] = { id = id, label = p.name or id, name = p.name, root = p.root,
          text = (p.name or id) .. " " .. (p.root or "") }
      end
    end
    return result
  end,
  multi_select = function(ctx) return ctx.workspace and ctx.workspace.multi end,
  preview = require("workspace.router_subtree.preview").project,
  on_confirm = function(items, ctx)
    if type(items) == "table" and items.id ~= nil then
      items = { items }
    end
    ctx.workspace = ctx.workspace or {}
    local roots = vim.tbl_map(function(p) return p.root end, items)
    ctx.workspace.search_roots = roots
    -- Preset kind (a direct keymap entered the pick with intent already set):
    -- skip the kind menu and land on the matching router leaf scoped to the
    -- picked roots. The leaf's dirs_picker_opts reads ctx.search.dirs.
    local kind = ctx.workspace.search_kind
    local leaf = kind and ({ grep = "search_grep", find = "search_find",
                             symbol = "search_symbol" })[kind]
    if leaf then
      ctx.search = ctx.search or {}
      ctx.search.dirs = roots
      return leaf
    end
    return "workspace_search_kind"
  end,
  -- F11: project picker with preview.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_search_kind = {
  title = function(ctx)
    local scope = (ctx.workspace and ctx.workspace.search_scope) or "?"
    return "Kind (scope=" .. scope .. ")"
  end,
  items = {
    { id = "grep",   label = "Live grep",               text = "grep Live grep" },
    { id = "find",   label = "Find files",              text = "find Find files" },
    { id = "symbol", label = "Workspace symbols (LSP)", text = "symbol Workspace symbols (LSP)" },
  },
  -- 收口2 (T3) — 裁决5 + 裁决6 + C-W5: resolve roots HERE (workspace owns
  -- scope→roots), seed them into ctx.search.dirs, then return the router
  -- search leaf id. router's navigate frames the terminal search as a normal
  -- stack frame (back returns to this kind menu); the leaf's
  -- dirs_picker_opts(ctx) reads ctx.search.dirs. No backend.pick / Snacks
  -- fallback — volt covers grep/files/lsp_workspace_symbols (C-W1).
  on_confirm = function(item, ctx)
    ctx.workspace = ctx.workspace or {}
    local roots = ctx.workspace.search_roots
              or require("workspace.router_subtree.scope")
                   .resolve(ctx.workspace.search_scope)
    local leaf = ({ grep = "search_grep", find = "search_find",
                    symbol = "search_symbol" })[item.id]
    if not leaf then return nil end
    ctx.search = ctx.search or {}
    -- search_symbol (lsp_workspace_symbols) is not dir-scoped, but seeding
    -- dirs is harmless and keeps grep/find consistent.
    ctx.search.dirs = roots
    return leaf
  end,
  -- F11: kind chooser (3 items) — compact select layout.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

return M
