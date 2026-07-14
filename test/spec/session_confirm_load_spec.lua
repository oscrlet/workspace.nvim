--- test/spec/session_confirm_load_spec.lua
--- Coverage for session.confirm_before_load behavior.

local config = require("workspace.config")
local session_api = require("workspace.session.api")
local store = require("workspace.session.store")
local ss = require("workspace.session.state")

local function tmp_session_dir()
  local d = vim.fn.tempname() .. "_confirm_load"
  vim.fn.mkdir(d, "p")
  return d
end

local function write_minimal_session(name)
  local snap = {
    version = 1,
    tabs = {},
    active_tab_id = nil,
  }
  local ok, err = store.write(name, snap)
  assert.is_truthy(ok, "write failed: " .. tostring(err))
end

describe("session.confirm_before_load", function()
  local saved_select
  local select_calls

  before_each(function()
    select_calls = {}
    saved_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      select_calls[#select_calls + 1] = { items = items, opts = opts, on_choice = on_choice }
    end
    config._reset()
    store._dir = tmp_session_dir()
    ss.set_current(nil)
  end)

  after_each(function()
    vim.ui.select = saved_select
    if store._dir then
      vim.fn.delete(store._dir, "rf")
      store._dir = nil
    end
    ss.set_current(nil)
    config._reset()
  end)

  it("flag false → load proceeds without vim.ui.select", function()
    config.merge({ session = { confirm_before_load = false } })
    write_minimal_session("nopromp")
    local ok, err = session_api.load("nopromp")
    assert.is_true(ok, "load failed: " .. tostring(err))
    assert.equals(0, #select_calls, "select should not have been called")
    assert.equals("nopromp", ss.current())
  end)

  it("flag true → vim.ui.select invoked; Cancel does not change state", function()
    config.merge({ session = { confirm_before_load = true } })
    write_minimal_session("toprompt")
    session_api.load("toprompt")
    assert.equals(1, #select_calls)
    -- Cancel.
    select_calls[1].on_choice("Cancel")
    assert.is_nil(ss.current(), "current should remain nil after Cancel")
  end)

  it("flag true → vim.ui.select invoked; Load proceeds", function()
    config.merge({ session = { confirm_before_load = true } })
    write_minimal_session("loadprompt")
    session_api.load("loadprompt")
    assert.equals(1, #select_calls)
    select_calls[1].on_choice("Load")
    assert.equals("loadprompt", ss.current())
  end)

  it("force=true bypasses prompt", function()
    config.merge({ session = { confirm_before_load = true } })
    write_minimal_session("forced")
    local ok, err = session_api.load("forced", { force = true })
    assert.is_true(ok, "load failed: " .. tostring(err))
    assert.equals(0, #select_calls)
    assert.equals("forced", ss.current())
  end)
end)
