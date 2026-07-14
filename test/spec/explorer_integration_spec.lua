--- test/spec/explorer_integration_spec.lua
--- Busted: Snacks.explorer integration (Scheme C).

local function reset()
  pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceExplorerFollow")
  package.loaded["workspace.integration.explorer"] = nil
  package.loaded["workspace"] = nil
  require("workspace.config")._reset()
end

local function load_integration()
  return require("workspace.integration.explorer")
end

--- Install a Snacks stub. Returns { explorer_calls, restore }.
local function stub_snacks(opts)
  opts = opts or {}
  local explorer_calls = {}
  local get_pickers = opts.pickers or {}
  local prev = _G.Snacks
  _G.Snacks = {
    picker = {
      explorer = function(o) table.insert(explorer_calls, o or {}) end,
      get      = function(_) return get_pickers end,
    },
  }
  return explorer_calls, function() _G.Snacks = prev end
end

--- Register a project on the current tab.
local function register_proj(id, root)
  local pm = require("workspace.project")
  local p = pm.register({ id = id, path = root, force = true })
  local tab = require("workspace.tab")
  tab.add_project_to_active(id)
  return p
end

describe("integration.explorer", function()
  before_each(function()
    reset()
    require("workspace.tab.state")._reset()
    pcall(function() require("workspace.project.state").projects = {} end)
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceExplorerFollow")
  end)

  it("default-on: setup() creates the augroup", function()
    require("workspace.config")._reset()
    load_integration().setup()
    local cmds = vim.api.nvim_get_autocmds({
      group = "WorkspaceExplorerFollow",
      event = "User",
      pattern = "WorkspaceTabActiveChanged",
    })
    assert.is_true(#cmds >= 1)
  end)

  it("opt-out flag: setup() does NOT create the augroup", function()
    require("workspace.config")._reset()
    require("workspace.config").merge({ ui = { explorer = { auto_follow_active_project = false } } })
    load_integration().setup()
    local ok, cmds = pcall(vim.api.nvim_get_autocmds, { group = "WorkspaceExplorerFollow" })
    assert.is_true(not ok or #cmds == 0)
  end)

  it("active changed + tree open → calls Snacks.picker.explorer with new root", function()
    require("workspace.config")._reset()
    local mod = load_integration()
    mod.setup()
    mod._tree_open = function() return true end

    register_proj("foo", "/tmp/foo")

    local calls, restore = stub_snacks()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "WorkspaceTabActiveChanged",
      data = { project_id = "foo" },
    })
    restore()

    local found = false
    for _, c in ipairs(calls) do
      if c.cwd and c.cwd:find("/tmp/foo", 1, true) then found = true end
    end
    assert.is_true(found, "expected Snacks.picker.explorer cwd=/tmp/foo, got: " .. vim.inspect(calls))
  end)

  it("follow_current_file flag default-true → autocmd dispatch still happens", function()
    require("workspace.config")._reset()
    local mod = load_integration()
    mod.setup()
    mod._tree_open = function() return true end

    register_proj("foo", "/tmp/foo")

    local calls, restore = stub_snacks()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "WorkspaceTabActiveChanged",
      data = { project_id = "foo" },
    })
    restore()

    assert.is_true(#calls >= 1, "expected at least one Snacks.picker.explorer call")
  end)

  it("missing project_id → handler tolerates and no-ops", function()
    require("workspace.config")._reset()
    local mod = load_integration()
    mod.setup()
    mod._tree_open = function() return true end

    local calls, restore = stub_snacks()
    local ok = pcall(function()
      vim.api.nvim_exec_autocmds("User", {
        pattern = "WorkspaceTabActiveChanged",
        data = {},
      })
    end)
    restore()

    assert.is_true(ok, "handler must not raise on missing project_id")
    assert.equals(0, #calls, "no Snacks call when project_id is absent")
  end)

  it("tree closed → no Snacks.picker.explorer call", function()
    require("workspace.config")._reset()
    local mod = load_integration()
    mod.setup()
    mod._tree_open = function() return false end

    register_proj("foo", "/tmp/foo")

    local calls, restore = stub_snacks()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "WorkspaceTabActiveChanged",
      data = { project_id = "foo" },
    })
    restore()

    assert.equals(0, #calls)
  end)

  it("pick_root_for_explorer: ui.select choice → Snacks.picker.explorer, no switch_active", function()
    require("workspace.config")._reset()
    register_proj("alpha", "/tmp/alpha")
    register_proj("beta", "/tmp/beta")

    local orig_select = vim.ui.select
    vim.ui.select = function(items, _, on_choice) on_choice(items[2]) end

    local tab = require("workspace.tab")
    local orig_switch = tab.switch_active
    local switch_called = false
    tab.switch_active = function(...) switch_called = true; return orig_switch(...) end

    local calls, restore = stub_snacks()
    load_integration().pick_root_for_explorer()
    restore()
    vim.ui.select = orig_select
    tab.switch_active = orig_switch

    local found = false
    for _, c in ipairs(calls) do
      if c.cwd and c.cwd:find("/tmp/beta", 1, true) then found = true end
    end
    assert.is_true(found, "expected explorer cwd=/tmp/beta, got: " .. vim.inspect(calls))
    assert.is_false(switch_called, "switch_active must NOT be called")
  end)

  it("pick_root_for_explorer: empty tab → notify WARN, no Snacks call", function()
    require("workspace.config")._reset()
    require("workspace.tab.state")._reset()

    local notified
    local orig_notify = vim.notify
    vim.notify = function(msg, lvl) notified = { msg = msg, lvl = lvl } end

    local calls, restore = stub_snacks()
    load_integration().pick_root_for_explorer()
    restore()
    vim.notify = orig_notify

    assert.is_truthy(notified, "expected vim.notify to be called")
    assert.equals(vim.log.levels.WARN, notified.lvl)
    assert.equals(0, #calls)
  end)
end)
