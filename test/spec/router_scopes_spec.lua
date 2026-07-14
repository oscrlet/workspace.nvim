-- Stub the workspace data APIs + router.scope so we can assert registration
-- and the dirs/chip each scope's get() delivers, without a live workspace.
local function setup_stubs()
  package.loaded["router.scope"] = {
    _r = {},
    register = function(self_or_opt, maybe_opt)
      -- support module-style call M.register(opt)
      local opt = maybe_opt or self_or_opt
      table.insert(package.loaded["router.scope"]._r, opt)
    end,
  }
  -- 收口1: choose_project now navigates a two-node router chain instead of
  -- calling backend.pick + writing router._skip_next_abort. Stub router so we
  -- can capture register_node specs and navigate declarations.
  package.loaded["router"] = {
    _nodes = {},
    _navs  = {},
    register_node = function(id, spec)
      package.loaded["router"]._nodes[id] = spec
    end,
    navigate = function(nav)
      table.insert(package.loaded["router"]._navs, nav)
    end,
  }
  package.loaded["router.backend"] = {
    pick = function() error("backend.pick must not be called (收口1)") end,
  }
  package.loaded["workspace.tab"] = {
    scope_roots = function() return { "/tab/a", "/tab/b" } end,
    projects    = function() return { "p1" } end,
  }
  package.loaded["workspace.session"] = {
    projects = function() return { "p1", "p2" } end,
  }
  package.loaded["workspace.workspace"] = {
    tabs = function() return { { tabnr = 1 } } end,
  }
  package.loaded["workspace.project.registry"] = {
    get  = function(id) return { id = id, name = id .. "!", root = "/r/" .. id } end,
    list = function() return { { id = "g", name = "G", root = "/g" } } end,
  }
  package.loaded["workspace.integration.router_scopes"] = nil
  return require("workspace.integration.router_scopes")
end

