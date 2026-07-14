--- test/spec/explorer_multiroot_spec.lua
--- Busted: Scheme B multi-root explorer integration.

local AUGROUP = "WorkspaceExplorerMultiroot"
local SOURCE = "workspace_explorer"

local function reset()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  package.loaded["workspace.integration.explorer_multiroot"] = nil
  package.loaded["workspace"] = nil
  require("workspace.config")._reset()
  require("workspace.tab.state")._reset()
  pcall(function() require("workspace.project.state").projects = {} end)
end

local function load_mod()
  return require("workspace.integration.explorer_multiroot")
end

--- Install a Snacks stub. Returns { state, restore }.
local function stub_snacks()
  local prev = _G.Snacks
  local state = {
    sources = {},
    pick_calls = {},
    explorer_calls = {},
    pickers = {},
  }
  _G.Snacks = {
    picker = {
      sources = state.sources,
      pick = function(opts) table.insert(state.pick_calls, opts) end,
      get = function(_filter) return state.pickers end,
      explorer = function(opts) table.insert(state.explorer_calls, opts or {}) end,
    },
  }
  return state, function() _G.Snacks = prev end
end

--- Make tmp dir + register a project on the current tab.
--- Uses tab.add_project (pure data mutation) rather than
--- add_project_to_active so the test does not :tcd into the tmp dir
--- (which would change cwd mid-spec and break package.path-relative
--- module loading on subsequent requires).
local function register_proj(id)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local pm = require("workspace.project")
  local p = pm.register({ id = id, path = root, force = true })
  local tab = require("workspace.tab")
  tab.add_project(nil, id)
  return p, root
end

describe("integration.explorer_multiroot", function()
  before_each(function() reset() end)
  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  end)

  it("setup() with enabled=false → no source registered, no augroup", function()
    local state, restore = stub_snacks()
    -- enabled defaults to false.
    load_mod().setup()
    assert.is_nil(state.sources[SOURCE])
    local ok, cmds = pcall(vim.api.nvim_get_autocmds, { group = AUGROUP })
    assert.is_true((not ok) or #cmds == 0)
    restore()
  end)

  it("setup() with enabled=true + Snacks present → registers source", function()
    local state, restore = stub_snacks()
    local cfg = require("workspace.config").get()
    cfg.ui.explorer_multiroot.enabled = true
    load_mod().setup()
    assert.is_not_nil(state.sources[SOURCE])
    assert.is_function(state.sources[SOURCE].finder)
    -- augroup created
    local cmds = vim.api.nvim_get_autocmds({ group = AUGROUP })
    assert.is_true(#cmds >= 1)
    restore()
  end)

  it("_items() with 2 projects on tab → 2 items shaped {dir=true,file=root,text=name}", function()
    local _, restore = stub_snacks()
    local p1, _ = register_proj("mr_a")
    local p2, _ = register_proj("mr_b")
    local items = load_mod()._items()
    assert.equals(2, #items)
    -- order matches projects() order; root values come from project records
    -- (canonicalized via realpath by project.register).
    assert.is_true(items[1].dir == true)
    assert.is_true(items[2].dir == true)
    assert.equals(p1.root, items[1].file)
    assert.equals(p2.root, items[2].file)
    -- text = name (or id fallback)
    assert.is_truthy(items[1].text)
    assert.is_truthy(items[2].text)
    restore()
  end)

  it("WorkspaceTabProjectAdded triggers refresh path", function()
    local state, restore = stub_snacks()
    local cfg = require("workspace.config").get()
    cfg.ui.explorer_multiroot.enabled = true

    -- Pretend an open picker exists — _refresh will call :find on it.
    local find_calls = 0
    table.insert(state.pickers, {
      find = function(self) find_calls = find_calls + 1 end,
    })

    local mod = load_mod()
    mod.setup()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "WorkspaceTabProjectAdded",
      data = {},
    })
    -- _refresh defers to vim.schedule (avoids fast-context API calls).
    vim.wait(50, function() return find_calls >= 1 end)
    assert.is_true(find_calls >= 1)
    restore()
  end)

  it("WorkspaceTabActiveChanged does NOT relocate picker cwd", function()
    local state, restore = stub_snacks()
    local cfg = require("workspace.config").get()
    cfg.ui.explorer_multiroot.enabled = true

    local set_cwd_calls = 0
    table.insert(state.pickers, {
      find = function(self) end,
      set_cwd = function(self, _) set_cwd_calls = set_cwd_calls + 1 end,
    })

    load_mod().setup()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "WorkspaceTabActiveChanged",
      data = { project_id = "anything" },
    })
    -- Multi-root must preserve all roots: never call set_cwd on the picker.
    assert.equals(0, set_cwd_calls)
    -- Also: explorer was NOT reopened with a new cwd.
    assert.equals(0, #state.explorer_calls)
    restore()
  end)

  it("M.open() calls Snacks.picker.pick({ source = SOURCE }) once", function()
    local state, restore = stub_snacks()
    local cfg = require("workspace.config").get()
    cfg.ui.explorer_multiroot.enabled = true
    local mod = load_mod()
    mod.setup()
    mod.open()
    assert.equals(1, #state.pick_calls)
    assert.equals(SOURCE, state.pick_calls[1].source)
    restore()
  end)

  it("empty tab → _items() returns {} and warns (no raise)", function()
    local _, restore = stub_snacks()
    local notified = {}
    local orig = vim.notify
    vim.notify = function(msg, lvl)
      table.insert(notified, { msg = msg, lvl = lvl })
    end
    local items = load_mod()._items()
    vim.notify = orig
    assert.equals(0, #items)
    -- a WARN was emitted
    local saw_warn = false
    for _, n in ipairs(notified) do
      if n.lvl == vim.log.levels.WARN then saw_warn = true end
    end
    assert.is_true(saw_warn)
    restore()
  end)
end)
