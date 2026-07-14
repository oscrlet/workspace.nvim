--- test/spec/template_migration_spec.lua
--- Verify one-time migration: templates/ -> tab_templates/.

local template_store = require("workspace.template.store")
local path_util = require("workspace.util.path")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d)
  vim.fn.delete(d, "rf")
end

local function exists(p)
  return (vim.uv or vim.loop).fs_stat(p) ~= nil
end

local function write_file(p, contents)
  local f = assert(io.open(p, "w"))
  f:write(contents)
  f:close()
end

describe("template migration", function()
  local data_root
  local original_data_dir

  before_each(function()
    data_root = tmpdir()
    original_data_dir = path_util.data_dir
    path_util.data_dir = function() return data_root end
    -- Ensure store does not skip migration via injected _dir.
    template_store._dir = nil
    template_store._reset_migration()
  end)

  after_each(function()
    path_util.data_dir = original_data_dir
    template_store._reset_migration()
    rmdir(data_root)
  end)

  it("migrates legacy templates/ to tab_templates/ on first dir() call", function()
    local legacy = data_root .. "/templates"
    local target = data_root .. "/tab_templates"
    vim.fn.mkdir(legacy, "p")
    write_file(legacy .. "/sample.json", '{"cwd":"/tmp","project_ids":[]}')

    assert.is_true(exists(legacy))
    assert.is_false(exists(target))

    local d = template_store.dir()
    assert.equals(target, d)

    assert.is_true(exists(target))
    assert.is_true(exists(target .. "/sample.json"))
    -- Legacy directory should no longer exist (renamed).
    assert.is_false(exists(legacy))
  end)

  it("is idempotent: second call does not re-run migration", function()
    local legacy = data_root .. "/templates"
    local target = data_root .. "/tab_templates"
    vim.fn.mkdir(legacy, "p")
    write_file(legacy .. "/one.json", "{}")

    template_store.dir() -- triggers migration
    assert.is_true(exists(target .. "/one.json"))

    -- Re-create legacy with a DIFFERENT file. Since migration already ran
    -- (flag set), this should NOT be moved on subsequent dir() calls.
    vim.fn.mkdir(legacy, "p")
    write_file(legacy .. "/two.json", "{}")

    local ok = pcall(template_store.dir)
    assert.is_true(ok)
    -- two.json should remain in legacy (migration did not re-run).
    assert.is_true(exists(legacy .. "/two.json"))
    assert.is_false(exists(target .. "/two.json"))
  end)

  it("no-op when no legacy dir exists", function()
    local legacy = data_root .. "/templates"
    local target = data_root .. "/tab_templates"
    assert.is_false(exists(legacy))
    assert.is_false(exists(target))

    local ok, d = pcall(template_store.dir)
    assert.is_true(ok)
    assert.equals(target, d)
    -- dir() itself does not create target (callers do via ensure_dir).
    -- But it must not error and must not create a legacy dir.
    assert.is_false(exists(legacy))
  end)

  it("skips migration when target already exists", function()
    local legacy = data_root .. "/templates"
    local target = data_root .. "/tab_templates"
    vim.fn.mkdir(legacy, "p")
    vim.fn.mkdir(target, "p")
    write_file(legacy .. "/legacy.json", "{}")
    write_file(target .. "/new.json", "{}")

    template_store.dir()

    -- Legacy preserved; target untouched.
    assert.is_true(exists(legacy .. "/legacy.json"))
    assert.is_true(exists(target .. "/new.json"))
    assert.is_false(exists(target .. "/legacy.json"))
  end)
end)
