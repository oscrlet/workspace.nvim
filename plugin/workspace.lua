if vim.g.loaded_workspace then return end
vim.g.loaded_workspace = true

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("WorkspaceExit", { clear = true }),
  callback = function()
    local ok, ws = pcall(require, "workspace")
    if ok and ws.save_on_exit then pcall(ws.save_on_exit) end
  end,
})
