--- test/spec/dashboard_spec.lua
--- Busted: workspace.ui.dashboard alpha-nvim section provider.

local config    = require("workspace.config")
local store     = require("workspace.session.store")
local dashboard = require("workspace.ui.dashboard")
local session   = require("workspace.session.api")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d) vim.fn.delete(d, "rf") end

describe("ui.dashboard.alpha_section", function()
  local sess_dir

  before_each(function()
    config._reset()
    sess_dir = tmpdir()
    store._dir = sess_dir
  end)

  after_each(function()
    store._dir = nil
    rmdir(sess_dir)
    config._reset()
  end)

  it("returns nil when cfg.ui.dashboard.alpha_section == false", function()
    config.merge({ ui = { dashboard = { alpha_section = false } } })
    -- Even if there were sessions, flag-off must short-circuit.
    assert.is_nil(dashboard.alpha_section())
  end)

  it("returns nil when session list is empty", function()
    -- flag default = true
    assert.same({}, session.list())
    assert.is_nil(dashboard.alpha_section())
  end)

  it("returns a group with N buttons (≤5) when sessions exist; pressing a button calls session.load(name, {force=true})", function()
    -- Seed three sessions via store.write, each with a tab/project_id structure.
    local function seed(name, tabs, mtime)
      assert(store.write(name, { tabs = tabs }))
      if mtime then
        vim.loop.fs_utime(store.path(name), mtime, mtime)
      end
    end
    -- Distinct integer mtimes so getftime ordering is deterministic.
    seed("alpha", { { project_ids = { "p1" } } }, 1000)
    seed("beta",  { { project_ids = { "p1", "p2" } }, { project_ids = { "p3" } } }, 2000)
    seed("gamma", { { project_ids = {} } }, 3000)

    local sec = dashboard.alpha_section()
    assert.is_table(sec)
    assert.equals("group", sec.type)
    -- The outer group contains: header text, padding, inner group of buttons.
    -- Find the inner button group.
    local inner
    for _, child in ipairs(sec.val) do
      if type(child) == "table" and child.type == "group" then
        inner = child
        break
      end
    end
    assert.is_table(inner)
    assert.equals(3, #inner.val)

    -- Spy on session.load.
    local calls = {}
    local orig = session.load
    session.load = function(name, opts) table.insert(calls, { name = name, opts = opts }) end

    -- Press first button.
    inner.val[1].on_press()

    session.load = orig

    assert.equals(1, #calls)
    -- Most recently modified is "gamma".
    assert.equals("gamma", calls[1].name)
    assert.is_table(calls[1].opts)
    assert.is_true(calls[1].opts.force)
  end)
end)
