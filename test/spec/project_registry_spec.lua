local store = require("workspace.project.store")
local registry = require("workspace.project.registry")

local function tmppath()
  return vim.fn.tempname() .. "_projects.json"
end

local function fresh()
  store._path = tmppath()
  registry.setup({})
end

local function cleanup()
  if store._path then
    os.remove(store._path)
    os.remove(store._path .. ".bak")
    os.remove(store._path .. ".tmp")
  end
  store._path = nil
end

describe("project.registry", function()
  before_each(fresh)
  after_each(cleanup)

  it("register persists project", function()
    local p = registry.register({ path = "/tmp/foo" })
    assert.is_table(p)
    assert.is_string(p.id)
    assert.equals("/tmp/foo", p.root)
    assert.is_truthy(registry.exists(p.id))
  end)

  it("list returns all registered", function()
    registry.register({ path = "/tmp/a" })
    registry.register({ path = "/tmp/b" })
    local all = registry.list()
    assert.is_table(all)
    assert.is_true(#all >= 2)
  end)

  it("get returns project by id", function()
    local p = registry.register({ path = "/tmp/foo" })
    local got = registry.get(p.id)
    assert.is_table(got)
    assert.equals(p.id, got.id)
  end)

  it("unregister removes project", function()
    local p = registry.register({ path = "/tmp/foo" })
    assert.is_truthy(registry.unregister(p.id))
    assert.is_nil(registry.get(p.id))
  end)

  it("update changes name", function()
    local p = registry.register({ path = "/tmp/foo" })
    registry.update(p.id, { name = "NewName" })
    assert.equals("NewName", registry.get(p.id).name)
  end)

  it("register_presets skips duplicates", function()
    registry.register({ path = "/tmp/foo" })
    local before = #registry.list()
    registry.register_presets({ "/tmp/foo" })
    local after = #registry.list()
    assert.equals(before, after)
  end)

  it("find_by_root locates project", function()
    local p = registry.register({ path = "/tmp/foo" })
    local got = registry.find_by_root(p.root)
    assert.is_table(got)
    assert.equals(p.id, got.id)
  end)
end)
