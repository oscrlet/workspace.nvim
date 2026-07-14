--- test/spec/session_auto_register_spec.lua
--- Verifies project.auto_register_on_load behavior during session load.

local tab_state   = require("workspace.tab.state")
local tab_api     = require("workspace.tab.api")
local ses_store   = require("workspace.session.store")
local ses_state   = require("workspace.session.state")
local ses_api     = require("workspace.session.api")
local proj_store  = require("workspace.project.store")
local registry    = require("workspace.project.registry")
local config      = require("workspace.config")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d)
  vim.fn.delete(d, "rf")
end

describe("session auto_register_on_load", function()
  local proj_dir
  local sess_dir
  local tdir

  before_each(function()
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    sess_dir = tmpdir()
    ses_store._dir = sess_dir

    tab_state._reset()
    ses_state._reset()

    tdir = tmpdir()

    -- Reset config to defaults by clearing user-overridable field.
    config.merge({ project = { auto_register_on_load = true } })
  end)

  after_each(function()
    tab_state._reset()
    ses_state._reset()
    proj_store._path = nil
    ses_store._dir   = nil
    rmdir(proj_dir)
    rmdir(sess_dir)
    rmdir(tdir)
    -- Restore default.
    config.merge({ project = { auto_register_on_load = true } })
  end)

  it("auto-registers orphan project ids when flag enabled", function()
    -- Pre-seed session JSON with one tab and an unknown project id.
    local snap = {
      version = 1,
      tabs = {
        {
          id          = "tab-uuid-1",
          label       = "t1",
          order       = 1,
          cwd         = tdir,
          project_ids = { "ghost_proj" },
          active_project_id = nil,
          nvim_state  = "",
        },
      },
      active_tab_id = "tab-uuid-1",
    }
    local ok, err = ses_store.write("autoreg_yes", snap)
    assert.is_truthy(ok, tostring(err))

    -- Pre-condition: registry has no entry for ghost_proj.
    assert.is_nil(registry.get("ghost_proj"))

    local lok, lerr = ses_api.load("autoreg_yes", { force = true })
    assert.is_truthy(lok, tostring(lerr))

    -- Assert: registry now has an entry.
    local proj = registry.get("ghost_proj")
    assert.is_not_nil(proj)
    -- Root must equal tdir (after normalize_path realpath resolution).
    local expected_root = tdir
    if vim.uv and vim.uv.fs_realpath then
      expected_root = vim.uv.fs_realpath(tdir) or tdir
    end
    assert.equals(expected_root, proj.root)
    assert.equals("session_load", proj.meta and proj.meta.auto)
  end)

  it("leaves orphan ids unregistered when flag disabled", function()
    config.merge({ project = { auto_register_on_load = false } })

    local snap = {
      version = 1,
      tabs = {
        {
          id          = "tab-uuid-2",
          label       = "t1",
          order       = 1,
          cwd         = tdir,
          project_ids = { "ghost_proj_2" },
          active_project_id = nil,
          nvim_state  = "",
        },
      },
      active_tab_id = "tab-uuid-2",
    }
    local ok, err = ses_store.write("autoreg_no", snap)
    assert.is_truthy(ok, tostring(err))

    assert.is_nil(registry.get("ghost_proj_2"))

    local lok, lerr = ses_api.load("autoreg_no", { force = true })
    assert.is_truthy(lok, tostring(lerr))

    -- Registry remains empty for that id.
    assert.is_nil(registry.get("ghost_proj_2"))

    -- tab.api.projects() returns [] because the orphan id is not registered.
    local projs = tab_api.projects()
    assert.equals(0, #projs)
  end)

  it("auto-register is idempotent across multiple loads", function()
    local snap = {
      version = 1,
      tabs = {
        {
          id          = "tab-uuid-3",
          label       = "t1",
          order       = 1,
          cwd         = tdir,
          project_ids = { "idem_proj" },
          active_project_id = nil,
          nvim_state  = "",
        },
      },
      active_tab_id = "tab-uuid-3",
    }
    assert.is_truthy(ses_store.write("idem", snap))

    assert.is_truthy(ses_api.load("idem", { force = true }))
    local first = registry.get("idem_proj")
    assert.is_not_nil(first)
    local first_created = first.created_at

    -- Load again.
    assert.is_truthy(ses_api.load("idem", { force = true }))
    local second = registry.get("idem_proj")
    assert.is_not_nil(second)
    -- created_at preserved => same entry, not duplicated.
    assert.equals(first_created, second.created_at)

    -- Only one project in registry list.
    local list = registry.list()
    local count = 0
    for _, p in ipairs(list) do
      if p.id == "idem_proj" then count = count + 1 end
    end
    assert.equals(1, count)
  end)
end)
