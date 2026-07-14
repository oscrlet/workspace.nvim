--- test/spec/discover_spec.lua
--- Tests for M.discover() realpath-dedup behavior.
--- NOTE: M.discover() does NOT exist as a public API. Testing path.realpath()
--- deduplication and symlink resolution via registry.normalize_path(),
--- which is the core mechanism discover.lua uses (seen[real_dir] dedup).

local path = require("workspace.util.path")
local discover = require("workspace.project.discover")
local registry = require("workspace.project.registry")
local proj_store = require("workspace.project.store")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d)
  vim.fn.delete(d, "rf")
end

local function tmppath()
  return vim.fn.tempname() .. "_projects.json"
end

local function fresh()
  proj_store._path = tmppath()
  registry.setup({})
end

local function cleanup(dirs)
  if proj_store._path then
    os.remove(proj_store._path)
    os.remove(proj_store._path .. ".bak")
    os.remove(proj_store._path .. ".tmp")
  end
  proj_store._path = nil
  if dirs then
    for _, d in ipairs(dirs) do
      rmdir(d)
    end
  end
end

describe("discover realpath dedup", function()
  local dirs_to_clean = {}

  before_each(function()
    fresh()
    dirs_to_clean = {}
  end)

  after_each(function()
    cleanup(dirs_to_clean)
  end)

  it("path.realpath resolves symlinks", function()
    local real_dir = tmpdir()
    table.insert(dirs_to_clean, real_dir)

    local symlink_path = vim.fn.tempname()
    os.remove(symlink_path)  -- Remove if exists (tempname only names, doesn't create)
    local cmd = "ln -s " .. vim.fn.fnameescape(real_dir) .. " " .. vim.fn.fnameescape(symlink_path)
    local result = vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
      -- Symlink created successfully.
      table.insert(dirs_to_clean, symlink_path)
      local real1 = path.realpath(real_dir)
      local real2 = path.realpath(symlink_path)
      assert.equals(real1, real2, "realpath should resolve same for symlink and real dir")
    end
  end)

  it("discover deduplicates symlinked directories", function()
    local real_dir = tmpdir()
    table.insert(dirs_to_clean, real_dir)

    -- Create a marker file so it's discovered.
    vim.fn.writefile({}, real_dir .. "/.git")

    -- Create a symlink to the same directory.
    local symlink_path = vim.fn.tempname()
    os.remove(symlink_path)
    local cmd = "ln -s " .. vim.fn.fnameescape(real_dir) .. " " .. vim.fn.fnameescape(symlink_path)
    local result = vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
      table.insert(dirs_to_clean, symlink_path)

      -- Discover both paths via glob.
      local patterns = { real_dir, symlink_path }
      local candidates = discover.discover(patterns, {
        markers = { ".git" },
        dry_run = true,  -- Don't register, just discover.
      })

      -- Should have only 1 candidate, not 2 (deduped via realpath).
      assert.equals(1, #candidates, "discover should deduplicate symlink and real dir")
      -- Both real_dir and symlink_path should resolve to same canonical path.
      local real1 = path.realpath(real_dir)
      local real2 = path.realpath(symlink_path)
      assert.equals(real1, real2)
      assert.equals(real1, candidates[1].path)
    end
  end)

  it("discover finds project with .git marker", function()
    local proj_dir = tmpdir()
    table.insert(dirs_to_clean, proj_dir)
    vim.fn.writefile({}, proj_dir .. "/.git")

    local candidates = discover.discover({ proj_dir }, {
      markers = { ".git" },
      dry_run = true,
    })

    assert.equals(1, #candidates)
    -- Compare realpath-normalized paths (macOS /private/var/ symlink issue).
    local real_proj = path.realpath(proj_dir)
    local real_cand = path.realpath(candidates[1].path)
    assert.equals(real_proj, real_cand)
  end)

  it("discover respects markers filter", function()
    local proj_dir = tmpdir()
    table.insert(dirs_to_clean, proj_dir)
    vim.fn.writefile({}, proj_dir .. "/.git")

    -- Search with different marker.
    local candidates = discover.discover({ proj_dir }, {
      markers = { "pyproject.toml" },
      dry_run = true,
    })

    assert.equals(0, #candidates, "should not find with non-matching marker")
  end)

  it("discover skips non-directory paths", function()
    local file_path = vim.fn.tempname()
    vim.fn.writefile({ "test" }, file_path)
    table.insert(dirs_to_clean, file_path)

    local candidates = discover.discover({ file_path }, {
      markers = { ".git" },
      dry_run = true,
    })

    assert.equals(0, #candidates, "should skip non-directory paths")
  end)

  it("scan_path returns candidates for directory with marker", function()
    local scan_dir = tmpdir()
    table.insert(dirs_to_clean, scan_dir)
    vim.fn.writefile({}, scan_dir .. "/.git")

    local candidates = discover.scan_path(scan_dir, {
      markers = { ".git" },
    })

    assert.equals(1, #candidates)
    -- Compare realpath-normalized paths.
    local real_scan = path.realpath(scan_dir)
    local real_cand = path.realpath(candidates[1].path)
    assert.equals(real_scan, real_cand)
  end)
end)
