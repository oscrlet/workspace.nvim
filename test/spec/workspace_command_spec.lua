--- test/spec/workspace_command_spec.lua
--- Regression: :Workspace must invoke router.open("workspace").

describe(":Workspace + sub-router commands", function()
  local saved_router_loaded
  local captured

  before_each(function()
    captured = {}
    saved_router_loaded = package.loaded["router"]
    package.loaded["router"] = {
      open = function(id, ctx)
        captured[#captured + 1] = { id = id, ctx = ctx }
      end,
      register_subtree = function(_, _) end,
      _internal = {
        tree = {
          has = function(_) return true end,
        },
      },
    }
    package.loaded["workspace.router_subtree"] = package.loaded["workspace.router_subtree"]
      or { id = "workspace" }

    require("workspace.commands").setup_template_commands()
  end)

  after_each(function()
    package.loaded["router"] = saved_router_loaded
  end)

  it(":Workspace invokes router.open('workspace')", function()
    vim.api.nvim_cmd({ cmd = "Workspace" }, {})
    assert.equals(1, #captured)
    assert.equals("workspace", captured[1].id)
  end)

  local sub_cases = {
    { cmd = "WorkspaceSession", node = "workspace_session" },
    { cmd = "WorkspaceProject", node = "workspace_project" },
    { cmd = "WorkspaceTab",     node = "workspace_tab" },
    { cmd = "WorkspaceOps",     node = "workspace_ops" },
    { cmd = "WorkspaceSearch",  node = "workspace_search" },
  }

  for _, c in ipairs(sub_cases) do
    it(":" .. c.cmd .. " invokes router.open('" .. c.node .. "')", function()
      vim.api.nvim_cmd({ cmd = c.cmd }, {})
      assert.equals(1, #captured)
      assert.equals(c.node, captured[1].id)
    end)
  end
end)
