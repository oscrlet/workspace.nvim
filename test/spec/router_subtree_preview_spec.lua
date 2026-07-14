-- project preview delegates to router's dir_peek (shared devicon + color
-- directory rendering), falling back to project_tree if router is absent.
describe("router_subtree.preview.project", function()
  local function load()
    package.loaded["workspace.router_subtree.preview"] = nil
    return require("workspace.router_subtree.preview")
  end

  it("delegates to router.preview.dir_peek with item.dir = root", function()
    local captured
    package.loaded["router.preview"] = { dir_peek = function(ctx) captured = ctx end }
    local pv = load()
    local ctx = { item = { root = "/home/me/proj" }, preview = {}, buf = 7 }
    pv.project(ctx)
    package.loaded["router.preview"] = nil
    assert.is_table(captured)
    assert.equals("/home/me/proj", captured.item.dir)
  end)

  it("renders (no root) when the item has neither root nor path", function()
    local got
    package.loaded["router.preview"] = { dir_peek = function() error("should not run") end }
    local pv = load()
    local ctx = { item = {}, preview = {
      reset = function() end,
      set_lines = function(_, lines) got = lines end,
    } }
    pv.project(ctx)
    package.loaded["router.preview"] = nil
    assert.same({ "(no root)" }, got)
  end)
end)

describe("tab preview expands each project via dirs_peek", function()
  local function load()
    package.loaded["workspace.router_subtree.preview"] = nil
    return require("workspace.router_subtree.preview")
  end

  it("delegates tab projects to dirs_peek as sections + markdown metadata header", function()
    local secs, opts
    package.loaded["router.preview"] = { dirs_peek = function(_, s, o) secs = s; opts = o end }
    package.loaded["workspace.project.registry"] = {
      get = function(id) return { id = id, name = id .. "!", root = "/r/" .. id } end,
    }
    local pv = load()
    pv.tab({ item = { tab = { project_ids = { "p1", "p2" }, active_project_id = "p1",
                              cwd = "/r/p1", label = "work" } }, preview = {}, buf = 9 })
    package.loaded["router.preview"] = nil
    package.loaded["workspace.project.registry"] = nil
    assert.is_table(secs)
    assert.equals(2, #secs)
    assert.equals("p1!", secs[1].label)
    assert.equals("/r/p1", secs[1].path)
    -- markdown metadata header + ft; projects as indented sub-items,
    -- active marked inline.
    assert.equals("markdown", opts.ft)
    assert.equals("# Tab: work", opts.header[1])
    assert.is_truthy(vim.tbl_contains(opts.header, "- **projects**:"))
    assert.is_truthy(vim.tbl_contains(opts.header, "  - **p1!** _(active)_"))
    assert.is_truthy(vim.tbl_contains(opts.header, "  - p2!"))
  end)
end)
