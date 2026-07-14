local store = require("workspace.project.store")
local registry = require("workspace.project.registry")
local migrate = require("workspace.migrate.projections")
local id_util = require("workspace.util.id")

local function tmppath()
  return vim.fn.tempname() .. "_projects.json"
end

local function tmpdir()
  local d = vim.fn.tempname() .. "_dir"
  vim.fn.mkdir(d, "p")
  return d
end

local function write_file(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

local function fresh()
  store._path = tmppath()
  registry.setup({})
end

local _tmp_paths = {}
local _tmp_dirs = {}

local function track_path(p)
  _tmp_paths[#_tmp_paths + 1] = p
  return p
end

local function track_dir(p)
  _tmp_dirs[#_tmp_dirs + 1] = p
  return p
end

local function cleanup()
  if store._path then
    os.remove(store._path)
    os.remove(store._path .. ".bak")
    os.remove(store._path .. ".tmp")
  end
  store._path = nil
  for _, p in ipairs(_tmp_paths) do os.remove(p) end
  _tmp_paths = {}
  for _, d in ipairs(_tmp_dirs) do
    pcall(vim.fn.delete, d, "rf")
  end
  _tmp_dirs = {}
end

describe("migrate.projections", function()
  before_each(fresh)
  after_each(cleanup)

  it("happy path: registers all unique roots with meta.auto", function()
    local d1 = track_dir(tmpdir())
    local d2 = track_dir(tmpdir())
    local d3 = track_dir(tmpdir())
    local src = track_path(tmppath())
    write_file(src, vim.json.encode({
      sessA = { d1, d2 },
      sessB = { d2, d3 },  -- d2 repeats; should be deduped
    }))

    local result, err = migrate.run({ src_path = src })
    assert.is_nil(err)
    assert.is_table(result)
    assert.equals(3, #result.added)
    assert.equals(0, #result.errors)

    local listed = registry.list()
    assert.equals(3, #listed)
    for _, p in ipairs(listed) do
      assert.equals("migrate_projections", p.meta and p.meta.auto)
    end

    -- ids should match basename-derived ids for the unique roots.
    local got_roots = {}
    for _, p in ipairs(listed) do got_roots[p.root] = true end
    local function real(p)
      return (vim.uv and vim.uv.fs_realpath and vim.uv.fs_realpath(p)) or p
    end
    assert.is_true(got_roots[real(d1)] == true)
    assert.is_true(got_roots[real(d2)] == true)
    assert.is_true(got_roots[real(d3)] == true)
  end)

  it("dry-run: leaves registry untouched, returns candidates", function()
    local d1 = track_dir(tmpdir())
    local d2 = track_dir(tmpdir())
    local d3 = track_dir(tmpdir())
    local src = track_path(tmppath())
    write_file(src, vim.json.encode({
      sess = { d1, d2, d3 },
    }))

    local before = #registry.list()
    local result, err = migrate.run({ src_path = src, dry_run = true })
    assert.is_nil(err)
    assert.is_table(result)
    assert.equals(3, #result.added)
    assert.equals(before, #registry.list())
    -- All candidates carry the meta tag.
    for _, a in ipairs(result.added) do
      assert.equals("migrate_projections", a.meta.auto)
    end
  end)

  it("skip: pre-registered root reported in skipped", function()
    local d1 = track_dir(tmpdir())
    local d2 = track_dir(tmpdir())
    local src = track_path(tmppath())
    write_file(src, vim.json.encode({ sess = { d1, d2 } }))

    -- Pre-register d1.
    registry.register({ path = d1 })

    local result, err = migrate.run({ src_path = src })
    assert.is_nil(err)
    assert.equals(1, #result.added)
    assert.equals(1, #result.skipped)
    assert.equals(0, #result.errors)
  end)

  it("id collision: pre-existing id with different root resolves cleanly", function()
    -- When derive() would collide with an existing id pointing to a
    -- different root, the migration must NOT clobber the existing
    -- entry. It either reports an error OR derives a fresh id (parent-
    -- prefixed) and adds the project under that. Both outcomes are
    -- spec-acceptable; what matters is that the pre-registered entry
    -- stays intact.
    local d1 = track_dir(tmpdir())
    local d2 = track_dir(tmpdir())
    local src = track_path(tmppath())
    write_file(src, vim.json.encode({ sess = { d1 } }))

    local real_d1 = (vim.uv and vim.uv.fs_realpath and vim.uv.fs_realpath(d1)) or d1
    local id1 = id_util.derive(real_d1, {})
    -- Pre-register id1 pointing to a *different* root.
    registry.register({ id = id1, path = d2 })
    local pre_root = registry.get(id1).root

    local result, err = migrate.run({ src_path = src })
    assert.is_nil(err)
    -- Total of added+errors covers exactly this one source root.
    assert.equals(1, #result.added + #result.errors)
    -- Pre-existing entry untouched.
    assert.equals(pre_root, registry.get(id1).root)
  end)

  it("missing src returns err", function()
    local result, err = migrate.run({ src_path = "/nonexistent/path/projections.json" })
    assert.is_nil(result)
    assert.is_string(err)
    assert.is_truthy(err:find("not found", 1, true))
  end)

  it("malformed JSON returns err", function()
    local src = track_path(tmppath())
    write_file(src, "{not valid json")
    local result, err = migrate.run({ src_path = src })
    assert.is_nil(result)
    assert.is_string(err)
    assert.is_truthy(err:find("invalid JSON", 1, true))
  end)
end)
