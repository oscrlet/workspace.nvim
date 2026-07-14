--- test/spec/persist_state_spec.lua
--- R5: Persistent tab/project state (independent of session).

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d)
  vim.fn.delete(d, "rf")
end

local function reset_all()
  pcall(vim.api.nvim_del_augroup_by_name, "WorkspacePersistState")
  pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceAutocmds")
  require("workspace.tab.state")._reset()
  require("workspace.workspace.state")._reset()
  require("workspace.session.state")._reset()
  require("workspace.config")._reset()
  pcall(function() require("workspace.state.persist")._reset() end)
end

describe("persistent state (R5)", function()
  local data_dir
  local prev_proj_path
  local proj_store = require("workspace.project.store")
  local registry   = require("workspace.project.registry")

  before_each(function()
    data_dir = tmpdir()
    prev_proj_path = proj_store._path
    proj_store._path = data_dir .. "/projects.json"
    registry.setup({})
    reset_all()
  end)

  after_each(function()
    pcall(function() require("workspace.integration.persist")._teardown() end)
    reset_all()
    proj_store._path = prev_proj_path
    rmdir(data_dir)
  end)

  it("cold start with empty data_dir: read() returns nil and setup does not crash", function()
    require("workspace").setup({ data_dir = data_dir,
      session = { confirm_before_load = false, autoload_last_on_startup = false } })
    local persist = require("workspace.state.persist")
    local snap, err = persist.read()
    assert.is_nil(snap)
    assert.is_truthy(err)
  end)

  it("add_project_to_active without session writes state.json", function()
    require("workspace").setup({ data_dir = data_dir,
      persistent_state = { enabled = true, debounce_ms = 30 },
      session = { confirm_before_load = false, autoload_last_on_startup = false } })
    local pdir = tmpdir()
    vim.fn.mkdir(pdir .. "/.git", "p")
    local project = require("workspace.project")
    project.register({ path = pdir, id = "ps_a" })

    -- No active session.
    assert.is_nil(require("workspace.session").current())

    require("workspace.tab").add_project(nil, "ps_a")

    vim.wait(300, function()
      return vim.fn.filereadable(data_dir .. "/state.json") == 1
    end)

    local persist = require("workspace.state.persist")
    local snap = assert(persist.read())
    assert.is_table(snap.tabs)
    local found
    for _, t in ipairs(snap.tabs) do
      for _, pid in ipairs(t.project_ids or {}) do
        if pid == "ps_a" then found = t end
      end
    end
    assert.is_not_nil(found)
    rmdir(pdir)
  end)

  it("simulated restart: clear tab_state then setup() rehydrates from disk", function()
    -- First run: register + add project + flush.
    require("workspace").setup({ data_dir = data_dir,
      persistent_state = { enabled = true, debounce_ms = 20 },
      session = { confirm_before_load = false, autoload_last_on_startup = false } })
    local pdir = tmpdir()
    vim.fn.mkdir(pdir .. "/.git", "p")
    require("workspace.project").register({ path = pdir, id = "ps_b" })
    require("workspace.tab").add_project(nil, "ps_b")
    vim.wait(200, function()
      return vim.fn.filereadable(data_dir .. "/state.json") == 1
    end)

    -- Simulate restart: clear in-memory state, do NOT delete state.json.
    require("workspace.integration.persist")._teardown()
    require("workspace.tab.state")._reset()
    require("workspace.workspace.state")._reset()

    -- Re-run setup → should rehydrate.
    require("workspace.integration.persist").setup(require("workspace.config").get())

    local nr = vim.api.nvim_get_current_tabpage()
    local tab = require("workspace.tab.state").by_tabnr(nr)
    assert.is_not_nil(tab)
    local has = false
    for _, pid in ipairs(tab.project_ids or {}) do
      if pid == "ps_b" then has = true end
    end
    assert.is_true(has, "expected rehydrated project ps_b on current tab")
    rmdir(pdir)
  end)

  it("persistent_state.enabled = false: no augroup, no writes on event", function()
    require("workspace").setup({ data_dir = data_dir,
      persistent_state = { enabled = false },
      session = { confirm_before_load = false, autoload_last_on_startup = false } })
    -- No augroup. nvim_get_autocmds raises when the group does not exist.
    local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "WorkspacePersistState" })
    if ok then
      assert.equals(0, #autocmds)
    end -- else: group truly absent, which is the desired state

    -- Mutation event does not produce state.json.
    local pdir = tmpdir()
    vim.fn.mkdir(pdir .. "/.git", "p")
    require("workspace.project").register({ path = pdir, id = "ps_c" })
    require("workspace.tab").add_project(nil, "ps_c")
    vim.wait(150, function() return false end)
    assert.equals(0, vim.fn.filereadable(data_dir .. "/state.json"))
    rmdir(pdir)
  end)

  it("SessionLoad rewrites state.json to reflect loaded session", function()
    require("workspace").setup({ data_dir = data_dir,
      persistent_state = { enabled = true, debounce_ms = 20 },
      session = { confirm_before_load = false, autoload_last_on_startup = false } })

    -- Pre-existing state.json with a stale project.
    local pdir_old = tmpdir()
    local pdir_new = tmpdir()
    vim.fn.mkdir(pdir_old .. "/.git", "p")
    vim.fn.mkdir(pdir_new .. "/.git", "p")
    local project = require("workspace.project")
    project.register({ path = pdir_old, id = "ps_old" })
    require("workspace.tab").add_project(nil, "ps_old")
    vim.wait(200, function()
      return vim.fn.filereadable(data_dir .. "/state.json") == 1
    end)

    -- Save a session that uses ps_new instead.
    require("workspace.tab.state")._reset()
    project.register({ path = pdir_new, id = "ps_new" })
    require("workspace.tab.state").ensure(vim.api.nvim_get_current_tabpage())
    require("workspace.tab").add_project(nil, "ps_new")
    local sess = require("workspace.session.api")
    assert(sess.save("ps_load_test"))

    -- Now wipe in-memory and load the session.
    require("workspace.tab.state")._reset()
    sess.load("ps_load_test", { force = true })

    -- state.json should reflect ps_new (the loaded session), not ps_old.
    local snap = assert(require("workspace.state.persist").read())
    local seen_new, seen_old = false, false
    for _, t in ipairs(snap.tabs or {}) do
      for _, pid in ipairs(t.project_ids or {}) do
        if pid == "ps_new" then seen_new = true end
        if pid == "ps_old" then seen_old = true end
      end
    end
    assert.is_true(seen_new, "expected ps_new in state.json after load")
    assert.is_false(seen_old, "stale ps_old should be gone after load")

    rmdir(pdir_old); rmdir(pdir_new)
  end)

  it("debounce coalesces multiple rapid events into one write", function()
    require("workspace").setup({ data_dir = data_dir,
      persistent_state = { enabled = true, debounce_ms = 100 },
      session = { confirm_before_load = false, autoload_last_on_startup = false } })

    -- Spy on persist.write.
    local persist = require("workspace.state.persist")
    local orig_write = persist.write
    local writes = 0
    persist.write = function(...) writes = writes + 1; return orig_write(...) end

    -- Fire 5 rapid events within debounce window.
    for i = 1, 5 do
      vim.api.nvim_exec_autocmds("User", {
        pattern = "WorkspaceTabActiveChanged",
        data = { n = i },
      })
    end

    vim.wait(300, function() return false end)
    persist.write = orig_write

    assert.is_true(writes <= 2, "expected <=2 writes, got " .. writes)
    assert.is_true(writes >= 1, "expected >=1 write, got " .. writes)
  end)
end)
