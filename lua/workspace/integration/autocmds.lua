local M = {}

-- Mutation events that trigger debounced autosave.
local MUTATION_EVENTS = {
  "WorkspaceTabProjectAdded",
  "WorkspaceTabProjectRemoved",
  "WorkspaceTabActiveChanged",
  "WorkspaceTabCwdChanged",
  "WorkspaceTabRenamed",
  "WorkspaceTabReordered",
  "WorkspaceProjectRegistered",
  "WorkspaceProjectUpdated",
  "WorkspaceProjectUnregistered",
}

function M.setup()
  local cfg_root = require("workspace.config").get()
  local sess_cfg = cfg_root.session or {}
  local debounce_ms = sess_cfg.autosave_debounce_ms or 500
  local autosave_enabled = sess_cfg.autosave ~= false

  local timer = nil

  local function flush()
    if timer then
      pcall(vim.fn.timer_stop, timer)
      timer = nil
    end
  end

  local function do_save()
    local session = require("workspace.session")
    local cur = session.current()
    if cur ~= nil then
      pcall(session.save, cur)
    end
  end

  local function debounced_save()
    -- Re-read config flag so toggling at runtime works.
    local live_cfg = (require("workspace.config").get().session or {})
    if live_cfg.autosave == false then return end
    if require("workspace.session").current() == nil then return end
    flush()
    timer = vim.fn.timer_start(debounce_ms, function()
      timer = nil
      do_save()
    end)
  end

  local group = vim.api.nvim_create_augroup("WorkspaceAutocmds", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      flush()
      do_save()
    end,
  })

  -- Track raw `:tcd` (and any tabpage/global cwd change) into tab.cwd
  -- so snapshots round-trip the user's actual current cwd, not just the
  -- initial one captured at tab creation. `:lcd` (window scope) is
  -- intentionally ignored — it's a window-local override that should
  -- not pollute tab state.
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      local scope = vim.v.event.scope
      if scope ~= "tabpage" and scope ~= "global" then return end
      local tab_state = require("workspace.tab.state")
      local nr = vim.api.nvim_get_current_tabpage()
      local tab = tab_state.by_tabnr(nr)
      if not tab then return end
      local new = vim.v.event.cwd or vim.fn.getcwd()
      if tab.cwd == new then return end       -- idempotent: no self-loop
      tab.cwd = new
      pcall(function()
        require("workspace.tab.events").fire("CwdChanged", { tabnr = nr, cwd = new })
      end)
    end,
  })

  if autosave_enabled then
    for _, ev in ipairs(MUTATION_EVENTS) do
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = ev,
        callback = debounced_save,
      })
    end
  end

  -- Setup LSP integration if config is available
  pcall(function()
    local config = require("workspace.config").get()
    if config.lsp then
      require("workspace.integration.lsp").setup(config.lsp)
    end
  end)

  -- Expose for tests.
  M._debounced_save = debounced_save
  M._flush = flush
end

function M.save_on_exit()
  -- Direct hook for plugin/workspace.lua to call if needed
  local session = require("workspace.session")
  local current = session.current()
  if current ~= nil then
    pcall(session.save)
  end
end

return M
