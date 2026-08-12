describe("workspace.scope", function()
  before_each(function()
    package.loaded["workspace.scope"] = nil
    package.loaded["workspace.tab"] = nil
    package.loaded["workspace.session"] = nil
    package.loaded["workspace.project"] = nil
  end)

  it("returns unique valid roots for the requested tab", function()
    local requested_tab
    package.loaded["workspace.tab"] = {
      projects = function(tabnr)
        requested_tab = tabnr
        return {
          { id = "api", root = "/work/api" },
          { id = "missing-root" },
          { id = "web", root = "/work/web" },
          { id = "api-mirror", root = "/work/api" },
        }
      end,
    }

    local roots = require("workspace.scope").tab_roots(7)

    assert.equals(7, requested_tab)
    assert.same({ "/work/api", "/work/web" }, roots)
  end)

  it("returns unique roots for projects in the current session", function()
    package.loaded["workspace.session"] = {
      projects = function()
        return { "api", "missing", "web", "api-copy" }
      end,
    }
    local projects = {
      api = { id = "api", root = "/work/api" },
      web = { id = "web", root = "/work/web" },
      ["api-copy"] = { id = "api-copy", root = "/work/api" },
    }
    package.loaded["workspace.project"] = {
      get = function(id) return projects[id] end,
    }

    local roots = require("workspace.scope").session_roots()

    assert.same({ "/work/api", "/work/web" }, roots)
  end)

  it("returns roots for explicitly selected project ids", function()
    local projects = {
      api = { id = "api", root = "/work/api" },
      web = { id = "web", root = "/work/web" },
      mirror = { id = "mirror", root = "/work/api" },
    }
    package.loaded["workspace.project"] = {
      get = function(id) return projects[id] end,
    }

    local roots = require("workspace.scope").project_roots({
      "web", "missing", "api", "mirror",
    })

    assert.same({ "/work/web", "/work/api" }, roots)
  end)

  it("returns all registered project roots when ids are omitted", function()
    package.loaded["workspace.project"] = {
      list = function()
        return {
          { id = "web", root = "/work/web" },
          { id = "api", root = "/work/api" },
          { id = "mirror", root = "/work/web" },
          { id = "virtual" },
        }
      end,
    }

    local roots = require("workspace.scope").project_roots()

    assert.same({ "/work/web", "/work/api" }, roots)
  end)
end)
