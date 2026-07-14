-- router_refresh: verifies the bridge wires autocmds for all 8 mutation
-- events and that refresh_now is a no-op when no router picker is open
-- (so it is safe to fire under the headless test environment).

-- Ensure router.nvim + workspace.nvim are on rtp regardless of how the
-- harness was launched (minimal_init='NONE' children don't inherit --cmd
-- rtp), so the L1-API tests below can require("router").
do
  for _, p in ipairs({
    vim.fn.expand("~/code/neovim/plugins/router.nvim"),
    vim.fn.expand("~/code/neovim/plugins/workspace.nvim"),
  }) do
    if vim.fn.isdirectory(p) == 1 then vim.opt.runtimepath:prepend(p) end
  end
end

local rr = require("workspace.integration.router_refresh")

describe("integration.router_refresh", function()
  before_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceRouterRefresh")
  end)

  it("registers User autocmds for all 8 mutation events", function()
    rr.setup()
    assert.is_table(rr._events)
    assert.equals(8, #rr._events)
    local expected = {
      WorkspaceProjectRegistered     = true,
      WorkspaceProjectUnregistered   = true,
      WorkspaceProjectUpdated        = true,
      WorkspaceSessionSaved          = true,
      WorkspaceSessionDeleted        = true,
      WorkspaceSessionRenamed        = true,
      WorkspaceTabProjectAdded       = true,
      WorkspaceTabProjectRemoved     = true,
    }
    for _, ev in ipairs(rr._events) do
      assert.is_true(expected[ev], "unexpected event in list: " .. ev)
    end

    local cmds = vim.api.nvim_get_autocmds({
      group = "WorkspaceRouterRefresh",
      event = "User",
    })
    assert.is_true(#cmds >= 8, "expected ≥8 User autocmds, got " .. #cmds)
  end)

  it("refresh_now is a no-op when no router picker is open", function()
    rr.setup()
    assert.has_no.errors(function() rr._refresh() end)
  end)

  -- 收口4: refresh_now must go through router's public L1 API
  -- (router.invalidate_items + router.refresh_active), never reach into
  -- renderer.invalidate_items_cache or call Snacks.picker.get directly.
  it("refresh_now calls router.invalidate_items() (L1 API, not renderer)", function()
    rr.setup()
    local router = require("router")
    local invalidated = false
    local orig = router.invalidate_items
    router.invalidate_items = function() invalidated = true end
    -- no active frame: still must invalidate the cache.
    local orig_current = router.current
    router.current = function() return nil end
    rr._refresh()
    router.invalidate_items = orig
    router.current = orig_current
    assert.is_true(invalidated, "expected router.invalidate_items() to be called")
  end)

  it("refresh_now calls router.refresh_active() when a frame is active", function()
    rr.setup()
    local router = require("router")
    local refreshed = false
    local orig_refresh = router.refresh_active
    local orig_inval   = router.invalidate_items
    local orig_current = router.current
    router.invalidate_items = function() end
    router.current = function() return "workspace_project_list" end
    router.refresh_active = function() refreshed = true end
    rr._refresh()
    router.refresh_active   = orig_refresh
    router.invalidate_items = orig_inval
    router.current          = orig_current
    assert.is_true(refreshed, "expected router.refresh_active() to be called")
  end)

  it("refresh_now does NOT call refresh_active when no frame is active", function()
    rr.setup()
    local router = require("router")
    local refreshed = false
    local orig_refresh = router.refresh_active
    local orig_inval   = router.invalidate_items
    local orig_current = router.current
    router.invalidate_items = function() end
    router.current = function() return nil end
    router.refresh_active = function() refreshed = true end
    rr._refresh()
    router.refresh_active   = orig_refresh
    router.invalidate_items = orig_inval
    router.current          = orig_current
    assert.is_false(refreshed, "refresh_active must not run with no active frame")
  end)

  it("refresh_now does not touch Snacks.picker.get", function()
    rr.setup()
    local prev = _G.Snacks
    local got = false
    _G.Snacks = { picker = { get = function() got = true; return {} end } }
    local router = require("router")
    local orig_inval = router.invalidate_items
    local orig_current = router.current
    router.invalidate_items = function() end
    router.current = function() return nil end
    rr._refresh()
    router.invalidate_items = orig_inval
    router.current = orig_current
    _G.Snacks = prev
    assert.is_false(got, "refresh_now must not call Snacks.picker.get")
  end)
end)
