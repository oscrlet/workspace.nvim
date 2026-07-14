--- workspace/integration/ui_select.lua
--- Minimal vim.ui.select shim that routes the call through
--- Snacks.picker.select. No layout / preset overrides — we let Snacks's
--- own select source render whatever the host has configured (so anything
--- pinned globally via Snacks.config.picker.layout still applies).
---
--- Installed by workspace.setup() (gated by cfg.ui.override_vim_select,
--- default true). Falls back to the previously-installed vim.ui.select
--- when Snacks is not loaded.
---
--- Debug: call M.set_debug(true) to log each call's items / opts /
--- effective Snacks state to /tmp/wsp-uiselect.log so we can diagnose
--- visual issues against real interactive sessions without guessing.
local M = {}

local debug_on = false
local LOG_PATH = "/tmp/wsp-uiselect.log"

local function log(msg)
  if not debug_on then return end
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  f:write(os.date("%H:%M:%S "))
  f:write(msg)
  f:write("\n")
  f:close()
end

local function dump(label, value)
  if not debug_on then return end
  log(label .. " = " .. vim.inspect(value, { newline = " ", indent = "" }))
end

local _pick_wrapped = false
local _orig_pick = nil

--- Idempotently wrap Snacks.picker.pick. Returns true if wrap is now in
--- place (either freshly installed or already from a prior call).
local function ensure_wrap_pick()
  if _pick_wrapped then return true end
  if not (_G.Snacks and _G.Snacks.picker
      and type(_G.Snacks.picker.pick) == "function") then
    return false
  end
  _orig_pick = _G.Snacks.picker.pick
  -- Snacks.picker.pick has two call shapes:
  --   M.pick(opts)             — single table arg
  --   M.pick(source, opts)     — string + table (used by Snacks.picker.<source>(opts))
  -- Forwarding only the first arg silently dropped opts (incl. dirs/cwd)
  -- whenever a source-named call hit the wrapper. Always forward all args.
  _G.Snacks.picker.pick = function(...)
    if debug_on then
      local a, b = ...
      local picker_opts = (type(a) == "table") and a or b
      if picker_opts then
        log("--- Snacks.picker.pick (post-merge) ---")
        log("  source = " .. tostring(picker_opts.source or a))
        log("  title  = " .. tostring(picker_opts.title))
        dump("  layout", picker_opts.layout)
        dump("  dirs",   picker_opts.dirs)
      end
    end
    return _orig_pick(...)
  end
  _pick_wrapped = true
  log("ensure_wrap_pick: wrapped Snacks.picker.pick")
  return true
end

--- vim.ui.select-compatible implementation.
---@param items table
---@param opts table|nil
---@param on_choice fun(item: any|nil, idx: integer|nil)
function M.select(items, opts, on_choice)
  opts = opts or {}
  on_choice = on_choice or function() end

  log("--- M.select call ---")
  dump("items", items)
  dump("opts", opts)

  if not (_G.Snacks and _G.Snacks.picker and type(_G.Snacks.picker.select) == "function") then
    log("Snacks.picker.select unavailable; using fallback")
    local prev = M._previous_select
    if prev then return prev(items, opts, on_choice) end
    return
  end

  -- Lazy-wrap Snacks.picker.pick on first reachable call. This was
  -- previously done in M.install(), but install() runs from
  -- workspace.setup() which may execute before Snacks's picker
  -- submodule has been lazy-loaded. Without the wrap, the host's
  -- pinned layout was not applied on cold start; users had to
  -- :Lazy reload workspace.nvim once to make it stick. Wrapping here
  -- ensures it runs the first time anything actually invokes
  -- vim.ui.select.
  ensure_wrap_pick()

  -- Snacks's select source forces layout = { preset = "select" } at the
  -- end of its pipeline, so the host's globally-pinned layout (e.g.
  -- router_block) does not apply unless we override via opts.snacks.
  -- Reuse whatever the host has pinned in Snacks.config.picker.layout
  -- and add `hidden = { "preview" }` so a 2-3 choice prompt does not
  -- expose an empty preview column.
  local pinned_layout
  if _G.Snacks.config and _G.Snacks.config.picker
      and _G.Snacks.config.picker.layout then
    pinned_layout = _G.Snacks.config.picker.layout
  end
  dump("pinned_layout", pinned_layout)

  if pinned_layout then
    opts = vim.tbl_extend("force", opts, {})
    opts.snacks = opts.snacks or {}
    if opts.snacks.layout == nil then
      -- Build a shallow copy and add hidden = { "preview" }. Snacks
      -- accepts both `layout = "preset_name"` and a table override; we
      -- normalize to a table so we can attach `hidden`.
      local layout_override
      if type(pinned_layout) == "string" then
        layout_override = { preset = pinned_layout, hidden = { "preview" } }
      elseif type(pinned_layout) == "table" then
        layout_override = vim.tbl_deep_extend("force", {}, pinned_layout)
        layout_override.hidden = { "preview" }
      end
      opts.snacks.layout = layout_override
    end
  end
  dump("opts after layout merge", opts)

  log("delegating to Snacks.picker.select")
  _G.Snacks.picker.select(items, opts, on_choice)
