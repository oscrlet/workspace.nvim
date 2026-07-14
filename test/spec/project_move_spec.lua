--- test/spec/project_move_spec.lua
--- Busted: project.api.move + :ProjectMove command.

local commands   = require("workspace.commands")
local registry   = require("workspace.project.registry")
local proj_store = require("workspace.project.store")
local api        = require("workspace.project.api")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return (vim.uv and vim.uv.fs_realpath and vim.uv.fs_realpath(d)) or d
end

local function rmdir(d) vim.fn.delete(d, "rf") end

describe("project.api.move + :ProjectMove", function()
  local proj_dir, root_a, root_b
  local notifies, orig_notify
  local update_events

  before_each(function()
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    root_a = tmpdir()
    root_b = tmpdir()
    registry.register({ path = root_a, id = "alpha", name = "Alpha" })

    notifies = {}
    orig_notify = vim.notify
    vim.notify = function(msg, lvl) table.insert(notifies, { msg = msg, level = lvl }) end

    update_events = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "WorkspaceProjectUpdated",
      callback = function(args) table.insert(update_events, args.data) end,
    })

    commands.setup_project_commands()
  end)

  after_each(function()
    vim.notify = orig_notify
    pcall(vim.api.nvim_clear_autocmds, { event = "User", pattern = "WorkspaceProjectUpdated" })
    proj_store._path = nil
    rmdir(proj_dir)
    rmdir(root_a)
    rmdir(root_b)
  end)

  it("moves an existing project root to a real directory and fires WorkspaceProjectUpdated", function()
    local ok, err = api.move("alpha", root_b)
    assert.is_true(ok, err)
    local p = registry.get("alpha")
    assert.equals(root_b, p.root)
    assert.equals("alpha", p.id)
    assert.is_true(#update_events >= 1)
    assert.equals("alpha", update_events[#update_events].id)
  end)

  it("returns false + error for non-existent id, no events", function()
    update_events = {}
    local ok, err = api.move("ghost", root_b)
    assert.is_false(ok)
    assert.is_string(err)
    assert.matches("not found", err)
    assert.equals(0, #update_events)
  end)

  it("returns false for non-existent path, no mutation", function()
    update_events = {}
    local bogus = "/this/path/should/not/exist/" .. tostring(os.time()) .. "_x"
    local ok, err = api.move("alpha", bogus)
    assert.is_false(ok)
    assert.is_string(err)
    local p = registry.get("alpha")
    assert.equals(root_a, p.root)
    assert.equals(0, #update_events)
  end)

  it(":ProjectMove user command moves the project", function()
    vim.cmd("ProjectMove alpha " .. root_b)
    local p = registry.get("alpha")
    assert.equals(root_b, p.root)
  end)
end)
