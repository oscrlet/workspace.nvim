-- Verifies the resession backend dispatches to the resession plugin via a
-- stub, and that available() honestly reports presence/shape.

local function with_stub(stub, fn)
  local prev_pre = package.preload["resession"]
  local prev_loaded = package.loaded["resession"]
  package.loaded["resession"] = nil
  package.preload["resession"] = function() return stub end
  -- Force fresh require of the backend so it re-binds to the new stub.
  package.loaded["workspace.snapshot.resession"] = nil
  local backend = require("workspace.snapshot.resession")
  local ok, err = pcall(fn, backend, stub)
  package.loaded["resession"] = prev_loaded
  package.preload["resession"] = prev_pre
  package.loaded["workspace.snapshot.resession"] = nil
  if not ok then error(err) end
end

describe("workspace.snapshot.resession", function()
  it("kind = 'resession'", function()
    local backend = require("workspace.snapshot.resession")
    assert.equals("resession", backend.kind)
  end)

  it("available() = false when plugin missing", function()
    package.loaded["resession"] = nil
    package.preload["resession"] = nil
    package.loaded["workspace.snapshot.resession"] = nil
    local backend = require("workspace.snapshot.resession")
    assert.is_false(backend.available())
  end)

  it("available() = false when API shape mismatched", function()
    with_stub({ save = "not a function" }, function(backend)
      assert.is_false(backend.available())
    end)
  end)

  it("available() = true when save+load are functions", function()
    with_stub({ save = function() end, load = function() end }, function(backend)
      assert.is_true(backend.available())
    end)
  end)

  it("capture() calls resession.save and returns blob with session_name", function()
    local calls = {}
    local stub = {
      save = function(name, opts) calls[#calls + 1] = { kind = "save", name = name, opts = opts } end,
      load = function(name, opts) calls[#calls + 1] = { kind = "load", name = name, opts = opts } end,
    }
    with_stub(stub, function(backend)
      local nr = vim.api.nvim_get_current_tabpage()
      local blob = backend.capture(nr)
      assert.is_table(blob)
      assert.equals("resession", blob.kind)
      assert.is_string(blob.session_name)
      -- Verify save was called with the same name.
      local save_call
      for _, c in ipairs(calls) do if c.kind == "save" then save_call = c end end
      assert.is_table(save_call)
      assert.equals(blob.session_name, save_call.name)
    end)
  end)

  it("restore() calls resession.load with stored session_name", function()
    local calls = {}
    local stub = {
      save = function() end,
      load = function(name, opts) calls[#calls + 1] = { name = name, opts = opts } end,
    }
    with_stub(stub, function(backend)
      backend.restore({ kind = "resession", session_name = "myname" }, 1)
      assert.equals(1, #calls)
      assert.equals("myname", calls[1].name)
    end)
  end)
end)
