local M = {}

local function default_data_dir()
  -- Fallback when stdpath is unavailable (e.g., in some test contexts).
  local ok, p = pcall(vim.fn.stdpath, "data")
  if ok and p and p ~= "" then
    return p .. "/workspace"
  end
  return vim.fn.expand("~/.local/share/nvim/workspace")
end

local function build_defaults()
  return {
    -- Top-level data directory (sessions, projects.json, lockfiles, etc.)
    data_dir = default_data_dir(),

    -- Project configuration
    project = {
      default_markers = { ".git", ".project", ".workspace" },
      id_strategy = "basename", -- "basename" | "hash" | "user"
      auto_register_on_load = true,

      presets = {},

      auto_scan = {
        enabled = false,
        globs = {},
        markers = { ".git", ".project" },
        max_depth = 3,
      },

      preview = {
        command = "eza", -- "eza" | "tree" | "fd" | "builtin"
        depth = 2,
        show_hidden = false,
        respect_gitignore = true,
        show_meta = true,
        max_entries = 200,
      },
    },

    -- Session configuration
    session = {
      autosave = true,
      autosave_debounce_ms = 500,
      autosave_on_exit = true,
      autoload_last_on_startup = false,
      confirm_before_load = true,

      -- Per-tab snapshot backend.
      --   "winlayout"      -- pure lua, zero deps
      --   "mksession"      -- :mksession per-tab + sanitization
      --   "resession-auto" -- use resession.nvim if installed, else winlayout
      snapshot_backend = "resession-auto",

      preview = {
        show_tab_labels = true,
        show_project_active_marker = true,
        show_modified_at = true,
        show_buffer_count = false,
      },
    },

    -- Tab / Workspace configuration
    tab = {
      cwd_strategy = "active_project", -- "active_project" | "manual"
      fallback_grep_to_cwd = true,
    },

    -- Persistent tab/project state (independent of named sessions).
    -- When enabled, mutations are written to `<data_dir>/state.json` and
    -- restored at cold-start before any user command runs.
    --
    -- Default OFF: cold-start no-session is meant to be ephemeral —
    -- explicit :SessionSave is the persistence path. Opt in for
    -- IDE-style "remember everything across restarts" behaviour.
    persistent_state = {
      enabled = false,
      -- Debounce window for coalescing rapid mutations into one write.
      -- Defaults to session.autosave_debounce_ms when unset.
      debounce_ms = nil,
    },

    -- LSP integration
    lsp = {
      auto_register_workspace_folders = true,
      excluded_clients = {},
    },

    -- UI configuration
    ui = {
      picker = "snacks", -- "snacks" | "telescope"

      statusline = {
        enabled = false,
      },

      tabline = {
        integration = "nvchad_tabufline", -- "none" | "nvchad_tabufline" | "builtin_helpers"
        show_label = true,
        show_active_project = true,
        fallback = "cwd_basename",
      },

      dashboard = {
        alpha_section = true,
        max_recent = 10,
      },

      explorer = {
        auto_follow_active_project = true,
        follow_current_file        = true,
      },

      -- Scheme B: multi-root explorer (experimental, default off).
      -- See DESIGN_NOTES.md / README "Multi-root explorer (experimental)".
      explorer_multiroot = {
        enabled = false,
      },
    },

    -- Router (picker-router) integration
    router = {
      enabled = true,
      entry_command = "Workspace",
      entry_keymap = "<leader><leader>",
      breadcrumb = true,
      list_cache_ttl = 60,
      preview_cache_ttl = 60,
      tools = {
        "files", "grep", "buffers", "recent",
        "git_log", "git_status", "git_branches",
        "lsp_symbols", "lsp_workspace_symbols",
        "diagnostics", "keymaps", "commands",
      },
    },

    -- User keymaps (intentionally empty by default)
    keymaps = {},

    -- Logging
    log = {
      level = "WARN",
    },
  }
end

local current_config = build_defaults()

-- Branches that we deep-merge wholesale via vim.tbl_deep_extend.
local DEEP_MERGE_BRANCHES = {
  "session", "tab", "lsp", "ui", "router", "log", "keymaps", "persistent_state",
}

function M.merge(user_opts)
  if not user_opts then
    return current_config
  end

  -- Top-level scalar: data_dir
  if user_opts.data_dir ~= nil then
    current_config.data_dir = user_opts.data_dir
  end

  -- project: keep historical selective-merge semantics so that
  -- list-like fields (presets) are *replaced*, not merged-by-index.
  if user_opts.project then
    local up = user_opts.project
    if up.presets ~= nil then
      current_config.project.presets = up.presets
    end
    if up.auto_register_on_load ~= nil then
      current_config.project.auto_register_on_load = up.auto_register_on_load
    end
    if up.id_strategy ~= nil then
      current_config.project.id_strategy = up.id_strategy
    end
    if up.default_markers ~= nil then
      current_config.project.default_markers = up.default_markers
    end
    if up.auto_scan then
      current_config.project.auto_scan = vim.tbl_deep_extend(
        "force",
        current_config.project.auto_scan,
        up.auto_scan
      )
    end
    if up.preview then
      current_config.project.preview = vim.tbl_deep_extend(
        "force",
        current_config.project.preview,
        up.preview
      )
    end
  end

  -- All other top-level branches: deep merge from defaults.
  for _, key in ipairs(DEEP_MERGE_BRANCHES) do
    if user_opts[key] ~= nil then
      current_config[key] = vim.tbl_deep_extend(
        "force",
        current_config[key] or {},
        user_opts[key]
      )
    end
  end

  return current_config
end

function M.get()
  return current_config
end

-- Test helper: reset to pristine defaults.
function M._reset()
  current_config = build_defaults()
  return current_config
end

return M
