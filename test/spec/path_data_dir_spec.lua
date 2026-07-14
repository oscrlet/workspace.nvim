--- test/spec/path_data_dir_spec.lua
--- Verify util.path.data_dir() honors cfg.data_dir override (F8).

describe("util.path.data_dir", function()
  local path_util
  local config

  before_each(function()
    package.loaded["workspace.config"] = nil
    package.loaded["workspace.util.path"] = nil
    config = require("workspace.config")
    path_util = require("workspace.util.path")
    config._reset()
  end)

  after_each(function()
    if config and config._reset then
      config._reset()
    end
  end)

  it("returns stdpath('data')/workspace by default", function()
    local default = vim.fn.stdpath("data") .. "/workspace"
    assert.equal(default, path_util.data_dir())
  end)

  it("honors cfg.data_dir override set via config.merge", function()
    config.merge({ data_dir = "/tmp/foo-workspace-override" })
    assert.equal("/tmp/foo-workspace-override", path_util.data_dir())
  end)

  it("reverts to default after config._reset()", function()
    config.merge({ data_dir = "/tmp/foo-workspace-override" })
    assert.equal("/tmp/foo-workspace-override", path_util.data_dir())

    config._reset()

    local default = vim.fn.stdpath("data") .. "/workspace"
    assert.equal(default, path_util.data_dir())
  end)

  it("falls back gracefully when config module fails to load", function()
    -- Simulate early-init: blow away the cached config module and replace
    -- the loader with one that errors. data_dir() should not propagate.
    package.loaded["workspace.config"] = nil
    package.preload["workspace.config"] = function()
      error("simulated early-init failure")
    end

    -- Re-require path_util fresh so its internal pcall hits the broken loader.
    package.loaded["workspace.util.path"] = nil
    local fresh_path = require("workspace.util.path")

    local got = fresh_path.data_dir()
    assert.is_string(got)
    assert.is_true(#got > 0)

    -- Cleanup: restore real config loader.
    package.preload["workspace.config"] = nil
    package.loaded["workspace.config"] = nil
    package.loaded["workspace.util.path"] = nil
  end)
end)
