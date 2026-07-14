-- Verifies winlayout-based snapshot/restore preserves split structure
-- and global listed buffers (incl. hidden/badd-only).

local ws_snap   = require("workspace.workspace.snapshot")
local ws_state  = require("workspace.workspace.state")
local tab_state = require("workspace.tab.state")

local function tmpfile(content)
  local p = vim.fn.tempname()
  local f = io.open(p, "w"); f:write(content or "x\n"); f:close()
  -- Normalize via realpath so it matches nvim_buf_get_name (which resolves
  -- /var -> /private/var on macOS).
  return vim.uv.fs_realpath(p) or p
end

local function listed_paths()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted then
      local n = vim.api.nvim_buf_get_name(b)
      if n ~= "" then out[#out + 1] = n end
    end
  end
  return out
end

local function contains(list, target)
  for _, v in ipairs(list) do if v == target then return true end end
  return false
end

describe("workspace snapshot winlayout (vsplit + hidden buffer roundtrip)", function()
  before_each(function()
    pcall(vim.cmd, "silent! tabonly")
    pcall(vim.cmd, "silent! enew")
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    tab_state._reset()
    ws_state._reset()
  end)

  it("captures vsplit and restores both windows + hidden listed buffer", function()
    local f1 = tmpfile("alpha\n")
    local f2 = tmpfile("beta\n")
    local f3 = tmpfile("gamma\n") -- never window-shown, only badd

    vim.cmd("edit " .. vim.fn.fnameescape(f1))
    vim.cmd("vsplit " .. vim.fn.fnameescape(f2))
    vim.cmd("badd " .. vim.fn.fnameescape(f3))

    tab_state.ensure(vim.api.nvim_get_current_tabpage())

    local snap = ws_snap.snapshot()
    assert.equals(1, #snap.tabs)
    local entry = snap.tabs[1]
    local decoded = vim.json.decode(entry.nvim_state)
    assert.equals("winlayout", decoded.kind)
    assert.equals("row", decoded.layout[1]) -- vsplit becomes "row"
    assert.is_true(contains(snap.listed_buffers, f3),
      "hidden buffer should be in workspace listed_buffers")

    -- Wipe and restore.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    tab_state._reset()
    ws_state._reset()

    ws_snap.restore(snap)

    local wins = vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
    assert.equals(2, #wins, "expected 2 windows after vsplit restore")

    local paths = listed_paths()
    assert.is_true(contains(paths, f1), "f1 should be listed")
    assert.is_true(contains(paths, f2), "f2 should be listed")
    assert.is_true(contains(paths, f3), "f3 (hidden) should be restored as listed")

    for _, p in ipairs({ f1, f2, f3 }) do os.remove(p) end
  end)
end)
