--- test/spec/tabufline_spec.lua
--- Busted: NvChad tabufline integration glue.

local tabline_ui = require("workspace.ui.tabline")
local tab_state  = require("workspace.tab.state")

describe("integration.tabufline", function()
  before_each(function()
    package.loaded["workspace.integration.tabufline"] = nil
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceTabuflineGlue")
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceTabuflineGlue")
  end)

  it("setup() does not error when NvChad is absent", function()
    -- Force the require to fail by stuffing a sentinel into package.loaded.
    local key = "nvchad.tabufline.modules"
    local prev = package.loaded[key]
    package.loaded[key] = nil
    -- Block the loader by inserting a guard at the head of package.loaders.
    local loaders = package.loaders or package.searchers
    local guard = function(name)
      if name == key then
        return "\n\tno file 'nvchad-blocked-by-test'"
      end
    end
    table.insert(loaders, 1, guard)

    local mod = require("workspace.integration.tabufline")
    assert.has_no.errors(function() mod.setup() end)
    assert.is_false(mod._nvchad_present)

    -- The redraw autocmd must be registered even without NvChad.
    local cmds = vim.api.nvim_get_autocmds({
      group = "WorkspaceTabuflineGlue",
      event = "User",
      pattern = "WorkspaceTabRenamed",
    })
    assert.is_true(#cmds >= 1)

    -- Restore loader chain.
    for i, l in ipairs(loaders) do
      if l == guard then table.remove(loaders, i); break end
    end
    package.loaded[key] = prev
  end)

  it("ui/tabline.tab_name returns the workspace label when one is set", function()
    -- Register a tab with an explicit label; tab_name should pick it up.
    local tabnr = vim.api.nvim_get_current_tabpage()
    tab_state._reset()
    local tab = tab_state.ensure(tabnr)
    tab.label = "alpha-ws"
    assert.equals("alpha-ws", tabline_ui.tab_name(tabnr))
    tab_state._reset()
  end)
end)
