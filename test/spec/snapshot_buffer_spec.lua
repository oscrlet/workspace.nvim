--- test/spec/snapshot_buffer_spec.lua
--- Tests for nvim_state fallback (file-list) capture/restore when
--- resession.nvim is not installed.

local tab_state = require("workspace.tab.state")
local ws_snap   = require("workspace.workspace.snapshot")
local ws_state  = require("workspace.workspace.state")

local function tmpfile(content)
  local p = vim.fn.tempname() .. ".txt"
  local f = io.open(p, "w")
  assert(f, "could not open tmpfile " .. p)
  f:write(content or "hello\n")
  f:close()
  return p
end

local function buffer_paths()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      local n = vim.api.nvim_buf_get_name(b)
      if n ~= "" then out[#out + 1] = n end
    end
  end
  return out
end

local function resolve(p)
  if not p or p == "" then return p end
  return vim.loop.fs_realpath(p) or p
end

local function contains(list, val)
  local rv = resolve(val)
  for _, v in ipairs(list) do
    if v == val or resolve(v) == rv then return true end
  end
  return false
end

describe("workspace snapshot nvim_state fallback (no resession)", function()
  before_each(function()
    tab_state._reset()
    ws_state._reset()
  end)

  after_each(function()
    tab_state._reset()
    ws_state._reset()
  end)

  it("captures file-backed buffers as kind=winlayout JSON blob", function()
    local f = tmpfile("snapshot-buffer-spec\n")
    -- Edit the file in the current tab so it's part of tabpagebuflist.
    vim.cmd("edit " .. vim.fn.fnameescape(f))

    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)

    local snap = ws_snap.snapshot()
    assert.equals(1, #snap.tabs)

    local nvim_state = snap.tabs[1].nvim_state
    assert.is_string(nvim_state)
    assert.is_true(nvim_state ~= "", "nvim_state should be non-empty")

    local ok, decoded = pcall(vim.json.decode, nvim_state)
    assert.is_true(ok, "nvim_state should decode as JSON")
    assert.is_table(decoded)
    assert.equals("winlayout", decoded.kind)
    assert.is_table(decoded.layout)
    assert.is_table(decoded.wins)
    assert.is_table(decoded.files)
    assert.is_true(#decoded.files >= 1, "expected at least 1 file path")
    assert.is_true(contains(decoded.files, f), "expected " .. f .. " in files list")

    os.remove(f)
  end)

  it("restore loads file as buffer in active tabpage", function()
    local f = tmpfile("restore-spec\n")
    vim.cmd("edit " .. vim.fn.fnameescape(f))

    local nr = vim.api.nvim_get_current_tabpage()
    tab_state.ensure(nr)

    local snap = ws_snap.snapshot()

    -- Wipe all buffers (best effort) so we can verify restore loads them again.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end

    tab_state._reset()
    ws_state._reset()

    ws_snap.restore(snap)

    -- File should now be loaded as a buffer.
    local paths = buffer_paths()
    assert.is_true(contains(paths, f),
      "expected " .. f .. " to be present after restore; got: " .. vim.inspect(paths))

    os.remove(f)
  end)

  it("tab with no file-backed buffers yields empty files list and restore is a no-op", function()
    -- Move to a fresh tab with only an unnamed buffer.
    vim.cmd("tabnew")
    local nr = vim.api.nvim_get_current_tabpage()
    tab_state._reset()
    tab_state.ensure(nr)

    -- Wipe any name from the current buffer just in case.
    local cur = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_get_name(cur) ~= "" then
      vim.cmd("enew")
    end

    local snap = ws_snap.snapshot()
    assert.is_true(#snap.tabs >= 1)

    -- Find the entry for this tabnr (or take the only one).
    local entry = snap.tabs[1]
    assert.is_string(entry.nvim_state)
    local ok, decoded = pcall(vim.json.decode, entry.nvim_state)
    assert.is_true(ok)
    assert.equals("winlayout", decoded.kind)
    assert.equals(0, #(decoded.files or {}))

    -- Restore must not raise.
    tab_state._reset()
    ws_state._reset()
    local restore_ok, err = pcall(ws_snap.restore, snap)
    assert.is_true(restore_ok, "restore should not error: " .. tostring(err))
  end)
end)
