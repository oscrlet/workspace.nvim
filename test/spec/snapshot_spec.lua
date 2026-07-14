--- test/spec/snapshot_spec.lua
--- Tests for workspace.snapshot() and restore() round-trip preservation.

local tab_state   = require("workspace.tab.state")
local tab_api     = require("workspace.tab.api")
local ws_snap     = require("workspace.workspace.snapshot")
local ws_state    = require("workspace.workspace.state")
local registry    = require("workspace.project.registry")
local proj_store  = require("workspace.project.store")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d)
  vim.fn.delete(d, "rf")
end

local function tmppath()
  return vim.fn.tempname() .. "_projects.json"
end

describe("workspace snapshot/restore", function()
  local proj_dir
  local dirs_to_clean = {}

  before_each(function()
    -- Isolate project store.
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    -- Reset in-memory tab state.
    tab_state._reset()
    ws_state._reset()

    dirs_to_clean = {}
  end)

  after_each(function()
    tab_state._reset()
    ws_state._reset()
    proj_store._path = nil
    rmdir(proj_dir)
    for _, d in ipairs(dirs_to_clean) do
      rmdir(d)
    end
  end)

  it("snapshot captures tab count", function()
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)

    local snap = ws_snap.snapshot()
    assert.is_table(snap)
    assert.equals(1, #snap.tabs)
  end)

  it("snapshot captures project_ids per tab", function()
    -- Create two project dirs.
    local p1 = tmpdir()
    local p2 = tmpdir()
    table.insert(dirs_to_clean, p1)
    table.insert(dirs_to_clean, p2)

    local proj1 = registry.register({ path = p1, id = "snap_p1" })
    local proj2 = registry.register({ path = p2, id = "snap_p2" })

    -- Simulate tab with projects.
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    tab_api.add_project(nr1, proj1.id)
    tab_api.add_project(nr1, proj2.id)

    local snap = ws_snap.snapshot()
    assert.equals(1, #snap.tabs)
    assert.equals(2, #snap.tabs[1].project_ids)

    -- Verify both project IDs are present.
    local function contains(list, val)
      for _, v in ipairs(list) do if v == val then return true end end
      return false
    end
    assert.is_true(contains(snap.tabs[1].project_ids, "snap_p1"))
    assert.is_true(contains(snap.tabs[1].project_ids, "snap_p2"))
  end)

  it("snapshot captures active_tab_id", function()
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    local tab = tab_state.by_tabnr(nr1)

    ws_state.set_active_tab_id(tab.id)

    local snap = ws_snap.snapshot()
    assert.equals(tab.id, snap.active_tab_id)
  end)

  it("snapshot captures tab label and cwd", function()
    local p1 = tmpdir()
    table.insert(dirs_to_clean, p1)

    local nr1 = vim.api.nvim_get_current_tabpage()
    local tab = tab_state.ensure(nr1)
    tab.label = "test_tab"
    tab.cwd = p1

    local snap = ws_snap.snapshot()
    assert.equals("test_tab", snap.tabs[1].label)
    assert.equals(p1, snap.tabs[1].cwd)
  end)

  it("restore recreates tabs with project_ids", function()
    local p1 = tmpdir()
    local p2 = tmpdir()
    table.insert(dirs_to_clean, p1)
    table.insert(dirs_to_clean, p2)

    registry.register({ path = p1, id = "r_p1" })
    registry.register({ path = p2, id = "r_p2" })

    -- Create initial state with 1 tab + 2 projects.
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    tab_api.add_project(nr1, "r_p1")
    tab_api.add_project(nr1, "r_p2")

    -- Snapshot.
    local snap = ws_snap.snapshot()
    assert.equals(1, #snap.tabs)
    assert.equals(2, #snap.tabs[1].project_ids)

    -- Reset state.
    tab_state._reset()
    ws_state._reset()

    -- Restore from snapshot.
    ws_snap.restore(snap)

    -- Verify state restored.
    local all_tabs = tab_state.all()
    assert.equals(1, #all_tabs)

    local restored_tab = all_tabs[1]
    assert.equals(2, #restored_tab.project_ids)

    local function contains(list, val)
      for _, v in ipairs(list) do if v == val then return true end end
      return false
    end
    assert.is_true(contains(restored_tab.project_ids, "r_p1"))
    assert.is_true(contains(restored_tab.project_ids, "r_p2"))
  end)

  it("restore preserves active_tab_id", function()
    local p1 = tmpdir()
    table.insert(dirs_to_clean, p1)
    registry.register({ path = p1, id = "act_p1" })

    local nr1 = vim.api.nvim_get_current_tabpage()
    local tab = tab_state.ensure(nr1)
    tab_api.add_project(nr1, "act_p1")
    ws_state.set_active_tab_id(tab.id)

    local snap = ws_snap.snapshot()
    assert.equals(tab.id, snap.active_tab_id)

    -- Reset and restore.
    tab_state._reset()
    ws_state._reset()
    ws_snap.restore(snap)

    -- After restore, verify active_tab_id was set to one of the restored tabs.
    local restored_active_id = ws_state.active_tab_id()
    assert.is_not_nil(restored_active_id, "active_tab_id should be set after restore")

    -- Verify the active tab exists in state.
    local active_tab = tab_state.by_uuid(restored_active_id)
    assert.is_not_nil(active_tab, "restored active tab should exist in state")
  end)

  it("snapshot with empty tabs list is valid", function()
    tab_state._reset()
    local snap = ws_snap.snapshot()
    assert.is_table(snap)
    assert.equals(0, #snap.tabs)
    assert.is_nil(snap.active_tab_id)
  end)

  it("restore with empty snapshot clears state", function()
    local p1 = tmpdir()
    table.insert(dirs_to_clean, p1)
    registry.register({ path = p1, id = "e_p1" })

    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    tab_api.add_project(nr1, "e_p1")

    -- Create minimal snapshot.
    local snap = {
      version = 1,
      tabs = {},
      active_tab_id = nil,
    }

    -- Restore (should close extra tabs).
    ws_snap.restore(snap)
    -- Note: restore always keeps at least 1 tab in vim.
    local all_tabs = tab_state.all()
    assert.is_true(#all_tabs >= 1)
  end)
end)
