--- test/spec/tab_commands_picker_spec.lua
--- Busted: tab commands open a picker when invoked with no args, and
--- still honor explicit args for regression-free behavior.

local commands     = require("workspace.commands")
local tab_state    = require("workspace.tab.state")
local tab_api      = require("workspace.tab.api")
local registry     = require("workspace.project.registry")
local proj_store   = require("workspace.project.store")
local template_store = require("workspace.template.store")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d) vim.fn.delete(d, "rf") end

describe("tab commands picker fallback", function()
  local proj_dir, tmpl_dir
  local r1, r2
  local p1, p2
  local orig_notify

  before_each(function()
    -- Isolate stores.
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    tmpl_dir = tmpdir()
    template_store._dir = tmpl_dir

    tab_state._reset()

    r1 = tmpdir()
    r2 = tmpdir()
    p1 = registry.register({ path = r1, id = "p1" })
    p2 = registry.register({ path = r2, id = "p2" })

    -- Stub Snacks.picker.pick to capture spec.
    _G._captured_pick = nil
    _G.Snacks = {
      picker = {
        pick = function(spec)
          _G._captured_pick = spec
          return spec
        end,
      },
    }

    -- Silence notifications.
    orig_notify = vim.notify
    vim.notify = function(_, _) end

    -- Register the tab + template commands fresh.
    commands.setup_tab_commands()
    commands.setup_template_commands()
  end)

  after_each(function()
    vim.notify = orig_notify
    _G.Snacks = nil
    _G._captured_pick = nil
    tab_state._reset()
    proj_store._path = nil
    template_store._dir = nil
    rmdir(proj_dir)
    rmdir(tmpl_dir)
    rmdir(r1)
    rmdir(r2)
  end)

  it(":TabAddProject with no args opens project picker", function()
    vim.cmd("TabAddProject")
    assert.is_not_nil(_G._captured_pick)
    assert.is_table(_G._captured_pick.items)
    assert.equals("Add Project to Tab", _G._captured_pick.title)
    -- All registered projects should be available.
    assert.is_true(#_G._captured_pick.items >= 2)
  end)

  it(":TabRemoveProject with no args opens current-tab project picker", function()
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "p1")

    vim.cmd("TabRemoveProject")
    assert.is_not_nil(_G._captured_pick)
    assert.equals("Remove Project from Tab", _G._captured_pick.title)
    -- Should reflect tab projects (1 project added).
    assert.equals(1, #_G._captured_pick.items)
    assert.equals("p1", _G._captured_pick.items[1].id)
  end)

  it(":TabSwitchProject with no args opens current-tab project picker", function()
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)
    tab_api.add_project(nr, "p1")
    tab_api.add_project(nr, "p2")

    vim.cmd("TabSwitchProject")
    assert.is_not_nil(_G._captured_pick)
    assert.equals("Switch Tab Project", _G._captured_pick.title)
    assert.equals(2, #_G._captured_pick.items)
  end)

  it(":TabLoad with no args opens template picker", function()
    template_store.write("tmpl_a", { cwd = "/tmp", project_ids = {}, active_project_id = nil, nvim_state = "" })
    template_store.write("tmpl_b", { cwd = "/tmp", project_ids = {}, active_project_id = nil, nvim_state = "" })

    vim.cmd("TabLoad")
    assert.is_not_nil(_G._captured_pick)
    assert.equals("Tab Templates", _G._captured_pick.title)
    assert.is_true(#_G._captured_pick.items >= 2)
    local names = {}
    for _, it in ipairs(_G._captured_pick.items) do names[it.name] = true end
    assert.is_true(names["tmpl_a"])
    assert.is_true(names["tmpl_b"])
  end)

  it(":TabAddProject <id> still calls tab_api.add_project with id", function()
    -- Spy on tab_api.add_project.
    local orig = tab_api.add_project
    local captured_pid
    tab_api.add_project = function(nr, pid)
      captured_pid = pid
      return orig(nr, pid)
    end

    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)

    vim.cmd("TabAddProject p1")
    assert.equals("p1", captured_pid)
    -- Picker should NOT have been opened.
    assert.is_nil(_G._captured_pick)

    tab_api.add_project = orig
  end)
end)
