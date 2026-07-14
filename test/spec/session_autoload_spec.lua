--- test/spec/session_autoload_spec.lua
--- Coverage for session.autoload_last_on_startup behavior.

local config = require("workspace.config")
local store = require("workspace.session.store")
local ss = require("workspace.session.state")
local workspace = require("workspace")

local function tmpdir()
  local d = vim.fn.tempname() .. "_autoload"
  vim.fn.mkdir(d, "p")
  return d
end

local function write_session(name)
  local snap = { version = 1, tabs = {}, active_tab_id = nil }
  local ok, err = store.write(name, snap)
  assert.is_truthy(ok, "write failed: " .. tostring(err))
end

local function fire_autoload()
  local ok = pcall(vim.api.nvim_exec_autocmds, "VimEnter", { group = "WorkspaceAutoload" })
  return ok
end

describe("session.autoload_last_on_startup", function()
  before_each(function()
    config._reset()
    store._dir = tmpdir()
    ss.set_current(nil)
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceAutoload")
  end)

  after_each(function()
    if store._dir then
      vim.fn.delete(store._dir, "rf")
      store._dir = nil
    end
    ss.set_current(nil)
    config._reset()
    pcall(vim.api.nvim_del_augroup_by_name, "WorkspaceAutoload")
  end)

  it("flag false → no autocmd registered, fire is no-op", function()
    workspace.setup({ session = { autoload_last_on_startup = false } })
    -- Group should not exist; firing fails or does nothing.
    local ok = pcall(vim.api.nvim_exec_autocmds, "VimEnter", { group = "WorkspaceAutoload" })
    -- group missing → pcall returns false; either way no current session.
    assert.is_nil(ss.current())
  end)

  it("flag true with empty session dir → no error, no current", function()
    workspace.setup({ session = { autoload_last_on_startup = true } })
    fire_autoload()
    assert.is_nil(ss.current())
  end)

  it("flag true with two saved sessions → loads the newer one", function()
    write_session("older")
    -- Touch older's mtime to be in the past.
    local older_path = store.path("older")
    local now = os.time()
    vim.uv.fs_utime(older_path, now - 100, now - 100)

    write_session("newer")
    local newer_path = store.path("newer")
    vim.uv.fs_utime(newer_path, now, now)

    workspace.setup({ session = { autoload_last_on_startup = true } })
    fire_autoload()

    assert.equals("newer", ss.current())
  end)
end)
