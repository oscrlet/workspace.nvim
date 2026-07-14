--- test/spec/active_tab_restore_spec.lua
--- Tests that snapshot/restore tracks the active tab by index, not by uuid.

local tab_state = require("workspace.tab.state")
local ws_snap   = require("workspace.workspace.snapshot")
local ws_state  = require("workspace.workspace.state")

local function close_extra_tabs()
  -- Close all tabs except the first.
  while #vim.api.nvim_list_tabpages() > 1 do
    pcall(vim.cmd, "tabclose $")
  end
end

describe("active tab restore (index-based)", function()
  before_each(function()
    close_extra_tabs()
    tab_state._reset()
    ws_state._reset()
  end)

  after_each(function()
    close_extra_tabs()
    tab_state._reset()
    ws_state._reset()
  end)

  it("snapshot records active_tab_index for the active tab", function()
    -- Tab 1: reuse current.
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1).order = 1
    -- Tab 2.
    vim.cmd("tabnew")
    local nr2 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr2).order = 2
    -- Tab 3.
    vim.cmd("tabnew")
    local nr3 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr3).order = 3

    -- Set the middle one active.
    local middle = tab_state.by_tabnr(nr2)
    ws_state.set_active_tab_id(middle.id)

    local snap = ws_snap.snapshot()
    assert.equals(3, #snap.tabs)
    assert.equals(2, snap.active_tab_index)
    assert.equals(middle.id, snap.active_tab_id)
  end)

  it("restore uses active_tab_index even when uuids are regenerated", function()
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1).order = 1
    vim.cmd("tabnew")
    local nr2 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr2).order = 2
    vim.cmd("tabnew")
    local nr3 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr3).order = 3

    local middle = tab_state.by_tabnr(nr2)
    ws_state.set_active_tab_id(middle.id)

    local snap = ws_snap.snapshot()
    assert.equals(2, snap.active_tab_index)

    -- Wipe old state so original UUIDs are gone, then close extra tabs to start clean.
    close_extra_tabs()
    tab_state._reset()
    ws_state._reset()

    ws_snap.restore(snap)

    -- After restore, the second of the three restored tabs should be active.
    local active_page = vim.api.nvim_get_current_tabpage()
    assert.equals(2, vim.api.nvim_tabpage_get_number(active_page))

    -- Sanity: ws_state.active_tab_id should resolve to a real tab.
    local restored_active_id = ws_state.active_tab_id()
    assert.is_not_nil(restored_active_id)
    local active_tab = tab_state.by_uuid(restored_active_id)
    assert.is_not_nil(active_tab)
    -- And that tab should be the second one.
    assert.equals(2, vim.api.nvim_tabpage_get_number(active_tab.tabnr))
  end)

  it("restore falls back to active_tab_id when active_tab_index is nil (legacy)", function()
    -- Build a real snapshot first to harvest entry ids/structure.
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1).order = 1
    vim.cmd("tabnew")
    local nr2 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr2).order = 2
    vim.cmd("tabnew")
    local nr3 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr3).order = 3

    local middle = tab_state.by_tabnr(nr2)
    ws_state.set_active_tab_id(middle.id)

    local snap = ws_snap.snapshot()
    -- Strip the new field to simulate a legacy session file.
    snap.active_tab_index = nil
    -- snap.active_tab_id is still the middle tab's id.

    close_extra_tabs()
    tab_state._reset()
    ws_state._reset()

    ws_snap.restore(snap)

    local active_page = vim.api.nvim_get_current_tabpage()
    assert.equals(2, vim.api.nvim_tabpage_get_number(active_page))
  end)

  it("restore tolerates a snapshot with no resolvable active tab", function()
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1).order = 1
    vim.cmd("tabnew")
    local nr2 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr2).order = 2

    local snap = ws_snap.snapshot()
    -- Hand-craft: index nil, id matches nothing.
    snap.active_tab_index = nil
    snap.active_tab_id    = "deadbeefdeadbeefdeadbeefdeadbeef"

    close_extra_tabs()
    tab_state._reset()
    ws_state._reset()

    -- Should not throw.
    local ok = pcall(ws_snap.restore, snap)
    assert.is_true(ok)

    -- Active tab must be a valid restored tabpage (no crash, sane focus).
    local pages = vim.api.nvim_list_tabpages()
    assert.equals(2, #pages)
    local active_page = vim.api.nvim_get_current_tabpage()
    local found = false
    for _, p in ipairs(pages) do if p == active_page then found = true end end
    assert.is_true(found)
  end)
end)
