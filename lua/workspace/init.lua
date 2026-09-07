local M = {}

M.config = nil

--- Listed Neovim buffers in session order; newly opened buffers follow them.
function M.buffers()
  return require('workspace.buffers').list()
end

function M.setup(opts)
  local config = require("workspace.config")
  local project = require("workspace.project")
  local commands = require("workspace.commands")

  M.config = config.merge(opts or {})
  project.setup(M.config)
  commands.setup_project_commands()
  commands.setup_session_commands()
  commands.setup_workspace_commands()
  commands.setup_tab_commands()
  commands.setup_search_commands()
  commands.setup_template_commands()

  local presets = M.config.project and M.config.project.presets
  if presets and #presets > 0 then
    project.register_presets(presets)
  end

  pcall(function()
    require("workspace.integration.autocmds").setup()
  end)

  -- Register router subtree if router.nvim available and config opts in.
  local router_enabled = M.config.router and M.config.router.enabled ~= false
  if router_enabled then
    pcall(function()
      local router = require("router")
      router.register_subtree("workspace", require("workspace.router_subtree"))
    end)
    pcall(function()
      require("workspace.integration.router_refresh").setup()
    end)
    pcall(function()
      require("workspace.integration.router_scopes").register()
    end)
  end

  if M.config.ui and M.config.ui.tabline
      and M.config.ui.tabline.integration == 'nvchad_tabufline' then
    pcall(function()
      require("workspace.integration.tabufline").setup()
    end)
  end

  -- Persistent tab/project state: subscribes to mutations and (immediately)
  -- rehydrates state.json into tab_state. Default-on; disable with
  -- cfg.persistent_state.enabled = false.
  pcall(function()
    if M.config.persistent_state and M.config.persistent_state.enabled ~= false then
      require("workspace.integration.persist").setup(M.config)
    end
  end)

  pcall(function()
    require("workspace.integration.explorer").setup()
  end)

  -- Scheme B: multi-root explorer (experimental, default off).
  pcall(function()
    require("workspace.integration.explorer_multiroot").setup()
  end)

  -- Override vim.ui.select with a router-styled Snacks-backed picker so all
  -- selection prompts (incl. session.load confirm and any third-party plugin)
  -- match the rest of the workspace UI. Opt-out via cfg.ui.override_vim_select = false.
  if not (M.config.ui and M.config.ui.override_vim_select == false) then
    pcall(function()
      require("workspace.integration.ui_select").install()
    end)
  end

  -- Autoload most-recent session on VimEnter (one-shot) when configured.
  if M.config.session and M.config.session.autoload_last_on_startup then
    local group = vim.api.nvim_create_augroup("WorkspaceAutoload", { clear = true })
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      callback = function()
        local sess = require("workspace.session.api")
        if sess.current and sess.current() then return end
        local list = sess.list() or {}
        if #list == 0 then return end
        table.sort(list, function(a, b)
          return (a.modified_at or 0) > (b.modified_at or 0)
        end)
        pcall(sess.load, list[1].name, { force = true })
      end,
    })
  end
end

function M.save_on_exit()
  require("workspace.integration.autocmds").save_on_exit()
end

return M