describe("workspace router_scopes", function()
  it("registers tab / session / project scopes", function()
    local rs = setup_stubs()
    rs.register()
    local ids = {}
    for _, o in ipairs(package.loaded["router.scope"]._r) do ids[#ids + 1] = o.id end
    assert.same({ "ws_tab", "ws_session", "ws_project" }, ids)
  end)

  it("ws_tab get delivers all current-tab roots + 'tab' chip", function()
    local rs = setup_stubs()
    rs.register()
    local opt
    for _, o in ipairs(package.loaded["router.scope"]._r) do if o.id == "ws_tab" then opt = o end end
    local dirs, chip
    opt.get(function(d, c) dirs = d; chip = c end)
    assert.same({ "/tab/a", "/tab/b" }, dirs)
    assert.equals("tab", chip)
  end)

  it("ws_session get delivers session project roots + 'session' chip", function()
    local rs = setup_stubs()
    rs.register()
    local opt
    for _, o in ipairs(package.loaded["router.scope"]._r) do if o.id == "ws_session" then opt = o end end
    local dirs, chip
    opt.get(function(d, c) dirs = d; chip = c end)
    assert.same({ "/r/p1", "/r/p2" }, dirs)
    assert.equals("session", chip)
  end)

  it("ws_project get is interactive (a function, no immediate dirs)", function()
    local rs = setup_stubs()
    rs.register()
    local opt
    for _, o in ipairs(package.loaded["router.scope"]._r) do if o.id == "ws_project" then opt = o end end
    assert.is_function(opt.get)
  end)

  -- 收口1 进取档: choose_project = two-node router chain (ws_scope_source →
  -- ws_scope_project), stack frames (back-able), cb threaded via module-level
  -- _pending_cb (方案B). No backend.pick, no router._skip_next_abort.
  describe("choose_project two-node chain (收口1)", function()
    local function ws_project_get(rs)
      rs.register()
      for _, o in ipairs(package.loaded["router.scope"]._r) do
        if o.id == "ws_project" then return o.get end
      end
    end

    it("registers ws_scope_source + ws_scope_project router nodes", function()
      local rs = setup_stubs()
      rs.register()
      local nodes = package.loaded["router"]._nodes
      assert.is_table(nodes.ws_scope_source, "ws_scope_source not registered")
      assert.is_table(nodes.ws_scope_project, "ws_scope_project not registered")
    end)

    it("ws_project get navigates open→ws_scope_source (no backend.pick)", function()
      local rs = setup_stubs()
      local get = ws_project_get(rs)
      get(function() end)
      local navs = package.loaded["router"]._navs
      assert.equals(1, #navs)
      assert.equals("open", navs[1].kind)
      assert.equals("ws_scope_source", navs[1].to_id)
    end)

    it("ws_scope_source on_confirm sets source + returns ws_scope_project", function()
      local rs = setup_stubs()
      ws_project_get(rs)
      local src_node = package.loaded["router"]._nodes.ws_scope_source
      local ctx = {}
      local next_id = src_node.on_confirm({ id = "session" }, ctx)
      assert.equals("ws_scope_project", next_id)
      assert.equals("session", ctx.workspace._scope_source)
    end)

    it("ws_scope_source items cover tab/session/global", function()
      local rs = setup_stubs()
      ws_project_get(rs)
      local src_node = package.loaded["router"]._nodes.ws_scope_source
      local items = type(src_node.items) == "function"
        and src_node.items({}) or src_node.items
      local ids = {}
      for _, it in ipairs(items) do ids[it.id] = true end
      assert.is_true(ids.tab and ids.session and ids.global,
        "expected tab/session/global source items")
    end)

    it("ws_scope_project items list source's projects", function()
      local rs = setup_stubs()
      ws_project_get(rs)
      local proj_node = package.loaded["router"]._nodes.ws_scope_project
      -- session source → registry.get('p1'/'p2')
      local ctx = { workspace = { _scope_source = "session" } }
      local items = proj_node.items(ctx)
      assert.is_table(items)
      assert.equals(2, #items)
      assert.is_string(items[1].root)
    end)

    it("ws_scope_project on_confirm fires pending cb with {root}, name", function()
      local rs = setup_stubs()
      local get = ws_project_get(rs)
      local got_dirs, got_name
      get(function(dirs, name) got_dirs = dirs; got_name = name end)
      local proj_node = package.loaded["router"]._nodes.ws_scope_project
      local ctx = { workspace = { _scope_source = "global" } }
      proj_node.on_confirm({ name = "Proj X", root = "/p/x" }, ctx)
      assert.same({ "/p/x" }, got_dirs)
      assert.equals("Proj X", got_name)
    end)

    it("on_back / cancel clears pending cb (no stale fire)", function()
      local rs = setup_stubs()
      local get = ws_project_get(rs)
      local fired = 0
      get(function() fired = fired + 1 end)
      local src_node = package.loaded["router"]._nodes.ws_scope_source
      -- back at the source level cancels the whole flow
      if type(src_node.on_back) == "function" then src_node.on_back({}) end
      -- a subsequent stray confirm must not fire the cleared cb
      local proj_node = package.loaded["router"]._nodes.ws_scope_project
      proj_node.on_confirm({ name = "X", root = "/x" },
        { workspace = { _scope_source = "global" } })
      assert.equals(0, fired, "cb fired after cancel — pending_cb not cleared")
    end)

    -- WC-3.3: back at the PROJECT level is also a cancel — must clear the
    -- pending cb so a later close/stray confirm cannot fire a stale closure.
    it("ws_scope_project on_back clears pending cb (project-level cancel)", function()
      local rs = setup_stubs()
      local get = ws_project_get(rs)
      local fired = 0
      get(function() fired = fired + 1 end)
      local proj_node = package.loaded["router"]._nodes.ws_scope_project
      assert.is_function(proj_node.on_back)
      proj_node.on_back({})
      -- a subsequent stray confirm must not fire the cleared cb
      proj_node.on_confirm({ name = "X", root = "/x" },
        { workspace = { _scope_source = "global" } })
      assert.equals(0, fired, "cb fired after project-level back — not cleared")
    end)
  end)

  -- WC-3.2: the module must not eager-require heavy node deps at load time.
  -- If workspace.router_subtree.preview is broken/absent, require()ing
  -- router_scopes and calling register() must still succeed (the scope
  -- chooser must not silently vanish). preview is now lazily required only
  -- when a preview is actually rendered.
  describe("WC-3.2 lazy preview require", function()
    it("register() works even when preview module fails to load", function()
      setup_stubs()
      -- Poison the preview module so an eager top-level require would throw.
      package.loaded["workspace.router_subtree.preview"] = nil
      package.preload["workspace.router_subtree.preview"] = function()
        error("preview module deliberately broken for WC-3.2")
      end
      package.loaded["workspace.integration.router_scopes"] = nil

      local ok_req, rs = pcall(require, "workspace.integration.router_scopes")
      assert.is_true(ok_req, "router_scopes must load without eager preview require")
      local ok_reg = pcall(rs.register)
      assert.is_true(ok_reg, "register() must run despite broken preview module")
      -- The chooser nodes must still be registered.
      assert.is_table(package.loaded["router"]._nodes.ws_scope_source)
      assert.is_table(package.loaded["router"]._nodes.ws_scope_project)

      package.preload["workspace.router_subtree.preview"] = nil
      package.loaded["workspace.router_subtree.preview"] = nil
      package.loaded["workspace.integration.router_scopes"] = nil
    end)
  end)
end)
