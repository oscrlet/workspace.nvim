local M = {}

function M.fire(name, data)
  local ok, err = pcall(function()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "WorkspaceTab" .. name,
      data = data,
    })
  end)
  if not ok then
    require("workspace.util.log").error("Fire event failed: " .. tostring(err))
  end
end

return M
