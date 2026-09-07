-- Buffer membership belongs to Neovim. Only session ordering lives here.
local M = {}
local rank = {}
function M.restore_order(files)
  rank = {}
  for i, file in ipairs(files or {}) do
    local buf = vim.fn.bufnr(file)
    if buf >= 0 then rank[buf] = i end
  end
end
function M.list()
  local buffers = vim.tbl_filter(function(buf)
    return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted
  end, vim.api.nvim_list_bufs())
  table.sort(buffers, function(a, b)
    local ra, rb = rank[a] or math.huge, rank[b] or math.huge
    return ra == rb and a < b or ra < rb
  end)
  return buffers
end
return M
