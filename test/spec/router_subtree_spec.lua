-- Tests for workspace.router_subtree
-- Run via: PlenaryBustedDirectory test/spec

local stub_module = function(mod_path, tbl)
  package.loaded[mod_path] = tbl
end

describe("workspace.router_subtree", function()
  -- ------------------------------------------------------------------ setup
  before_each(function()
    -- Reset the modules under test so each test gets a fresh load
    package.loaded["workspace.router_subtree"] = nil
    package.loaded["workspace.router_subtree.nodes"] = nil
    package.loaded["workspace.router_subtree.nodes.workspace"] = nil
    package.loaded["workspace.router_subtree.nodes.project"] = nil
    package.loaded["workspace.router_subtree.nodes.session"] = nil
    package.loaded["workspace.router_subtree.nodes.tab"] = nil
    package.loaded["workspace.router_subtree.nodes.ops"] = nil
    package.loaded["workspace.router_subtree.nodes.search"] = nil
    package.loaded["workspace.router_subtree.scope"] = nil
    package.loaded["workspace.router_subtree.actions"] = nil

    -- Stub heavy runtime deps so require() doesn't blow up in headless
    stub_module("workspace.project", {
      list = function() return {} end,
      register = function() end,
      unregister = function() end,
      update = function() end,
      input_path_candidates = function() return {} end,
      discover = function() return {} end,
    })
    stub_module("workspace.session", {
      list = function() return {} end,
      projects = function() return {} end,
      load = function() end,
      save = function() end,
      delete = function() end,
      rename = function() end,
      path = function() return "" end,
      save_candidates = function() return {} end,
      focus_project = function() end,
      current_info = function() return nil end,
    })
    stub_module("workspace.tab", {
      projects = function() return {} end,
      add_project_to_active = function() end,
      switch_active = function() end,
      remove_project = function() end,
      rename = function() end,
    })
    stub_module("workspace.workspace", {
      new_tab = function() end,
      close_tab = function() end,
      switch_tab = function() end,
      move_tab = function() end,
      tabs = function() return {} end,
    })
    stub_module("workspace.ui.preview", {
      project_tree = function() return {} end,
      session_tree = function() return {} end,
      tab_detail   = function() return {} end,
    })
    stub_module("workspace.template.api", {
      list = function() return {} end,
      save_as = function() end,
      load = function() end,
    })
    stub_module("workspace", {
      config = { project = { auto_scan = { globs = {} } } },
    })

    -- Stub vim globals that are absent in --clean headless
    if not vim.fn.getcwd then
      vim.fn.getcwd = function() return "/tmp" end
    end
    if not vim.fn.setreg then
      vim.fn.setreg = function() end
    end
    if not vim.ui then
      vim.ui = { input = function() end }
    end
  end)

  -- ------------------------------------------------------------------ 1
  describe("subtree spec shape", function()
    it("require returns table with parent, entry, nodes", function()
      local spec = require("workspace.router_subtree")
      assert.is_table(spec)
      assert.equals("root", spec.parent)
      assert.is_table(spec.entry)
      assert.equals("workspace", spec.entry.id)
      assert.is_string(spec.entry.label)
      assert.is_table(spec.nodes)
    end)
  end)

  -- ------------------------------------------------------------------ 2
  describe("nodes table keys", function()
    it("contains all required top-level and sub-entry keys", function()
      local nodes = require("workspace.router_subtree.nodes")
      local required_keys = {
        "workspace",
        "workspace_project",
        "workspace_project_list",
        "workspace_project_add",
        "workspace_project_discover",
        "workspace_session",
        "workspace_session_list",
        "workspace_session_save",
        "workspace_tab",
        "workspace_tab_projects",
        "workspace_ops",
        "workspace_ops_new_tab",
        "workspace_ops_tab_list",
        "workspace_ops_projects",
        "workspace_search",
        "workspace_search_pick",
        "workspace_search_kind",
      }
      for _, k in ipairs(required_keys) do
        assert.is_table(nodes[k], "missing node key: " .. k)
      end
    end)

    it("entry node items cover project/session/tab/ops/search", function()
      local nodes = require("workspace.router_subtree.nodes")
      local ids = {}
      for _, item in ipairs(nodes.workspace.items) do
        ids[item.id] = true
      end
      for _, id in ipairs({ "project", "session", "tab", "ops", "search" }) do
        assert.is_true(ids[id], "workspace entry missing item id=" .. id)
      end
    end)
  end)

  -- ------------------------------------------------------------------ 3
  describe("scope.resolve", function()
    it("'cwd' scope returns table with getcwd result", function()
      local scope = require("workspace.router_subtree.scope")
      -- mock getcwd
      local orig = vim.fn.getcwd
      vim.fn.getcwd = function() return "/test/cwd" end
      local roots = scope.resolve("cwd")
      vim.fn.getcwd = orig
      assert.is_table(roots)
      assert.equals(1, #roots)
      assert.equals("/test/cwd", roots[1])
    end)

    it("'tab' scope returns table (may be empty when no projects)", function()
      local scope = require("workspace.router_subtree.scope")
      local roots = scope.resolve("tab")
      assert.is_table(roots)
    end)

    it("'workspace' scope returns table (may be empty when no session)", function()
      local scope = require("workspace.router_subtree.scope")
      local roots = scope.resolve("workspace")
      assert.is_table(roots)
    end)
  end)

  -- ------------------------------------------------------------------ 4
  describe("actions module", function()
    it("M.common has <C-d>, <C-r>, <C-y> entries", function()
      local actions = require("workspace.router_subtree.actions")
      assert.is_table(actions.common)
      assert.equals("<C-d>", actions.common.delete.key)
      assert.equals("<C-r>", actions.common.rename.key)
      assert.equals("<C-y>", actions.common.yank.key)
    end)

    it("factory functions return tables with key field", function()
      local actions = require("workspace.router_subtree.actions")
      local d = actions.delete_action(function() end)
      assert.equals("<C-d>", d.key)
      local r = actions.rename_action("Prompt: ", function() end)
      assert.equals("<C-r>", r.key)
      local y = actions.yank_action(function() return "" end)
      assert.equals("<C-y>", y.key)
    end)
  end)

  -- ------------------------------------------------------------------ 5
  describe("node spec required fields", function()
    local function check_node(id, node)
      assert.is_not_nil(node.title,
        id .. " missing title")
      local has_items  = node.items  ~= nil
      local has_source = node.source ~= nil
      assert.is_true(has_items or has_source,
        id .. " needs items or source")
      -- on_confirm is required for non-leaf nodes; leaf nodes may omit it
      -- but we enforce it where it logically exists
    end

    it("all nodes have title and items/source", function()
      local nodes = require("workspace.router_subtree.nodes")
      for id, node in pairs(nodes) do
        check_node(id, node)
      end
    end)

    it("workspace entry on_confirm returns workspace_<id>", function()
      local nodes = require("workspace.router_subtree.nodes")
      local ws = nodes.workspace
      assert.is_function(ws.on_confirm)
      assert.equals("workspace_project", ws.on_confirm({ id = "project" }))
      assert.equals("workspace_session", ws.on_confirm({ id = "session" }))
      assert.equals("workspace_tab",     ws.on_confirm({ id = "tab" }))
      assert.equals("workspace_ops",     ws.on_confirm({ id = "ops" }))
      assert.equals("workspace_search",  ws.on_confirm({ id = "search" }))
    end)

    it("workspace_project on_confirm returns workspace_project_<id>", function()
      local nodes = require("workspace.router_subtree.nodes")
      local proj = nodes.workspace_project
      assert.is_function(proj.on_confirm)
      assert.equals("workspace_project_list",
        proj.on_confirm({ id = "list" }))
      assert.equals("workspace_project_add",
        proj.on_confirm({ id = "add" }))
      assert.equals("workspace_project_discover",
        proj.on_confirm({ id = "discover" }))
    end)

    it("workspace_project_list on_confirm: search_scope sets ctx.workspace.search_roots", function()
      local nodes = require("workspace.router_subtree.nodes")
      local node = nodes.workspace_project_list
      local ctx = { workspace = { intent = "search_scope" } }
      local items = { { id = "p1", root = "/p1" }, { id = "p2", root = "/p2" } }
      local next_id = node.on_confirm(items, ctx)
      assert.equals("workspace_search_kind", next_id)
      assert.is_table(ctx.workspace.search_roots)
      assert.equals(2, #ctx.workspace.search_roots)
    end)

    it("workspace_search on_confirm: scoped sets intent and multi", function()
      local nodes = require("workspace.router_subtree.nodes")
      local node = nodes.workspace_search
      local ctx = {}
      local next_id = node.on_confirm({ id = "scoped" }, ctx)
      assert.equals("workspace_search_pick", next_id)
      assert.equals("search_scope", ctx.workspace.intent)
      assert.is_true(ctx.workspace.multi)
    end)

    it("workspace_search on_confirm: tab scope goes to search_kind", function()
      local nodes = require("workspace.router_subtree.nodes")
      local node = nodes.workspace_search
      local ctx = {}
      local next_id = node.on_confirm({ id = "tab" }, ctx)
      assert.equals("workspace_search_kind", next_id)
      assert.equals("tab", ctx.workspace.search_scope)
    end)

    -- 收口2 (T3) — 裁决6 + C-W5: the terminal kind menu becomes a normal
    -- router frame. on_confirm RESOLVES roots itself (裁决5) into
    -- ctx.search.dirs and returns the router leaf id so navigate frames it
    -- (back returns to the kind menu). No backend.pick / Snacks fallback.
    describe("workspace_search_kind → router leaf (收口2)", function()
      it("grep returns search_grep leaf and seeds ctx.search.dirs", function()
        local nodes = require("workspace.router_subtree.nodes")
        local node = nodes.workspace_search_kind
        local ctx = { workspace = { search_scope = "tab",
                                    search_roots = { "/a", "/b" } } }
        local next_id = node.on_confirm({ id = "grep" }, ctx)
        assert.equals("search_grep", next_id)
        assert.is_table(ctx.search)
        assert.same({ "/a", "/b" }, ctx.search.dirs)
      end)

      it("find returns search_find leaf", function()
        local nodes = require("workspace.router_subtree.nodes")
        local node = nodes.workspace_search_kind
        local ctx = { workspace = { search_scope = "tab",
                                    search_roots = { "/r" } } }
        local next_id = node.on_confirm({ id = "find" }, ctx)
        assert.equals("search_find", next_id)
        assert.same({ "/r" }, ctx.search.dirs)
      end)

      it("symbol returns search_symbol leaf", function()
        local nodes = require("workspace.router_subtree.nodes")
        local node = nodes.workspace_search_kind
        local ctx = { workspace = { search_scope = "workspace",
                                    search_roots = { "/r" } } }
        local next_id = node.on_confirm({ id = "symbol" }, ctx)
        assert.equals("search_symbol", next_id)
      end)

      it("does NOT call backend.pick or Snacks (C-W1)", function()
        local backend_called = false
        package.loaded["router.backend"] = {
          pick = function() backend_called = true end,
        }
        local snacks_called = false
        local prev = _G.Snacks
        _G.Snacks = { picker = {
          grep = function() snacks_called = true end,
          files = function() snacks_called = true end,
          lsp_workspace_symbols = function() snacks_called = true end,
        } }
        local nodes = require("workspace.router_subtree.nodes")
        local node = nodes.workspace_search_kind
        local ctx = { workspace = { search_scope = "tab",
                                    search_roots = { "/r" } } }
        node.on_confirm({ id = "grep" }, ctx)
        _G.Snacks = prev
        package.loaded["router.backend"] = nil
        assert.is_false(backend_called, "must not call backend.pick")
        assert.is_false(snacks_called, "must not call Snacks.picker.*")
      end)
    end)

    -- 收口3 (T3) — Q2 选项A: project_list <C-g>/<C-f> actions navigate via
    -- router (kind=open, to search leaf, dirs override) instead of hard
    -- Snacks.picker. after must be nil (run no longer closes/aborts; navigate
    -- reuses the project picker view in-place and pushes a back-able frame).
    describe("workspace_project_list <C-g>/<C-f> → router.navigate (收口3)", function()
      local function find_action(node, key)
        for _, a in ipairs(node.actions or {}) do
          if a.key == key then return a end
        end
      end

      it("<C-g> navigates open→search_grep with dirs override, after nil", function()
        local captured
        package.loaded["router"] = {
          navigate = function(nav) captured = nav end,
        }
        local nodes = require("workspace.router_subtree.nodes")
        local act = find_action(nodes.workspace_project_list, "<C-g>")
        assert.is_table(act, "<C-g> action missing")
        assert.is_nil(act.after, "<C-g> after must be nil (no close/abort)")
        act.run({ id = "p1", root = "/proj/a" })
        package.loaded["router"] = nil
        assert.is_table(captured)
        assert.equals("open", captured.kind)
        assert.equals("search_grep", captured.to_id)
        assert.same({ "/proj/a" }, captured.overrides.picker_opts.dirs)
      end)

      it("<C-f> navigates open→search_find with dirs override, after nil", function()
        local captured
        package.loaded["router"] = {
          navigate = function(nav) captured = nav end,
        }
        local nodes = require("workspace.router_subtree.nodes")
        local act = find_action(nodes.workspace_project_list, "<C-f>")
        assert.is_table(act, "<C-f> action missing")
        assert.is_nil(act.after, "<C-f> after must be nil")
        act.run({ id = "p2", root = "/proj/b" })
        package.loaded["router"] = nil
        assert.is_table(captured)
        assert.equals("open", captured.kind)
        assert.equals("search_find", captured.to_id)
        assert.same({ "/proj/b" }, captured.overrides.picker_opts.dirs)
      end)

      it("<C-g>/<C-f> do not call Snacks.picker (C-W1)", function()
        package.loaded["router"] = { navigate = function() end }
        local snacks_called = false
        local prev = _G.Snacks
        _G.Snacks = { picker = {
          grep = function() snacks_called = true end,
          files = function() snacks_called = true end,
        } }
        local nodes = require("workspace.router_subtree.nodes")
        local g = find_action(nodes.workspace_project_list, "<C-g>")
        local f = find_action(nodes.workspace_project_list, "<C-f>")
        g.run({ id = "p", root = "/r" })
        f.run({ id = "p", root = "/r" })
        _G.Snacks = prev
        package.loaded["router"] = nil
        assert.is_false(snacks_called, "must not call Snacks.picker.*")
      end)

      -- C-W4: domain-data actions (add_project_to_active) stay direct domain
      -- mutations (allowed); only navigation side-effects are routed.
      it("C-W4: <C-a> add-to-tab remains a direct domain mutation", function()
        local added = {}
        package.loaded["workspace.tab"] = {
          add_project_to_active = function(id) table.insert(added, id) end,
        }
        local nodes = require("workspace.router_subtree.nodes")
        local act = find_action(nodes.workspace_project_list, "<C-a>")
        assert.is_table(act)
        assert.equals("close", act.after)
        act.run({ id = "px", root = "/r" })
        package.loaded["workspace.tab"] = nil
        assert.same({ "px" }, added)
      end)
    end)
  end)

  -- ------------------------------------------------------------------ 6
  -- FIX_PLAN F11: every node spec must declare `on_back` (string or
  -- function) and at least one of `picker_opts` / `layout`.
  describe("F11 schema fields", function()
    -- All node ids registered across the six node modules.
    local ids = {
      "workspace",
      "workspace_project",
      "workspace_project_list",
      "workspace_project_add",
      "workspace_project_discover",
      "workspace_session",
      "workspace_session_list",
      "workspace_session_save",
      "workspace_session_delete",
      "workspace_session_info",
      "workspace_tab",
      "workspace_tab_projects",
      "workspace_tab_remove_project",
      "workspace_tab_template_save",
      "workspace_tab_template_load",
      "workspace_ops",
      "workspace_ops_new_tab",
      "workspace_ops_tab_list",
      "workspace_ops_move_tab",
      "workspace_ops_projects",
      "workspace_search",
      "workspace_search_pick",
      "workspace_search_kind",
    }

    it("each node declares non-nil on_back (string or function)", function()
      local nodes = require("workspace.router_subtree.nodes")
      for _, id in ipairs(ids) do
        local node = nodes[id]
        assert.is_table(node, id .. " missing")
        assert.is_not_nil(node.on_back, id .. " missing on_back")
        local t = type(node.on_back)
        assert.is_true(t == "string" or t == "function",
          id .. " on_back must be string or function, got " .. t)
      end
    end)

    it("each node declares picker_opts or layout", function()
      local nodes = require("workspace.router_subtree.nodes")
      for _, id in ipairs(ids) do
        local node = nodes[id]
        local has_pick   = node.picker_opts ~= nil
        local has_layout = node.layout      ~= nil
        assert.is_true(has_pick or has_layout,
          id .. " needs picker_opts or layout")
        if has_pick then
          assert.is_table(node.picker_opts,
            id .. " picker_opts must be table")
        end
        if has_layout then
          local t = type(node.layout)
          assert.is_true(t == "string" or t == "table",
            id .. " layout must be string or table, got " .. t)
        end
      end
    end)
  end)
end)