end

--- Install M.select as vim.ui.select. Also wraps Snacks.picker.pick
--- transparently so the post-merge picker_opts can always be logged
--- when debug is on later — this isolates "did wrap_pick change
--- behaviour?" as a possible cause of weird debug-on/off differences.
--- Install state diagnostic log (always written; not gated by debug_on).
--- Lets us see at a glance whether vim.ui.select got hijacked by a
--- later plugin (dressing.nvim, noice.nvim, etc.) between our install
--- and the first actual select call.
local INSTALL_LOG = "/tmp/wsp-uiselect-install.log"
local function ilog(msg)
  local f = io.open(INSTALL_LOG, "a")
  if not f then return end
  f:write(os.date("%H:%M:%S "))
  f:write(msg)
  f:write("\n")
  f:close()
end

local function do_install(stage)
  local before = vim.ui.select
  if before ~= M.select then
    M._previous_select = before
    vim.ui.select = M.select
  end
  pcall(ensure_wrap_pick)
  ilog(string.format(
    "install[%s] before==M.select=%s after==M.select=%s pick_wrapped=%s",
    stage,
    tostring(before == M.select),
    tostring(vim.ui.select == M.select),
    tostring(_pick_wrapped)))
end

--- Install M.select as vim.ui.select.
---
--- Cold start has two moving parts:
---   1. Other plugins (dressing.nvim, noice.nvim, etc.) may set
---      vim.ui.select after workspace.setup() runs, displacing us.
---   2. Snacks.picker may not be loaded yet, so the eager wrap_pick
---      no-ops.
---
--- Defenses: install once eagerly, again on VimEnter (after every
--- non-deferred plugin's setup), and once on the first User LazyDone
--- event so lazy.nvim's "after-load" hooks cannot displace us either.
--- Each stage is logged to /tmp/wsp-uiselect-install.log so the user
--- can confirm exactly where the chain lives at any moment.
function M.install()
  -- Truncate log on each install() call (which corresponds to a fresh
  -- workspace.setup or :Lazy reload) so traces stay scoped.
  local f = io.open(INSTALL_LOG, "w")
  if f then f:close() end

  do_install("eager")

  local group = vim.api.nvim_create_augroup("WorkspaceUISelectInstall", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group, once = true,
    callback = function() do_install("VimEnter") end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group, pattern = "VeryLazy", once = true,
    callback = function() do_install("VeryLazy") end,
  })
end

--- Toggle log output only. The pick wrapper is installed once at
--- M.install() time and stays put regardless of debug state, so
--- toggling debug only affects whether the wrapper's logging code path
--- runs — never the rendering path itself.
function M.set_debug(on)
  debug_on = on and true or false
  if debug_on then
    local f = io.open(LOG_PATH, "w")
    if f then f:close() end
    log("debug enabled; pick wrapped = " .. tostring(_pick_wrapped))
    if _G.Snacks then
      log("Snacks loaded: yes")
      if _G.Snacks.config and _G.Snacks.config.picker then
        dump("Snacks.config.picker.layout", _G.Snacks.config.picker.layout)
      else
        log("Snacks.config.picker not present")
      end
    else
      log("Snacks loaded: no")
    end
    log("vim.ui.select == M.select: " .. tostring(vim.ui.select == M.select))
  end
end

return M
