--- test/spec/reactive_sync_spec.lua
--- Verifies User events fire on every workspace mutation entry point and that
--- subsequent `.list()`/`.projects()` calls reflect the post-mutation state.

local tab_state   = require("workspace.tab.state")
local tab_api     = require("workspace.tab.api")
local ses_store   = require("workspace.session.store")
local ses_state   = require("workspace.session.state")
local ses_api     = require("workspace.session.api")
local proj_store  = require("workspace.project.store")
local registry    = require("workspace.project.registry")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d) vim.fn.delete(d, "rf") end

--- Capture User events of one pattern into a table.
---@param pattern string
---@return table captured  list of `args.data` payloads
---@return integer augroup_id
local function capture(pattern)
  local captured = {}
  local group = vim.api.nvim_create_augroup("ReactiveSyncTest_" .. pattern, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = pattern,
    callback = function(args)
      table.insert(captured, args.data)
    end,
  })
  return captured, group
end

local function cleanup(group)
  pcall(vim.api.nvim_del_augroup_by_id, group)
end

describe("reactive sync: User events on mutations", function()
  local proj_dir
  local sess_dir

  before_each(function()
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    sess_dir = tmpdir()
    ses_store._dir = sess_dir

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

  it("WorkspaceProjectRegistered fires + list reflects new project", function()
    local captured, group = capture("WorkspaceProjectRegistered")
    local p = tmpdir()
    local proj = registry.register({ path = p, id = "rs1" })

    assert.is_true(#captured >= 1, "expected >=1 fire of WorkspaceProjectRegistered")
    assert.equals("rs1", captured[1].id)
    assert.is_table(captured[1].project)
    assert.equals("rs1", proj.id)
    assert.is_not_nil(registry.get("rs1"))

    cleanup(group)
    rmdir(p)
  end)

  it("WorkspaceProjectUnregistered fires + project removed", function()
    local p = tmpdir()
    registry.register({ path = p, id = "rs2" })

    local captured, group = capture("WorkspaceProjectUnregistered")
    local removed = registry.unregister("rs2")
    assert.is_true(removed)

    assert.equals(1, #captured)
    assert.equals("rs2", captured[1].id)
    assert.is_nil(registry.get("rs2"))

    cleanup(group)
    rmdir(p)
  end)

  it("WorkspaceProjectUpdated fires + update reflected", function()
    local p = tmpdir()
    registry.register({ path = p, id = "rs3", name = "old" })

    local captured, group = capture("WorkspaceProjectUpdated")
    registry.update("rs3", { name = "new-name" })

    assert.is_true(#captured >= 1, "expected >=1 fire of WorkspaceProjectUpdated")
    assert.equals("rs3", captured[#captured].id)
    assert.equals("new-name", captured[#captured].project.name)
    assert.equals("new-name", registry.get("rs3").name)

    cleanup(group)
    rmdir(p)
  end)

  it("WorkspaceSessionSaved fires + list contains saved session", function()
    local captured, group = capture("WorkspaceSessionSaved")
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)

    local ok, err = ses_api.save("rs_saved")
    assert.is_truthy(ok, tostring(err))

    assert.equals(1, #captured)
    assert.equals("rs_saved", captured[1].name)

    local items = ses_api.list()
    local found = false
    for _, it in ipairs(items) do
      if it.name == "rs_saved" then found = true end
    end
    assert.is_true(found, "expected rs_saved to appear in list()")

    cleanup(group)
  end)

  it("WorkspaceSessionDeleted fires + list does not contain it", function()
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    assert.is_truthy(ses_api.save("rs_del"))
    assert.is_truthy(ses_api.exists("rs_del"))

    local captured, group = capture("WorkspaceSessionDeleted")
    ses_api.delete("rs_del")

    assert.equals(1, #captured)
    assert.equals("rs_del", captured[1].name)
    assert.is_falsy(ses_api.exists("rs_del"))

    local items = ses_api.list()
    for _, it in ipairs(items) do
      assert.is_not.equals("rs_del", it.name)
    end

    cleanup(group)
  end)

  it("WorkspaceSessionRenamed fires + list reflects new name", function()
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    assert.is_truthy(ses_api.save("rs_old"))

    local captured, group = capture("WorkspaceSessionRenamed")
    local ok, err = ses_api.rename("rs_old", "rs_new")
    assert.is_truthy(ok, tostring(err))

    assert.equals(1, #captured)
    assert.equals("rs_old", captured[1].from)
    assert.equals("rs_new", captured[1].to)

    assert.is_falsy(ses_api.exists("rs_old"))
    assert.is_truthy(ses_api.exists("rs_new"))

    local items = ses_api.list()
    local saw_new, saw_old = false, false
    for _, it in ipairs(items) do
      if it.name == "rs_new" then saw_new = true end
      if it.name == "rs_old" then saw_old = true end
    end
    assert.is_true(saw_new)
    assert.is_false(saw_old)

    cleanup(group)
  end)

  it("WorkspaceTabProjectAdded fires + projects() includes added id", function()
    local p = tmpdir()
    registry.register({ path = p, id = "rs_t_add" })

    local captured, group = capture("WorkspaceTabProjectAdded")
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "rs_t_add")

    assert.equals(1, #captured)
    assert.equals(nr, captured[1].tabnr)
    assert.equals("rs_t_add", captured[1].project_id)

    local pids = ses_api.projects()
    local found = false
    for _, pid in ipairs(pids) do if pid == "rs_t_add" then found = true end end
    assert.is_true(found)

    cleanup(group)
    rmdir(p)
  end)

  it("WorkspaceTabProjectRemoved fires + projects() no longer contains id", function()
    local p = tmpdir()
    registry.register({ path = p, id = "rs_t_rm" })
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "rs_t_rm")

    local captured, group = capture("WorkspaceTabProjectRemoved")
    tab_api.remove_project(nr, "rs_t_rm")

    assert.equals(1, #captured)
    assert.equals(nr, captured[1].tabnr)
    assert.equals("rs_t_rm", captured[1].project_id)

    local pids = ses_api.projects()
    for _, pid in ipairs(pids) do
      assert.is_not.equals("rs_t_rm", pid)
    end

    cleanup(group)
    rmdir(p)
  end)
end)
