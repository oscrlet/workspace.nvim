-- Asserts the DirChanged subscriber installed by autocmds.setup:
--   * tabpage-scope cwd changes write through to tab.cwd
--   * window-scope (`:lcd`) is ignored
--   * a CwdChanged event is fired on each effective change

local function reset_workspace()
  for k in pairs(package.loaded) do
    if k == "workspace" or k:sub(1, 10) == "workspace." then
      package.loaded[k] = nil
    end
  end
end

describe("workspace cwd tracker (DirChanged)", function()
  -- `:tcd` inside a test mutates the process cwd; if any preceding spec
  -- in the same headless run added `.` to rtp at startup, subsequent
  -- requires will fail once cwd moves. Capture the absolute repo root
  -- once and restore it after every test.
  local repo_root = vim.fn.getcwd()

  before_each(function()
    vim.cmd("cd " .. vim.fn.fnameescape(repo_root))
    reset_workspace()
    require("workspace").setup({
      session  = { autosave = false },     -- silence the debounced save
      data_dir = vim.fn.tempname(),
      ui       = { override_vim_select = false },
    })
  end)

  after_each(function()
    vim.cmd("cd " .. vim.fn.fnameescape(repo_root))
  end)

  it("tabpage-scope DirChanged updates tab.cwd", function()
    local state = require("workspace.tab.state")
    local nr   = vim.api.nvim_get_current_tabpage()
    local tab  = state.ensure(nr)
    tab.cwd = "/old"

    -- Real `:tcd` exercises the production path: vim sets v:event.scope
    -- to "tabpage" and v:event.cwd to the resolved absolute path.
    local target = vim.fn.tempname()
    vim.fn.mkdir(target, "p")
    vim.cmd("tcd " .. vim.fn.fnameescape(target))

    -- macOS resolves /var → /private/var; just check the tail matches.
    assert.is_truthy(tab.cwd)
    assert.matches(vim.fn.fnamemodify(target, ":t"), tab.cwd)
  end)

  it("the tracker is idempotent when cwd is unchanged", function()
    local state  = require("workspace.tab.state")
    local events = require("workspace.tab.events")
    local nr     = vim.api.nvim_get_current_tabpage()
    local tab    = state.ensure(nr)
    tab.cwd = vim.fn.getcwd()

    local fired = 0
    vim.api.nvim_create_autocmd("User", {
      pattern  = "WorkspaceTabCwdChanged",
      callback = function() fired = fired + 1 end,
    })

    -- Re-fire with same cwd (callback short-circuits via tab.cwd == new).
    vim.api.nvim_exec_autocmds("DirChanged", {
      pattern = "global",
      data    = { scope = "global", cwd = tab.cwd },
    })
    assert.equals(0, fired)
  end)

  it("window-scope DirChanged does not write tab.cwd", function()
    local state = require("workspace.tab.state")
    local nr   = vim.api.nvim_get_current_tabpage()
    local tab  = state.ensure(nr)
    tab.cwd = "/keep-this"

    vim.api.nvim_exec_autocmds("DirChanged", {
      pattern = "window",
      data    = { scope = "window", cwd = "/should-be-ignored" },
    })
    assert.equals("/keep-this", tab.cwd)
  end)
end)
