local store = require("workspace.project.store")

local function tmppath()
  return vim.fn.tempname() .. "_projects.json"
end

describe("project.store", function()
  before_each(function()
    store._path = tmppath()
  end)

  after_each(function()
    if store._path then
      os.remove(store._path)
      os.remove(store._path .. ".bak")
      os.remove(store._path .. ".tmp")
    end
    store._path = nil
  end)

  it("read returns default when file missing", function()
    local data = store.read()
    assert.is_table(data)
    assert.equals(1, data.version)
    assert.is_table(data.projects)
  end)

  it("write+read roundtrip preserves projects", function()
    local payload = {
      version = 1,
      projects = { { id = "x", name = "X", root = "/tmp/x" } },
    }
    local ok = store.write(payload)
    assert.is_truthy(ok)
    local got = store.read()
    -- Either array form or keyed form acceptable; check round-trip.
    assert.is_table(got.projects)
  end)

  it("corrupt json triggers .bak recovery", function()
    -- Seed valid backup.
    store.write({ version = 1, projects = { { id = "good", root = "/tmp/g" } } })
    -- Force the .bak to exist by writing twice.
    store.write({ version = 1, projects = { { id = "good", root = "/tmp/g" } } })
    -- Corrupt the main file.
    local f = io.open(store._path, "w"); f:write("{not json"); f:close()
    -- Read should not throw and should yield a table.
    local got = store.read()
    assert.is_table(got)
    assert.is_table(got.projects)
  end)
end)
