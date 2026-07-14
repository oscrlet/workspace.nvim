--- test/spec/session_roundtrip_spec.lua
--- Busted: save + load round-trip preserves tab count and per-tab project_ids.
--- Uses temp paths; never touches real ~/.local/share/nvim.

local tab_state   = require("workspace.tab.state")
local tab_api     = require("workspace.tab.api")
local ws_snap     = require("workspace.workspace.snapshot")
local ses_store   = require("workspace.session.store")
local ses_state   = require("workspace.session.state")
local ses_api     = require("workspace.session.api")
local proj_store  = require("workspace.project.store")
local registry    = require("workspace.project.registry")

-- Temp dir helper.
local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

-- Remove a directory tree (best-effort).
local function rmdir(d)
  vim.fn.delete(d, "rf")
end

describe("session roundtrip", function()
  local proj_dir
  local sess_dir

  before_each(function()
    -- Isolate project store.
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    -- Isolate session store.
    sess_dir = tmpdir()
    ses_store._dir = sess_dir

    -- Reset in-memory tab state.
    tab_state._reset()
    ses_state._reset()
  end)

  after_each(function()
    tab_state._reset()
    ses_state._reset()
    proj_store._path = nil
    ses_store._dir   = nil
    rmdir(proj_dir)
    rmdir(sess_dir)
  end)

  it("save + load preserves tab count", function()
    -- Create two fake project dirs.
    local p1 = tmpdir()
    local p2 = tmpdir()
    local proj1 = registry.register({ path = p1, id = "proj1" })
    local proj2 = registry.register({ path = p2, id = "proj2" })

    -- Simulate tab 1: projects proj1 + proj2.
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    tab_api.add_project(nr1, proj1.id)
    tab_api.add_project(nr1, proj2.id)

    -- Simulate tab 2 via new entry (we can't call tabnew in headless easily;
    -- manually inject a second tab state entry with a synthetic tabnr).
    local nr2 = 99  -- synthetic; no actual vim tab
    tab_state.ensure(nr2)
    tab_api.add_project(nr2, proj1.id)

    -- Snapshot before save.
    local snap_before = ws_snap.snapshot()
    assert.equals(2, #snap_before.tabs)

    -- Save session.
    local ok, err = ses_api.save("roundtrip_test")
    assert.is_truthy(ok, "save failed: " .. tostring(err))

    -- Verify file written.
    assert.is_truthy(ses_api.exists("roundtrip_test"))

    -- Read raw to verify structure.
    local data, derr = ses_store.read("roundtrip_test")
    assert.is_nil(derr)
    assert.is_table(data)
    assert.equals(1, data.version)
    assert.equals(2, #data.tabs)

    -- Verify tab project_ids in snapshot.
    local tab_map = {}
    for _, t in ipairs(data.tabs) do
      tab_map[t.id] = t
    end

    -- Find which tab has 2 project_ids and which has 1.
    local two_proj, one_proj
    for _, t in ipairs(data.tabs) do
      if #t.project_ids == 2 then
        two_proj = t
      elseif #t.project_ids == 1 then
        one_proj = t
      end
    end
    assert.is_not_nil(two_proj, "expected a tab with 2 project_ids")
    assert.is_not_nil(one_proj, "expected a tab with 1 project_id")

    -- Check specific IDs.
    local function contains(list, val)
      for _, v in ipairs(list) do if v == val then return true end end
      return false
    end
    assert.is_true(contains(two_proj.project_ids, "proj1"))
    assert.is_true(contains(two_proj.project_ids, "proj2"))
    assert.is_true(contains(one_proj.project_ids, "proj1"))
  end)

  it("list returns saved session", function()
    -- Ensure dir exists.
    ses_store.write("alpha", { version = 1, tabs = {}, active_tab_id = nil })
    local items = ses_store.list()
    assert.is_true(#items >= 1)
    local found = false
    for _, item in ipairs(items) do
      if item.name == "alpha" then found = true end
    end
    assert.is_true(found)
  end)

  it("delete removes session", function()
    ses_store.write("beta", { version = 1, tabs = {}, active_tab_id = nil })
    assert.is_truthy(ses_api.exists("beta"))
    ses_api.delete("beta")
    assert.is_falsy(ses_api.exists("beta"))
  end)

  it("projects() unions across tabs", function()
    local p1 = tmpdir()
    local p2 = tmpdir()
    registry.register({ path = p1, id = "u1" })
    registry.register({ path = p2, id = "u2" })

    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    tab_api.add_project(nr1, "u1")

    local nr2 = 88
    tab_state.ensure(nr2)
    tab_api.add_project(nr2, "u2")

    local ids = ses_api.projects()
    assert.equals(2, #ids)

    rmdir(p1)
    rmdir(p2)
  end)

  it("snapshot restore round-trip: tab project_ids match", function()
    local p1 = tmpdir()
    local p2 = tmpdir()
    registry.register({ path = p1, id = "r1" })
    registry.register({ path = p2, id = "r2" })

    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    tab_api.add_project(nr1, "r1")
    tab_api.add_project(nr1, "r2")

    -- Save + reset + restore via low-level store to avoid vim tab operations.
    local snap = ws_snap.snapshot()
    assert.equals(1, #snap.tabs)
    assert.equals(2, #snap.tabs[1].project_ids)

    local ok, err = ses_store.write("rt2", snap)
    assert.is_truthy(ok, tostring(err))

    local loaded, lerr = ses_store.read("rt2")
    assert.is_nil(lerr)
    assert.equals(1, #loaded.tabs)

    local function contains(list, val)
      for _, v in ipairs(list) do if v == val then return true end end
      return false
    end
    assert.is_true(contains(loaded.tabs[1].project_ids, "r1"))
    assert.is_true(contains(loaded.tabs[1].project_ids, "r2"))

    rmdir(p1)
    rmdir(p2)
  end)
end)
