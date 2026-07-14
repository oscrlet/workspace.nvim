--- workspace/snapshot/mksession.lua
--- Per-tab snapshot via :mksession + sanitization. Captures buffer/window
--- options that the pure-lua winlayout backend can't see (folds, resize, etc.)
--- by writing a minimal Vim session script for the focused tab and stripping
--- the cross-tab control commands so it's safe to source on a single tab.
local M = {}

M.kind = "mksession"

function M.available()
  return true
end

-- Lines we strip from the mksession output before storing it. These are
-- safe-to-drop because either:
--   * they reference all-tabs operations ("silent only", "silent tabonly")
--     which would damage other tabs when restored,
--   * they navigate between tabs ("tabnew", "tabnext", ...) which doesn't
--     belong inside a single-tab restore script.
local function should_drop(line)
  if line == "silent only" then return true end
  if line == "silent tabonly" then return true end
  if line == "silent tabonly!" then return true end
  if line == "tabnew" then return true end
  if line:match("^tabnext") then return true end
  if line:match("^tabprevious") then return true end
  if line:match("^tabfirst") then return true end
  if line:match("^tablast") then return true end
  return false
end

local function sanitize(script)
  local out = {}
  for line in script:gmatch("([^\n]*)\n?") do
    if line ~= "" or #out > 0 then
      if not should_drop(line) then
        out[#out + 1] = line
      end
    end
  end
  -- Strip trailing empty lines.
  while #out > 0 and out[#out] == "" do
    out[#out] = nil
  end
  return table.concat(out, "\n")
end

--- Capture one tabpage's state via :mksession.
---@param tabnr integer
---@return table|nil blob with kind="mksession" and a sanitized `script` string
function M.capture(tabnr)
  if not pcall(vim.api.nvim_set_current_tabpage, tabnr) then
    return nil
  end

  local prev_so = vim.o.sessionoptions
  vim.o.sessionoptions = "buffers,curdir,folds,help,winsize,resize"

  local tmp = vim.fn.tempname() .. ".vim"
  local ok_mks = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(tmp))

  vim.o.sessionoptions = prev_so

  if not ok_mks then
    pcall(vim.fn.delete, tmp)
    return nil
  end

  local lines = {}
  do
    local fh = io.open(tmp, "r")
    if fh then
      for line in fh:lines() do lines[#lines + 1] = line end
      fh:close()
    end
  end
  pcall(vim.fn.delete, tmp)

  local raw = table.concat(lines, "\n")
  local script = sanitize(raw)

  return {
    kind   = "mksession",
    script = script,
  }
end

--- Restore one tabpage from a mksession blob. Caller has focused the
--- target tabpage already.
---@param decoded table
---@param tabnr integer
function M.restore(decoded, tabnr)
  if type(decoded) ~= "table" or type(decoded.script) ~= "string" then return end
  pcall(vim.cmd, "silent only")

  local tmp = vim.fn.tempname() .. ".vim"
  local fh = io.open(tmp, "w")
  if not fh then return end
  fh:write(decoded.script)
  fh:close()

  pcall(vim.cmd, "silent! source " .. vim.fn.fnameescape(tmp))
  pcall(vim.fn.delete, tmp)
end

-- Exported for tests.
M._sanitize = sanitize

return M
