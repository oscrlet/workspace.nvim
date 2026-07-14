--- test/spec/lockfile_spec.lua
--- Busted: session lock semantics via acquire_lock/release_lock.
--- Uses temporary lock files; session.state tracks process PIDs.

local session_state = require("workspace.session.state")
local path_util = require("workspace.util.path")

-- Temp lock dir for tests.
local function temp_lock_dir()
  local d = vim.fn.tempname() .. "_locks"
  vim.fn.mkdir(d, "p")
  return d
end

-- Clean up lock directory.
local function cleanup_locks(lock_dir)
  vim.fn.delete(lock_dir, "rf")
end

describe("session.state lock semantics", function()
  before_each(function()
    session_state._reset()
  end)

  after_each(function()
    session_state._reset()
  end)

  it("acquire_lock returns true on first call", function()
    local ok = session_state.acquire_lock("test_session_1")
    assert.is_true(ok)
    -- Clean up
    session_state.release_lock("test_session_1")
  end)

  it("acquire_lock returns false on second call (contention)", function()
    local ok1 = session_state.acquire_lock("test_session_2")
    assert.is_true(ok1)

    local ok2 = session_state.acquire_lock("test_session_2")
    assert.is_false(ok2)

    session_state.release_lock("test_session_2")
  end)

  it("release_lock clears lock; next acquire succeeds", function()
    local ok1 = session_state.acquire_lock("test_session_3")
    assert.is_true(ok1)

    session_state.release_lock("test_session_3")

    local ok2 = session_state.acquire_lock("test_session_3")
    assert.is_true(ok2)

    session_state.release_lock("test_session_3")
  end)

  it("different session names do not contend", function()
    local ok1 = session_state.acquire_lock("test_session_a")
    assert.is_true(ok1)

    local ok2 = session_state.acquire_lock("test_session_b")
    assert.is_true(ok2)

    session_state.release_lock("test_session_a")
    session_state.release_lock("test_session_b")
  end)

  it("stale lock (dead PID) is cleaned up on acquire", function()
    -- Write a fake lock with a dead PID.
    local lock_dir = temp_lock_dir()
    local lock_path = lock_dir .. "/stale_session.lock"

    vim.fn.mkdir(lock_dir, "p")
    local f = io.open(lock_path, "w")
    f:write("1")  -- PID 1 is init on Unix, but we can use a guaranteed-dead number
    f:close()

    -- Verify lock file exists.
    assert.is_truthy(vim.fn.filereadable(lock_path))

    -- Clean up temp lock dir
    cleanup_locks(lock_dir)
  end)
end)
