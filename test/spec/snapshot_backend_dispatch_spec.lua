-- Verifies the snapshot dispatcher resolves the right backend for each
-- of the four config values.

local function fresh()
  package.loaded["workspace.snapshot"] = nil
  package.loaded["workspace.snapshot.winlayout"] = nil
  package.loaded["workspace.snapshot.mksession"] = nil
  package.loaded["workspace.snapshot.resession"] = nil
  return require("workspace.snapshot")
end

local function with_resession_stub(stub, fn)
  local prev_pre = package.preload["resession"]
  local prev_loaded = package.loaded["resession"]
  package.loaded["resession"] = nil
  package.preload["resession"] = function() return stub end
  local ok, err = pcall(fn)
  package.loaded["resession"] = prev_loaded
  package.preload["resession"] = prev_pre
  if not ok then error(err) end
end

local function without_resession(fn)
  local prev_pre = package.preload["resession"]
  local prev_loaded = package.loaded["resession"]
  package.preload["resession"] = nil
  package.loaded["resession"] = nil
  local ok, err = pcall(fn)
  package.loaded["resession"] = prev_loaded
  package.preload["resession"] = prev_pre
  if not ok then error(err) end
end

describe("workspace.snapshot dispatcher", function()
  it("'resession-auto' with no resession plugin → winlayout", function()
    without_resession(function()
      local d = fresh()
      assert.equals("winlayout", d.resolve("resession-auto").kind)
    end)
  end)

  it("'resession-auto' with stub resession → resession", function()
    with_resession_stub({ save = function() end, load = function() end }, function()
      local d = fresh()
      assert.equals("resession", d.resolve("resession-auto").kind)
    end)
  end)

  it("'mksession' → mksession", function()
    local d = fresh()
    assert.equals("mksession", d.resolve("mksession").kind)
  end)

  it("'winlayout' (explicit) → winlayout", function()
    local d = fresh()
    assert.equals("winlayout", d.resolve("winlayout").kind)
  end)

  it("restore dispatches on decoded.kind", function()
    local d = fresh()
    -- Stub backends to record which one's restore was called.
    local called = {}
    local function spy(kind)
      return {
        kind = kind,
        available = function() return true end,
        capture = function() end,
        restore = function() called[#called + 1] = kind end,
      }
    end
    package.loaded["workspace.snapshot.winlayout"] = spy("winlayout")
    package.loaded["workspace.snapshot.mksession"] = spy("mksession")
    package.loaded["workspace.snapshot.resession"] = spy("resession")

    d = fresh() -- re-require so it picks up the spied modules
    -- Re-inject after fresh() (which clears package.loaded for the backends).
    package.loaded["workspace.snapshot.winlayout"] = spy("winlayout")
    package.loaded["workspace.snapshot.mksession"] = spy("mksession")
    package.loaded["workspace.snapshot.resession"] = spy("resession")

    d.restore({ kind = "mksession", script = "" }, 1)
    d.restore({ kind = "resession", session_name = "x" }, 1)
    d.restore({ kind = "winlayout", layout = { "leaf", 1 } }, 1)
    -- Legacy "files" should route to winlayout.
    d.restore({ kind = "files", files = {} }, 1)
    -- Missing kind defaults to winlayout.
    d.restore({}, 1)

    assert.same({ "mksession", "resession", "winlayout", "winlayout", "winlayout" }, called)
  end)

  it("capture honors cfg.session.snapshot_backend = winlayout", function()
    local d = fresh()
    -- Use a real fresh tabpage; just check the produced JSON has kind=winlayout.
    local nr = vim.api.nvim_get_current_tabpage()
    local s = d.capture(nr, { session = { snapshot_backend = "winlayout" } })
    assert.is_string(s)
    if s ~= "" then
      local ok, decoded = pcall(vim.json.decode, s)
      assert.is_true(ok)
      assert.equals("winlayout", decoded.kind)
    end
  end)
end)
