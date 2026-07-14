--- workspace/integration/explorer_multiroot.lua
--- Scheme B: Multi-root Explorer.
---
--- Registers a custom Snacks.picker source `workspace_explorer` whose
--- top-level rows are the projects on the current tab. Selecting a row
--- opens a single-root `Snacks.picker.explorer({ cwd = root })`.
---
--- Off by default; enable with `cfg.ui.explorer_multiroot.enabled = true`.
---
--- Public API:
---   M.setup()            — registers the source + autocmds (idempotent).
---   M.open()             — opens the picker.
---   M._items()           — returns top-level items for the current tab.
---   M._refresh()         — refreshes any open picker (exposed for spec).
---
--- See DESIGN_NOTES.md for the v1 acceptance contract and deferred items.

local M = {}

M.SOURCE = "workspace_explorer"
M.AUGROUP = "WorkspaceExplorerMultiroot"

--- Reactive events that must trigger a refresh of the multi-root picker.
local REFRESH_EVENTS = {
  "WorkspaceProjectRegistered",
  "WorkspaceProjectUnregistered",
  "WorkspaceProjectUpdated",
  "WorkspaceSessionSaved",
  "WorkspaceSessionDeleted",
  "WorkspaceSessionRenamed",
  "WorkspaceTabProjectAdded",
  "WorkspaceTabProjectRemoved",
}

--- TabActiveChanged is observed but does NOT relocate cwd (multi-root preserves all roots).
local TAB_ACTIVE_EVENT = "WorkspaceTabActiveChanged"

local function snacks()
  return _G.Snacks
end

local function notify_warn(msg)
  pcall(vim.notify, "[workspace] " .. msg, vim.log.levels.WARN)
end

--- Build top-level items: one per project on the current tab.
---@return table[]
function M._items()
  local ok_tab, tab = pcall(require, "workspace.tab")
  if not ok_tab or not tab or type(tab.projects) ~= "function" then
    return {}
  end
  local projects = tab.projects() or {}
  if #projects == 0 then
    notify_warn("multi-root explorer: no projects on this tab")
    return {}
  end
  local items = {}
  for _, p in ipairs(projects) do
    if p and p.root and p.root ~= "" then
      items[#items + 1] = {
        file    = p.root,
        text    = p.name or p.id or p.root,
        dir     = true,
        type    = "directory",
        open    = false,
        project = p,
      }
    end
  end
  return items
end

--- Open a single-root explorer rooted at the selected project.
---@param item table
local function drill_in(item)
  local s = snacks()
  if not s or not s.picker or not s.picker.explorer then
    notify_warn("multi-root explorer: Snacks.picker.explorer unavailable")
    return
  end
  if not item or not item.file then return end
  pcall(s.picker.explorer, { cwd = item.file })
end

-- Items cache. Snacks finders run in a libuv fast/async context where
-- `nvim_get_current_tabpage` and friends are forbidden, so we cannot
-- compute items inside the finder. Instead, compute on the main loop
-- (M.open / M._refresh) and stash here; the finder just iterates.
local _cached_items = {}

--- Define the picker source config.
---@return table
local function build_source_config()
  return {
    finder = function(_opts, _ctx)
      return function(cb)
        for _, item in ipairs(_cached_items) do
          cb(item)
        end
      end
    end,
    format = "file",
    -- Render in the same right-side column the single-root explorer
    -- uses, so confirming a project drills in place rather than jumping
    -- columns. The host's pinned default layout (router_block) has its
    -- own position, but `sidebar` preset honors the layout.position
    -- override below.
    layout = {
      preset = "sidebar",
      preview = false,
      layout = { position = "right" },
    },
    matcher = { sort_empty = false, fuzzy = false },
    confirm = function(picker, item)
      picker:close()
      if item then drill_in(item) end
    end,
  }
end

--- Register the source on `Snacks.picker.sources` if not already present.
---@return boolean ok
local function register_source()
  local s = snacks()
  if not s or not s.picker then return false end
  -- `Snacks.picker.sources` is `snacks.picker.config.sources` via __index.
  local sources = s.picker.sources
  if type(sources) ~= "table" then return false end
  sources[M.SOURCE] = build_source_config()
  return true
end

--- Refresh any open picker for our source.
--- Always runs the recompute under vim.schedule so callers reaching
--- here from a fast event context (User autocmd payload) do not trip
--- nvim_get_current_tabpage in tab.projects().
function M._refresh()
  vim.schedule(function()
    _cached_items = M._items()
    local s = snacks()
    if not s or not s.picker or type(s.picker.get) ~= "function" then return end
    local pickers = s.picker.get({ source = M.SOURCE }) or {}
    for _, p in ipairs(pickers) do
      if type(p.find) == "function" then
        pcall(function() p:find() end)
      end
    end
  end)
end

--- Configure the integration. Idempotent.
function M.setup()
  -- Always tear down any previous augroup so toggling enabled=false cleans up.
  pcall(vim.api.nvim_del_augroup_by_name, M.AUGROUP)

  local cfg = require("workspace.config").get()
  local mr = (cfg.ui and cfg.ui.explorer_multiroot) or {}
  if mr.enabled ~= true then
    -- Default off; do nothing.
    return
  end

  -- Register the picker source if Snacks is present.
  register_source()

  -- Subscribe to refresh events.
  local group = vim.api.nvim_create_augroup(M.AUGROUP, { clear = true })
  for _, pat in ipairs(REFRESH_EVENTS) do
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = pat,
      callback = function() M._refresh() end,
    })
  end
  -- TabActiveChanged: refresh items but never relocate cwd.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = TAB_ACTIVE_EVENT,
    callback = function() M._refresh() end,
  })
end

--- Open the multi-root explorer picker.
function M.open()
  local s = snacks()
  if not s or not s.picker or type(s.picker.pick) ~= "function" then
    notify_warn("multi-root explorer: Snacks.picker.pick unavailable")
    return
  end
  -- Ensure source is registered (no-op if already).
  register_source()
  -- Pre-compute on main loop so the finder (called in fast context)
  -- doesn't try to read tabpage state.
  _cached_items = M._items()
  pcall(s.picker.pick, { source = M.SOURCE })
end

return M
