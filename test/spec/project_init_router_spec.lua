-- Tests for the workspace_project_init router node — verifies the parent
-- items list gains an "init" entry and confirming the node triggers the
-- :ProjectInit flow (registry.register + .project write when no marker).

-- Ensure the workspace.nvim plugin dir is on rtp regardless of how the
-- harness was launched (the user's init.lua may error before lazy.nvim
-- adds it, and PlenaryBustedFile doesn't guarantee rtp inheritance).
do
  local plugin_dir = vim.fn.expand("~/code/neovim/plugins/workspace.nvim")
  if vim.fn.isdirectory(plugin_dir) == 1 then
    vim.opt.runtimepath:prepend(plugin_dir)
  end
end

local registry = require("workspace.project.registry")
local store    = require("workspace.project.store")
local dotfile  = require("workspace.project.dotfile")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function tmppath()
  return vim.fn.tempname() .. "_projects.json"
end

local function fresh_registry()
  store._path = tmppath()
  registry.setup({})
end

local function cleanup_registry()
  if store._path then
    os.remove(store._path)
    os.remove(store._path .. ".bak")
    os.remove(store._path .. ".tmp")
  end
  store._path = nil
end

local function load_subtree_fresh()
  package.loaded["workspace.router_subtree"] = nil
  package.loaded["workspace.router_subtree.nodes"] = nil
  package.loaded["workspace.router_subtree.nodes.project"] = nil
  return require("workspace.router_subtree")
end

describe("workspace_project_init router node", function()
  local dirs
  local saved_cwd

  before_each(function()
    dirs = {}
    saved_cwd = vim.fn.getcwd()
    fresh_registry()
    require("workspace.commands").setup_project_commands()
  end)

  after_each(function()
    cleanup_registry()
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(saved_cwd))
    for _, d in ipairs(dirs) do vim.fn.delete(d, "rf") end
    pcall(vim.api.nvim_del_user_command, "ProjectInit")
  end)

  it("workspace_project items expose an 'init' entry between add and discover", function()
    local subtree = load_subtree_fresh()
    local parent = subtree.nodes.workspace_project
    assert.is_table(parent)
    assert.is_table(parent.items)
    local ids = {}
    for _, it in ipairs(parent.items) do table.insert(ids, it.id) end
    -- Must contain "init".
    local has_init = false
    for _, id in ipairs(ids) do if id == "init" then has_init = true end end
    assert.is_true(has_init, "workspace_project.items missing id='init'")
    -- Order: list, add, init, discover.
    local pos = {}
    for i, id in ipairs(ids) do pos[id] = i end
    assert.is_true(pos.add < pos.init,      "init must come after add")
    assert.is_true(pos.init < pos.discover, "init must come before discover")
  end)

  it("confirming the init item registers cwd and writes .project when no marker", function()
    local d = tmpdir(); table.insert(dirs, d)
    vim.cmd("cd " .. vim.fn.fnameescape(d))

    local subtree = load_subtree_fresh()
    local node = subtree.nodes.workspace_project_init
    assert.is_table(node)
    -- The node's items() must return the single cwd row.
    local items = node.items()
    assert.equals(1, #items)
    -- Confirm.
    node.on_confirm(items[1])
    -- .project must now exist at the tmpdir.
    assert.is_truthy(vim.uv.fs_stat(d .. "/.project"))
    local payload = dotfile.read(d)
    assert.is_table(payload)
    -- Registry must have it.
    local real = (require("workspace.util.path").realpath and
                  require("workspace.util.path").realpath(d)) or d
    local proj = registry.find_by_root(real)
    assert.is_table(proj)
    assert.equals(payload.id, proj.id)
  end)

  it("on_confirm returns 'workspace_project_list'", function()
    local d = tmpdir(); table.insert(dirs, d)
    vim.cmd("cd " .. vim.fn.fnameescape(d))

    local subtree = load_subtree_fresh()
    local node = subtree.nodes.workspace_project_init
    local items = node.items()
    local next_id = node.on_confirm(items[1])
    assert.equals("workspace_project_list", next_id)
  end)
end)
