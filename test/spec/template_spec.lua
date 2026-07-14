--- test/spec/template_spec.lua
--- Busted: template save/load roundtrip.
--- Uses temp paths; never touches real ~/.local/share/nvim.

local template_api = require("workspace.template.api")
local template_store = require("workspace.template.store")
local tab_state = require("workspace.tab.state")
local tab_api = require("workspace.tab.api")
local registry = require("workspace.project.registry")
local proj_store = require("workspace.project.store")

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

describe("template", function()
  local proj_dir
  local tmpl_dir

  before_each(function()
    -- Isolate project store.
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    -- Isolate template store.
    tmpl_dir = tmpdir()
    template_store._dir = tmpl_dir

    -- Reset in-memory tab state.
    tab_state._reset()
  end)

  after_each(function()
    tab_state._reset()
    proj_store._path = nil
    template_store._dir = nil
    rmdir(proj_dir)
    rmdir(tmpl_dir)
  end)

  it("save_as captures cwd + project_ids", function()
    local p1 = tmpdir()
    registry.register({ path = p1, id = "p1" })

    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "p1")

    local tab_before = tab_state.by_tabnr(nr)
    assert.equals(1, #tab_before.project_ids)
    assert.equals("p1", tab_before.project_ids[1])

    local ok, err = template_api.save_as("test_tmpl")
    assert.is_truthy(ok, "save_as failed: " .. tostring(err))

    local data = template_store.read("test_tmpl")
    assert.is_table(data)
    assert.equals(1, #data.project_ids)
    assert.equals("p1", data.project_ids[1])

    rmdir(p1)
  end)

  it("load creates new tab with projects", function()
    local p1 = tmpdir()
    registry.register({ path = p1, id = "p1" })

    -- Save a template.
    template_store.write("load_test", {
      cwd              = vim.fn.getcwd(),
      project_ids      = { "p1" },
      active_project_id = "p1",
      nvim_state       = "",
    })

    -- Load should create new tab.
    local ok, err = template_api.load("load_test")
    assert.is_truthy(ok, "load failed: " .. tostring(err))

    -- Check tab state.
    local current_nr = vim.api.nvim_get_current_tabpage()
    local loaded_tab = tab_state.by_tabnr(current_nr)
    assert.is_not_nil(loaded_tab)
    assert.equals(1, #loaded_tab.project_ids)
    assert.equals("p1", loaded_tab.project_ids[1])

    rmdir(p1)
  end)

  it("list returns recent saves", function()
    template_store.write("first", { cwd = "/tmp", project_ids = {}, active_project_id = nil, nvim_state = "" })
    template_store.write("second", { cwd = "/tmp", project_ids = {}, active_project_id = nil, nvim_state = "" })

    local items = template_api.list()
    assert.is_true(#items >= 2)

    local names = {}
    for _, item in ipairs(items) do
      names[item.name] = true
    end
    assert.is_true(names["first"])
    assert.is_true(names["second"])
  end)

  it("delete removes template", function()
    template_store.write("to_delete", { cwd = "/tmp", project_ids = {}, active_project_id = nil, nvim_state = "" })

    local items_before = template_api.list()
    assert.is_true(#items_before >= 1)

    local ok, err = template_api.delete("to_delete")
    assert.is_truthy(ok, "delete failed: " .. tostring(err))

    local items_after = template_api.list()
    local found = false
    for _, item in ipairs(items_after) do
      if item.name == "to_delete" then found = true end
    end
    assert.is_false(found)
  end)

  it("roundtrip: save -> load -> projects match", function()
    local p1 = tmpdir()
    local p2 = tmpdir()
    registry.register({ path = p1, id = "proj_a" })
    registry.register({ path = p2, id = "proj_b" })

    -- Create tab with 2 projects.
    local nr1 = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr1)
    tab_api.add_project(nr1, "proj_a")
    tab_api.add_project(nr1, "proj_b")

    local tab1 = tab_state.by_tabnr(nr1)
    assert.equals(2, #tab1.project_ids)

    -- Save as template.
    local ok_save, err_save = template_api.save_as("roundtrip_tmpl")
    assert.is_truthy(ok_save, "save failed: " .. tostring(err_save))

    -- Reset tab state to simulate fresh session.
    tab_state._reset()

    -- Load template into new tab.
    local ok_load, err_load = template_api.load("roundtrip_tmpl")
    assert.is_truthy(ok_load, "load failed: " .. tostring(err_load))

    -- Verify loaded tab has same projects.
    local current_nr = vim.api.nvim_get_current_tabpage()
    local tab2 = tab_state.by_tabnr(current_nr)
    assert.is_not_nil(tab2)
    assert.equals(2, #tab2.project_ids)

    local function contains(list, val)
      for _, v in ipairs(list) do if v == val then return true end end
      return false
    end
    assert.is_true(contains(tab2.project_ids, "proj_a"))
    assert.is_true(contains(tab2.project_ids, "proj_b"))

    rmdir(p1)
    rmdir(p2)
  end)
end)
