--- test/spec/preview_spec.lua
--- Busted: ui.preview tree/detail rendering.
--- Uses temporary directories for project_tree tests.

local preview = require("workspace.ui.preview")
local session_store = require("workspace.session.store")
local project_mod = require("workspace.project")

-- Temp directory with sample structure.
local function tmpdir_with_files()
  local d = vim.fn.tempname() .. "_preview"
  vim.fn.mkdir(d, "p")
  -- Create some files to ensure non-empty readdir.
  vim.fn.mkdir(d .. "/subdir", "p")
  local f = io.open(d .. "/file1.txt", "w")
  f:write("content")
  f:close()
  local f2 = io.open(d .. "/subdir/file2.txt", "w")
  f2:write("content")
  f2:close()
  return d
end

-- Clean up a directory tree.
local function rmdir(d)
  vim.fn.delete(d, "rf")
end

describe("ui.preview", function()
  before_each(function()
    -- Reset project registry.
    local registry = require("workspace.project.registry")
    registry.setup({})
  end)

  it("project_tree returns non-empty array for directory with files", function()
    local tmpdir = tmpdir_with_files()

    local lines = preview.project_tree(tmpdir)

    assert.is_table(lines)
    assert.is_true(#lines > 0)
    -- First line should be the directory path or a file/folder name.
    assert.is_string(lines[1])

    rmdir(tmpdir)
  end)

  it("project_tree handles empty directory gracefully", function()
    local tmpdir = vim.fn.tempname() .. "_empty"
    vim.fn.mkdir(tmpdir, "p")

    local lines = preview.project_tree(tmpdir)

    assert.is_table(lines)
    assert.is_true(#lines > 0)

    rmdir(tmpdir)
  end)

  it("project_tree handles empty root string", function()
    local lines = preview.project_tree("")

    assert.is_table(lines)
    assert.is_true(#lines > 0)
    -- Should return a fallback message.
    assert.is_string(lines[1])
  end)

  it("session_tree returns table for existing session JSON", function()
    local tmpdir = vim.fn.tempname() .. "_sess"
    vim.fn.mkdir(tmpdir, "p")
    session_store._dir = tmpdir

    -- Write a stub session.
    local stub_data = {
      version = 1,
      tabs = {
        {
          id = "tab1",
          label = "Project A",
          order = 1,
          cwd = "/tmp/proj_a",
          project_ids = { "proj_a1", "proj_a2" },
          active_project_id = "proj_a1",
        },
      },
      active_tab_id = "tab1",
    }

    local ok, err = session_store.write("test_session", stub_data)
    assert.is_truthy(ok, "write failed: " .. tostring(err))

    local lines = preview.session_tree("test_session")

    assert.is_table(lines)
    assert.is_true(#lines > 0)
    -- Should contain session name.
    local found_header = false
    for _, line in ipairs(lines) do
      if line:match("Session:") then
        found_header = true
        break
      end
    end
    assert.is_true(found_header)

    session_store._dir = nil
    rmdir(tmpdir)
  end)

  it("session_tree degrades gracefully when session missing", function()
    local tmpdir = vim.fn.tempname() .. "_missing"
    vim.fn.mkdir(tmpdir, "p")
    session_store._dir = tmpdir

    local lines = preview.session_tree("nonexistent_session")

    assert.is_table(lines)
    assert.is_true(#lines > 0)
    -- Should contain fallback message.
    local found_fallback = false
    for _, line in ipairs(lines) do
      if line:match("unable to load") or line:match("Session:") then
        found_fallback = true
        break
      end
    end
    assert.is_true(found_fallback)

    session_store._dir = nil
    rmdir(tmpdir)
  end)

  it("tab_detail returns lines with cwd and projects", function()
    local registry = require("workspace.project.registry")
    local tmpdir = vim.fn.tempname() .. "_proj"
    vim.fn.mkdir(tmpdir, "p")

    local proj = registry.register({ path = tmpdir, id = "test_proj", name = "TestProj" })

    local tab = {
      cwd = "/tmp/workspace",
      project_ids = { proj.id },
      active_project_id = proj.id,
    }

    local lines = preview.tab_detail(tab)

    assert.is_table(lines)
    assert.is_true(#lines > 0)

    -- Should contain cwd.
    local found_cwd = false
    for _, line in ipairs(lines) do
      if line:match("cwd:") then
        found_cwd = true
        break
      end
    end
    assert.is_true(found_cwd)

    rmdir(tmpdir)
  end)

  it("tab_detail handles nil tab gracefully", function()
    local lines = preview.tab_detail(nil)

    assert.is_table(lines)
    assert.is_true(#lines > 0)
    assert.is_string(lines[1])
  end)
end)

-- --------------------------------------------------------------------
-- F3: bare :ProjectList / :SessionList wire preview pane into Snacks.
-- We stub _G.Snacks.picker.pick to capture the spec and assert it
-- carries a preview function that returns string[] for sample items
-- and degrades gracefully for nil / missing fields.
-- --------------------------------------------------------------------
describe("F3 preview wiring (bare picker commands)", function()
  local saved_snacks
  local captured

  before_each(function()
    captured = nil
    saved_snacks = _G.Snacks
    _G.Snacks = {
      picker = {
        pick = function(spec) captured = spec end,
      },
    }
    -- Ensure commands are registered.
    require("workspace.commands").setup()
    -- Reset project registry.
    local registry = require("workspace.project.registry")
    registry.setup({})
  end)

  after_each(function()
    _G.Snacks = saved_snacks
  end)

  it(":ProjectList picker spec carries a preview function", function()
    local registry = require("workspace.project.registry")
    local tmpdir = tmpdir_with_files()
    registry.register({ path = tmpdir, id = "f3_proj", name = "F3Proj" })

    vim.cmd("ProjectList")

    assert.is_table(captured)
    assert.is_function(captured.preview)

    -- Mock ctx with preview adapter that records lines.
    local seen
    local ctx = {
      item = { id = "f3_proj", name = "F3Proj", root = tmpdir },
      preview = {
        reset = function() end,
        set_lines = function(_, lines) seen = lines end,
      },
    }
    local lines = captured.preview(ctx)
    assert.is_table(lines)
    assert.is_true(#lines > 0)
    assert.is_table(seen)
    assert.is_true(#seen > 0)

    rmdir(tmpdir)
  end)

  it(":ProjectList preview is graceful for nil item and missing root", function()
    vim.cmd("ProjectList")
    assert.is_function(captured.preview)

    local function probe(item)
      local out
      local ctx = {
        item = item,
        preview = {
          reset = function() end,
          set_lines = function(_, lines) out = lines end,
        },
      }
      local lines = captured.preview(ctx)
      assert.is_table(lines)
      assert.is_true(#lines > 0)
      assert.is_string(lines[1])
      return out
    end

    probe(nil)
    probe({})
    probe({ name = "no-root" })
  end)

  it(":SessionList picker spec carries a preview function", function()
    local tmpdir = vim.fn.tempname() .. "_f3_sess"
    vim.fn.mkdir(tmpdir, "p")
    session_store._dir = tmpdir

    local stub_data = {
      version = 1,
      tabs = {
        {
          id = "tab1",
          label = "Project A",
          order = 1,
          cwd = "/tmp/proj_a",
          project_ids = { "proj_a1" },
          active_project_id = "proj_a1",
        },
      },
      active_tab_id = "tab1",
    }
    assert.is_truthy(session_store.write("f3_session", stub_data))

    vim.cmd("SessionList")

    assert.is_table(captured)
    assert.is_function(captured.preview)

    local seen
    local ctx = {
      item = { name = "f3_session" },
      preview = {
        reset = function() end,
        set_lines = function(_, lines) seen = lines end,
      },
    }
    local lines = captured.preview(ctx)
    assert.is_table(lines)
    assert.is_true(#lines > 0)
    assert.is_table(seen)
    assert.is_true(#seen > 0)
    -- header should mention session name
    local found = false
    for _, l in ipairs(lines) do
      if l:match("Session:") then found = true; break end
    end
    assert.is_true(found)

    session_store._dir = nil
    rmdir(tmpdir)
  end)

  it(":SessionList preview is graceful for nil item and missing name", function()
    vim.cmd("SessionList")
    assert.is_function(captured.preview)

    local function probe(item)
      local out
      local ctx = {
        item = item,
        preview = {
          reset = function() end,
          set_lines = function(_, lines) out = lines end,
        },
      }
      local lines = captured.preview(ctx)
      assert.is_table(lines)
      assert.is_true(#lines > 0)
      assert.is_string(lines[1])
      return out
    end

    probe(nil)
    probe({})
    probe({ name = "" })
  end)
end)
