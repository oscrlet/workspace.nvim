local dotfile  = require("workspace.project.dotfile")
local discover = require("workspace.project.discover")
local registry = require("workspace.project.registry")
local store    = require("workspace.project.store")

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

describe("project.dotfile", function()
  local dirs

  before_each(function()
    dirs = {}
    fresh_registry()
  end)

  after_each(function()
    cleanup_registry()
    for _, d in ipairs(dirs) do vim.fn.delete(d, "rf") end
  end)

  it("path joins dir + .project", function()
    assert.equals("/tmp/foo/.project", dotfile.path("/tmp/foo"))
    assert.equals("/tmp/foo/.project", dotfile.path("/tmp/foo/"))
  end)

  it("read returns nil when file absent", function()
    local d = tmpdir(); table.insert(dirs, d)
    assert.is_nil(dotfile.read(d))
  end)

  it("write then read round-trips id/name/meta", function()
    local d = tmpdir(); table.insert(dirs, d)
    local ok, err = dotfile.write(d, {
      id = "myproj", name = "My Proj",
      meta = { lang = "lua", year = 2026 },
    })
    assert.is_true(ok, tostring(err))
    local payload = dotfile.read(d)
    assert.is_table(payload)
    assert.equals(1, payload.version)
    assert.equals("myproj", payload.id)
    assert.equals("My Proj", payload.name)
    assert.is_table(payload.meta)
    assert.equals("lua", payload.meta.lang)
    assert.equals(2026, payload.meta.year)
    assert.is_number(payload.created_at)
  end)

  it("write rejects missing id", function()
    local d = tmpdir(); table.insert(dirs, d)
    local ok, err = dotfile.write(d, { name = "no-id" })
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("read returns nil on invalid JSON", function()
    local d = tmpdir(); table.insert(dirs, d)
    vim.fn.writefile({ "not json {" }, dotfile.path(d))
    assert.is_nil(dotfile.read(d))
  end)
end)

describe("discover honors .project authoritatively", function()
  local dirs

  before_each(function()
    dirs = {}
    fresh_registry()
  end)

  after_each(function()
    cleanup_registry()
    for _, d in ipairs(dirs) do vim.fn.delete(d, "rf") end
  end)

  it("suggested_id from .project overrides basename", function()
    local d = tmpdir(); table.insert(dirs, d)
    -- .project IS one of the default markers, so it satisfies has_marker.
    dotfile.write(d, { id = "authoritative_id", name = "Authoritative" })
    local cands = discover.discover({ d }, {
      markers = { ".project" }, dry_run = true,
    })
    assert.equals(1, #cands)
    assert.equals("authoritative_id", cands[1].suggested_id)
    assert.equals("Authoritative", cands[1].suggested_name)
  end)

  it("falls back to basename when .project missing", function()
    local d = tmpdir(); table.insert(dirs, d)
    vim.fn.writefile({}, d .. "/.git")
    local cands = discover.discover({ d }, {
      markers = { ".git" }, dry_run = true,
    })
    assert.equals(1, #cands)
    -- basename of tempname-derived dir is sanitized; just assert non-empty
    -- and that it doesn't accidentally pick up a phantom name field.
    assert.is_string(cands[1].suggested_id)
    assert.is_truthy(#cands[1].suggested_id > 0)
    assert.is_nil(cands[1].suggested_name)
  end)
end)

describe(":ProjectInit", function()
  local dirs

  before_each(function()
    dirs = {}
    fresh_registry()
    -- The command is registered at setup time; install it directly here so
    -- the spec doesn't depend on the full workspace.setup() chain.
    require("workspace.commands").setup_project_commands()
  end)

  after_each(function()
    cleanup_registry()
    for _, d in ipairs(dirs) do vim.fn.delete(d, "rf") end
    pcall(vim.api.nvim_del_user_command, "ProjectInit")
  end)

  it("creates .project + registers when no marker present", function()
    local d = tmpdir(); table.insert(dirs, d)
    vim.cmd("ProjectInit " .. vim.fn.fnameescape(d))
    -- .project must exist now.
    assert.is_truthy(vim.uv.fs_stat(d .. "/.project"))
    local payload = require("workspace.project.dotfile").read(d)
    assert.is_table(payload)
    assert.is_string(payload.id)
    -- The dir must be registered.
    local proj = registry.find_by_root(d)
    assert.is_table(proj)
    assert.equals(payload.id, proj.id)
  end)

  it("skips .project write when existing marker present", function()
    local d = tmpdir(); table.insert(dirs, d)
    vim.fn.writefile({}, d .. "/.git")
    vim.cmd("ProjectInit " .. vim.fn.fnameescape(d))
    -- No .project should have been written.
    local stat = vim.uv.fs_stat(d .. "/.project")
    assert.is_nil(stat)
    -- The dir must still be registered.
    assert.is_table(registry.find_by_root(d))
  end)

  it("honors existing .project id over derive", function()
    local d = tmpdir(); table.insert(dirs, d)
    require("workspace.project.dotfile").write(d,
      { id = "preset_id", name = "Preset" })
    vim.cmd("ProjectInit " .. vim.fn.fnameescape(d))
    local proj = registry.find_by_root(d)
    assert.is_table(proj)
    assert.equals("preset_id", proj.id)
    assert.equals("Preset", proj.name)
  end)

  it("is idempotent: second call doesn't duplicate", function()
    local d = tmpdir(); table.insert(dirs, d)
    vim.cmd("ProjectInit " .. vim.fn.fnameescape(d))
    local first = registry.find_by_root(d)
    vim.cmd("ProjectInit " .. vim.fn.fnameescape(d))
    local listing = registry.list()
    local matches = 0
    for _, p in ipairs(listing) do
      if p.root == first.root then matches = matches + 1 end
    end
    assert.equals(1, matches)
  end)
end)
