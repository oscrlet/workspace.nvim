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
    if name ~= "" then
      local stat = vim.uv and vim.uv.fs_stat and vim.uv.fs_stat(name)
        or vim.loop.fs_stat(name)
      if stat then
        local cursor = vim.api.nvim_win_get_cursor(win)
        local topline = vim.fn.line("w0", win)
        wins_meta[tostring(win)] = {
          file    = name,
          cursor  = cursor,
          topline = topline,
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

  -- Legacy "files" form: just :edit / :badd each file.
  if decoded.kind == "files" then
    local first = true
    for _, f in ipairs(decoded.files or {}) do
      if first then
        pcall(vim.cmd, "edit " .. vim.fn.fnameescape(f))
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
        pcall(vim.cmd, "edit " .. vim.fn.fnameescape(meta.file))
        if meta.cursor then
          pcall(vim.api.nvim_win_set_cursor, 0, meta.cursor)
        end
        if meta.topline then
          pcall(vim.fn.winrestview, { topline = meta.topline })
        end
      end
    elseif node[1] == "row" or node[1] == "col" then
      local children = node[2] or {}
      local split_cmd = node[1] == "row" and "vsplit" or "split"
      if #children > 0 then build(children[1]) end
      for i = 2, #children do
        pcall(vim.cmd, split_cmd)
        build(children[i])
      end
    end
  end
  build(decoded.layout)
end

return M
