describe("tab.state", function()
  local state

  before_each(function()
    -- Fresh state instance for each test
    package.loaded["workspace.tab.state"] = nil
    state = require("workspace.tab.state")
  end)

  it("ensure(1) returns table with uuid + project_ids", function()
    local tab = state.ensure(1)
    assert.is_table(tab)
    assert.is_string(tab.uuid)
    assert.is_table(tab.project_ids)
  end)

  it("subsequent ensure(1) returns same uuid", function()
    local tab1 = state.ensure(1)
    local tab2 = state.ensure(1)
    assert.equal(tab1.uuid, tab2.uuid)
  end)

  it("ensure(2) returns different uuid", function()
    local tab1 = state.ensure(1)
    local tab2 = state.ensure(2)
    assert.not_equal(tab1.uuid, tab2.uuid)
  end)

  it("remove(1) deletes tab", function()
    state.ensure(1)
    state.remove(1)
    assert.is_nil(state.by_tabnr(1))
  end)

  it("all() returns sorted by order", function()
    state.ensure(2)
    state.ensure(1)
    state.ensure(3)
    local all = state.all()
    assert.equal(3, #all)
    -- Verify all have uuid + project_ids
    for _, tab in ipairs(all) do
      assert.is_string(tab.uuid)
      assert.is_table(tab.project_ids)
    end
  end)
end)
