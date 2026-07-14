--- test/spec/autosave_session_spec.lua
--- F6: Debounced autosave on workspace mutation events.

local tab_state   = require("workspace.tab.state")
local tab_api     = require("workspace.tab.api")
local ses_store   = require("workspace.session.store")
local ses_state   = require("workspace.session.state")
local ses_api     = require("workspace.session.api")
local proj_store  = require("workspace.project.store")
local registry    = require("workspace.project.registry")
local config      = require("workspace.config")
local autocmds    = require("workspace.integration.autocmds")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d)
  vim.fn.delete(d, "rf")
end

describe("autosave session (F6)", function()
  local proj_dir
  local sess_dir
  local original_write

  before_each(function()
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    sess_dir = tmpdir()
    ses_store._dir = sess_dir

    tab_state._reset()
    ses_state._reset()

    -- Reset config session block to defaults.
    local cfg = config.get()
    cfg.session = cfg.session or {}
    cfg.session.autosave = true
    cfg.session.autosave_debounce_ms = 50  -- speed up tests

    -- Clear and re-establish autocmd group.
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceAutocmds")
    autocmds.setup()

    original_write = ses_store.write
  end)

  after_each(function()
    if original_write then ses_store.write = original_write end
    if autocmds._flush then autocmds._flush() end
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceAutocmds")

    tab_state._reset()
    ses_state._reset()
    proj_store._path = nil
    ses_store._dir   = nil
    rmdir(proj_dir)
    rmdir(sess_dir)
  end)

  it("debounced autosave persists mutation after debounce window", function()
    local p1 = tmpdir()
    local p2 = tmpdir()
    registry.register({ path = p1, id = "asp1" })
    registry.register({ path = p2, id = "asp2" })

    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "asp1")

    -- Save initial session.
    local ok, err = ses_api.save("autosave_test")
    assert.is_truthy(ok, tostring(err))

    -- Confirm baseline content.
    local data0 = assert(ses_store.read("autosave_test"))
    local function tab_with_two(d)
      for _, t in ipairs(d.tabs) do
        if #t.project_ids >= 2 then return t end
      end
    end
    assert.is_nil(tab_with_two(data0))

    -- Mutation: add second project (this fires WorkspaceTabProjectAdded).
    tab_api.add_project(nr, "asp2")

    -- Wait for debounce + a margin.
    vim.wait(400, function() return false end)

    local data1 = assert(ses_store.read("autosave_test"))
    local found = tab_with_two(data1)
    assert.is_not_nil(found, "expected mutation to be persisted")
    local function contains(list, val)
      for _, v in ipairs(list) do if v == val then return true end end
      return false
    end
    assert.is_true(contains(found.project_ids, "asp2"))

    rmdir(p1); rmdir(p2)
  end)

  it("no-op when no current session", function()
    local writes = 0
    ses_store.write = function(...) writes = writes + 1; return original_write(...) end

    local p1 = tmpdir()
    registry.register({ path = p1, id = "ns1" })
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)

    -- No session active.
    assert.is_nil(ses_api.current())
    tab_api.add_project(nr, "ns1")
    vim.wait(200, function() return false end)

    assert.equals(0, writes)
    rmdir(p1)
  end)

  it("autosave disabled via config skips persistence", function()
    local p1 = tmpdir()
    registry.register({ path = p1, id = "off1" })
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "off1")

    assert(ses_api.save("autosave_off"))
    local mtime0 = vim.fn.getftime(ses_store.path("autosave_off"))

    -- Disable autosave.
    config.get().session.autosave = false

    -- Re-init so the event handlers are not bound (autosave_enabled gate).
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceAutocmds")
    autocmds.setup()

    -- Wrap write to count.
    local writes = 0
    ses_store.write = function(...) writes = writes + 1; return original_write(...) end

    -- Mutation.
    local p2 = tmpdir()
    registry.register({ path = p2, id = "off2" })
    tab_api.add_project(nr, "off2")
    vim.wait(200, function() return false end)

    assert.equals(0, writes)
    local mtime1 = vim.fn.getftime(ses_store.path("autosave_off"))
    assert.equals(mtime0, mtime1)

    rmdir(p1); rmdir(p2)
  end)

  it("coalesces rapid mutations into a single write", function()
    local p1 = tmpdir()
    registry.register({ path = p1, id = "c1" })
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "c1")

    assert(ses_api.save("coalesce_test"))

    -- Count writes after baseline save.
    local writes = 0
    ses_store.write = function(...) writes = writes + 1; return original_write(...) end

    -- Fire 5 rapid mutations within debounce window.
    for i = 1, 5 do
      vim.api.nvim_exec_autocmds("User", {
        pattern = "WorkspaceTabActiveChanged",
        data = { tabnr = nr, project_id = "c1", n = i },
      })
    end

    -- Wait past debounce.
    vim.wait(400, function() return false end)

    assert.is_true(writes <= 2, "expected at most 2 writes, got " .. writes)
    assert.is_true(writes >= 1, "expected at least 1 write, got " .. writes)

    rmdir(p1)
  end)

  it("VimLeavePre saves regardless of autosave flag", function()
    local p1 = tmpdir()
    registry.register({ path = p1, id = "vl1" })
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "vl1")

    assert(ses_api.save("vlp_test"))

    config.get().session.autosave = false
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceAutocmds")
    autocmds.setup()

    local writes = 0
    ses_store.write = function(...) writes = writes + 1; return original_write(...) end

    -- Trigger VimLeavePre.
    vim.api.nvim_exec_autocmds("VimLeavePre", {})

    assert.is_true(writes >= 1, "VimLeavePre should always save when session is active")

    rmdir(p1)
  end)
end)
