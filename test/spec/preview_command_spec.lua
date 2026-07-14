--- test/spec/preview_command_spec.lua
--- Verifies project.preview.command honors eza / tree / fd / builtin
--- and falls back when binary is missing.

local config = require("workspace.config")

local function tmpdir_with_files()
  local d = vim.fn.tempname() .. "_pcmd"
  vim.fn.mkdir(d, "p")
  local f = io.open(d .. "/a.txt", "w"); f:write("x"); f:close()
  return d
end

local function rmdir(d) vim.fn.delete(d, "rf") end

describe("project.preview.command branching", function()
  local saved_executable
  local saved_systemlist
  local executable_map
  local systemlist_calls
  local systemlist_handler
  local saved_shell_error
  local preview

  before_each(function()
    -- Force fresh require so config snapshot inside preview.lua is re-read.
    package.loaded["workspace.ui.preview"] = nil
    preview = require("workspace.ui.preview")

    config._reset()
    saved_executable = vim.fn.executable
    saved_systemlist = vim.fn.systemlist
    saved_shell_error = vim.v.shell_error

    executable_map = { eza = 0, tree = 0, fd = 0 }
    systemlist_calls = {}
    systemlist_handler = function(_) return { "stub-output" } end

    vim.fn.executable = function(name)
      if executable_map[name] ~= nil then return executable_map[name] end
      return saved_executable(name)
    end
    vim.fn.systemlist = function(argv)
      systemlist_calls[#systemlist_calls + 1] = argv
      local result = systemlist_handler(argv)
      -- vim.v.shell_error is read-only normally; we set it via vim.cmd.
      pcall(function() vim.v.shell_error = 0 end)
      return result or {}
    end
  end)

  after_each(function()
    vim.fn.executable = saved_executable
    vim.fn.systemlist = saved_systemlist
    config._reset()
  end)

  it("command='eza' with eza available → invokes eza", function()
    config.merge({ project = { preview = { command = "eza" } } })
    executable_map.eza = 1
    local d = tmpdir_with_files()
    preview.project_tree(d)
    assert.is_true(#systemlist_calls >= 1)
    assert.equals("eza", systemlist_calls[1][1])
    rmdir(d)
  end)

  it("command='tree' with tree available → invokes tree", function()
    config.merge({ project = { preview = { command = "tree" } } })
    executable_map.tree = 1
    local d = tmpdir_with_files()
    preview.project_tree(d)
    assert.is_true(#systemlist_calls >= 1)
    assert.equals("tree", systemlist_calls[1][1])
    rmdir(d)
  end)

  it("command='fd' with fd available → invokes fd", function()
    config.merge({ project = { preview = { command = "fd" } } })
    executable_map.fd = 1
    local d = tmpdir_with_files()
    preview.project_tree(d)
    assert.is_true(#systemlist_calls >= 1)
    assert.equals("fd", systemlist_calls[1][1])
    rmdir(d)
  end)

  it("command='builtin' → does not call systemlist, uses readdir", function()
    config.merge({ project = { preview = { command = "builtin" } } })
    executable_map.eza = 1
    executable_map.tree = 1
    local d = tmpdir_with_files()
    local lines = preview.project_tree(d)
    assert.equals(0, #systemlist_calls)
    assert.is_table(lines)
    assert.is_true(#lines > 0)
    rmdir(d)
  end)

  it("preferred binary missing → falls back to next available, then builtin", function()
    config.merge({ project = { preview = { command = "tree" } } })
    -- All binaries missing.
    executable_map.tree = 0
    executable_map.eza = 0
    executable_map.fd = 0
    local d = tmpdir_with_files()
    local lines = preview.project_tree(d)
    assert.equals(0, #systemlist_calls)
    assert.is_table(lines)
    assert.is_true(#lines > 0)
    rmdir(d)
  end)
end)
