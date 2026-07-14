--- test/spec/config_defaults_spec.lua
--- Verifies that lua/workspace/config.lua exposes all defaults mandated by
--- project-new.md §11, and that M.merge() preserves user overrides while
--- keeping sibling defaults intact.

local config = require("workspace.config")

local function get_path(tbl, path)
  local cur = tbl
  for part in string.gmatch(path, "[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[part]
  end
  return cur
end

describe("config defaults (spec §11)", function()
  before_each(function()
    config._reset()
  end)

  it("exposes every required key path with a non-nil default", function()
    local cfg = config.merge({})

    local required = {
      "data_dir",

      "project.default_markers",
      "project.id_strategy",
      "project.auto_register_on_load",
      "project.presets",
      "project.auto_scan.enabled",
      "project.auto_scan.globs",
      "project.auto_scan.markers",
      "project.auto_scan.max_depth",
      "project.preview.command",
      "project.preview.depth",
      "project.preview.show_hidden",
      "project.preview.respect_gitignore",
      "project.preview.show_meta",
      "project.preview.max_entries",

      "session.autosave",
      "session.autosave_debounce_ms",
      "session.autosave_on_exit",
      "session.autoload_last_on_startup",
      "session.confirm_before_load",
      "session.preview.show_tab_labels",
      "session.preview.show_project_active_marker",
      "session.preview.show_modified_at",
      "session.preview.show_buffer_count",

      "tab.cwd_strategy",
      "tab.fallback_grep_to_cwd",

      "lsp.auto_register_workspace_folders",
      "lsp.excluded_clients",

      "ui.picker",
      "ui.statusline.enabled",
      "ui.tabline.integration",
      "ui.tabline.show_label",
      "ui.tabline.show_active_project",
      "ui.tabline.fallback",
      "ui.dashboard.alpha_section",
      "ui.dashboard.max_recent",

      "router.enabled",
      "router.entry_command",
      "router.entry_keymap",
      "router.breadcrumb",
      "router.list_cache_ttl",
      "router.preview_cache_ttl",
      "router.tools",

      "keymaps",
      "log.level",
    }

    for _, p in ipairs(required) do
      assert.is_not_nil(get_path(cfg, p), "missing default at: " .. p)
    end
  end)

  it("specifically asserts critical defaults", function()
    local cfg = config.merge({})

    assert.is_string(cfg.data_dir)
    assert.is_true(#cfg.data_dir > 0)
    assert.equals("basename", cfg.project.id_strategy)
    assert.is_true(cfg.project.auto_register_on_load)
    assert.is_true(cfg.session.autosave)
    assert.equals(500, cfg.session.autosave_debounce_ms)
    assert.is_true(cfg.router.enabled)
    assert.equals("table", type(cfg.router.tools))
    assert.is_true(#cfg.router.tools > 0)
  end)

  it("data_dir override survives merge", function()
    local cfg = config.merge({ data_dir = "/tmp/ws-test-xyz" })
    assert.equals("/tmp/ws-test-xyz", cfg.data_dir)
    -- siblings intact
    assert.is_true(cfg.project.auto_register_on_load)
    assert.is_true(cfg.router.enabled)
  end)

  it("project override survives merge; siblings intact", function()
    local cfg = config.merge({ project = { id_strategy = "hash" } })
    assert.equals("hash", cfg.project.id_strategy)
    -- siblings within project
    assert.is_true(cfg.project.auto_register_on_load)
    assert.equals("eza", cfg.project.preview.command)
    -- siblings on other branches
    assert.is_true(cfg.session.autosave)
    assert.is_true(cfg.router.enabled)
  end)

  it("session override survives merge; siblings intact", function()
    local cfg = config.merge({ session = { autosave_debounce_ms = 1234 } })
    assert.equals(1234, cfg.session.autosave_debounce_ms)
    assert.is_true(cfg.session.autosave)
    assert.is_true(cfg.session.autosave_on_exit)
    -- other branches untouched
    assert.equals("basename", cfg.project.id_strategy)
  end)

  it("tab override survives merge; siblings intact", function()
    local cfg = config.merge({ tab = { cwd_strategy = "manual" } })
    assert.equals("manual", cfg.tab.cwd_strategy)
    assert.is_true(cfg.tab.fallback_grep_to_cwd)
  end)

  it("lsp override survives merge; siblings intact", function()
    local cfg = config.merge({ lsp = { excluded_clients = { "rust_analyzer" } } })
    assert.same({ "rust_analyzer" }, cfg.lsp.excluded_clients)
    assert.is_true(cfg.lsp.auto_register_workspace_folders)
  end)

  it("ui override survives merge; siblings intact", function()
    local cfg = config.merge({ ui = { picker = "telescope" } })
    assert.equals("telescope", cfg.ui.picker)
    assert.equals("nvchad_tabufline", cfg.ui.tabline.integration)
    assert.is_true(cfg.ui.dashboard.alpha_section)
  end)

  it("router override survives merge; tools default retained", function()
    local cfg = config.merge({ router = { enabled = false } })
    assert.is_false(cfg.router.enabled)
    -- router.tools must NOT be stomped to nil
    assert.equals("table", type(cfg.router.tools))
    assert.is_true(#cfg.router.tools > 0)
    assert.equals("Workspace", cfg.router.entry_command)
  end)

  it("log override survives merge; siblings intact", function()
    local cfg = config.merge({ log = { level = "DEBUG" } })
    assert.equals("DEBUG", cfg.log.level)
    -- other branches untouched
    assert.is_true(cfg.router.enabled)
  end)
end)
