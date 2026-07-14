--- workspace/integration/tabufline.lua
--- NvChad tabufline integration glue.
---
--- NvChad's `nvchad.tabufline.modules.tabs()` (see ui/lua/nvchad/tabufline/
--- modules.lua) renders only numeric `" N "` labels — there is no extension
--- point to inject a workspace label without monkey-patching the entire
--- function. Rather than ship a brittle override, this module:
---   1. pcalls require("nvchad.tabufline.modules"); on absence, no-ops.
---   2. Registers a `User WorkspaceTabRenamed` autocmd that calls
---      `:redrawtabline` so any external consumer of `ui/tabline.tab_name`
---      observes the new label immediately.
---   3. Sets `_M.nvchad_present` so callers can probe whether a deeper
---      override pathway is realistic on the host.
---
--- Hosts that want workspace labels in NvChad's tabline should override
--- `nvchad.tabufline.modules.tabs` themselves and call
--- `require("workspace.ui.tabline").tab_name(tabnr)` for each tab — that
--- API is stable.
local M = {}

M._nvchad_present = false

--- Configure tabufline integration. Safe to call when NvChad is absent.
function M.setup()
  local ok, _ = pcall(require, "nvchad.tabufline.modules")
  M._nvchad_present = ok

  -- Always register the redraw autocmd; it is harmless without NvChad and
  -- still useful for builtin tablines that consult tab_name().
  local group = vim.api.nvim_create_augroup("WorkspaceTabuflineGlue", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "WorkspaceTabRenamed",
    callback = function()
      pcall(vim.cmd, "redrawtabline")
    end,
  })
end

return M
