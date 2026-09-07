--- workspace/snapshot/winlayout.lua
--- Winlayout backend: pure-lua per-tab capture of the nested split tree
--- plus per-window {file, cursor, topline}. Zero external dependencies.
local M = {}

M.kind = "winlayout"

function M.available()
  return true
end

--- Capture a single tabpage's window layout into a blob.
---@param tabnr integer  tabpage handle
---@return table|nil decoded blob, or nil if the tabpage no longer exists
function M.capture(tabnr)
  local ok_idx, idx = pcall(vim.api.nvim_tabpage_get_number, tabnr)
  if not ok_idx or not idx then
    return nil
  end
  local layout = vim.fn.winlayout(idx)
  local wins_meta = {}
  local files = {}
  local seen = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabnr)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.api.nvim_win_get_config(win).relative == "" then
      local stat = vim.uv and vim.uv.fs_stat and vim.uv.fs_stat(name)
        or vim.loop.fs_stat(name)
      if stat then
        local cursor = vim.api.nvim_win_get_cursor(win)
        local topline = vim.fn.line("w0", win)
        wins_meta[tostring(win)] = {
          file    = name,
          cursor  = cursor,
          topline = topline,
          view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
          width = vim.api.nvim_win_get_width(win),
          height = vim.api.nvim_win_get_height(win),
        }
        if not seen[name] then
          seen[name] = true
          files[#files + 1] = name
        end
      end
    end
  end
  return {
    kind   = "winlayout",
    layout = layout,
    wins   = wins_meta,
    files  = files,  -- back-compat: older readers can still display file list
    current_win = vim.api.nvim_tabpage_get_win(tabnr),
  }
end

--- Restore one tabpage's layout from a decoded blob.
--- Caller must have already focused the target tabpage.
---@param decoded table  blob returned by capture()
---@param tabnr integer  tabpage handle (already focused)
function M.restore(decoded, tabnr)
  if type(decoded) ~= "table" then return end
  -- Caller has already focused the target tabpage; collapse to one window.
  pcall(vim.cmd, "silent only")
  local wins = decoded.wins or {}
  local restored = {}

  -- Legacy "files" form: just :edit / :badd each file.
  if decoded.kind == "files" then
    local first = true
    for _, f in ipairs(decoded.files or {}) do
      if first then
        pcall(vim.cmd, "silent edit " .. vim.fn.fnameescape(f))
        first = false
      else
        pcall(vim.cmd, "badd " .. vim.fn.fnameescape(f))
      end
    end
    return
  end

  local function build(node)
    if type(node) ~= "table" then return end
    if node[1] == "leaf" then
      local meta = wins[tostring(node[2])]
      if meta and meta.file then
        restored[tostring(node[2])] = vim.api.nvim_get_current_win()
        pcall(vim.cmd, "silent edit " .. vim.fn.fnameescape(meta.file))
        if meta.cursor then
          pcall(vim.api.nvim_win_set_cursor, 0, meta.cursor)
        end
        if meta.topline then
          pcall(vim.fn.winrestview, { topline = meta.topline })
        end
      end
    elseif node[1] == "row" or node[1] == "col" then
      local children = node[2] or {}
      local split_cmd = node[1] == "row" and "rightbelow vsplit" or "rightbelow split"
      -- Allocate sibling roots before recursively subdividing any child.
      local roots = { vim.api.nvim_get_current_win() }
      for i = 2, #children do
        vim.cmd('silent ' .. split_cmd)
        roots[i] = vim.api.nvim_get_current_win()
      end
      for i, child in ipairs(children) do
        vim.api.nvim_set_current_win(roots[i])
        build(child)
      end
    end
  end
  build(decoded.layout)
  for old, win in pairs(restored) do
    local meta = wins[old]
    if meta.width then pcall(vim.api.nvim_win_set_width, win, meta.width) end
    if meta.height then pcall(vim.api.nvim_win_set_height, win, meta.height) end
  end
  for old, win in pairs(restored) do
    local meta = wins[old]
    if meta.view then
      vim.api.nvim_win_call(win, function() vim.fn.winrestview(meta.view) end)
    end
  end
  local focused = restored[tostring(decoded.current_win)]
  if focused then vim.api.nvim_set_current_win(focused) end
end

return M
