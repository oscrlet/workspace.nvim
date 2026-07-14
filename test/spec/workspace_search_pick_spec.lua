local nodes = require("workspace.router_subtree.nodes.search")

describe("workspace_search_pick.on_confirm", function()
  local pick = nodes.workspace_search_pick

  it("with a preset search_kind, returns the matching router leaf + sets ctx.search.dirs", function()
    local ctx = { workspace = { search_kind = "grep" } }
    local next_id = pick.on_confirm({ { root = "/a" }, { root = "/b" } }, ctx)
    assert.equals("search_grep", next_id)
    assert.same({ "/a", "/b" }, ctx.search.dirs)
  end)

  it("maps find/symbol kinds to their leaves", function()
    local c1 = { workspace = { search_kind = "find" } }
    assert.equals("search_find", pick.on_confirm({ { root = "/x" } }, c1))
    local c2 = { workspace = { search_kind = "symbol" } }
    assert.equals("search_symbol", pick.on_confirm({ { root = "/y" } }, c2))
  end)

  it("without a preset kind, falls back to the kind menu (unchanged)", function()
    local ctx = { workspace = {} }
    local next_id = pick.on_confirm({ { root = "/a" } }, ctx)
    assert.equals("workspace_search_kind", next_id)
    assert.same({ "/a" }, ctx.workspace.search_roots)
  end)

  it("normalizes a single (non-list) item", function()
    local ctx = { workspace = { search_kind = "grep" } }
    pick.on_confirm({ id = "p", root = "/solo" }, ctx)
    assert.same({ "/solo" }, ctx.search.dirs)
  end)
end)
