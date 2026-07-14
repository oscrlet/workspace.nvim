--- workspace/ui/dashboard.lua
--- alpha.nvim dashboard section provider for recent workspace sessions.
local M = {}

local function cfg_get()
  local ok, cfg_mod = pcall(require, "workspace.config")
  if not ok then return nil end
  local ok2, cfg = pcall(cfg_mod.get)
  if not ok2 then return nil end
  return cfg
end

--- Build a single alpha button entry compatible with alpha-nvim's
--- "button" element (type = "button" with `on_press` callback).
---@param shortcut string
---@param label string
---@param on_press function
---@return table
local function make_button(shortcut, label, on_press)
  return {
    type     = "button",
    val      = label,
    on_press = on_press,
    opts     = {
      position    = "center",
      shortcut    = shortcut,
      cursor      = 3,
      width       = 50,
      align_shortcut = "right",
      hl_shortcut = "Keyword",
      keymap      = {
        "n", shortcut,
        function() on_press() end,
        { noremap = true, silent = true, nowait = true },
      },
    },
  }
end

--- Return an alpha.nvim section table for the most-recent workspace
--- sessions, or nil when disabled / no sessions exist.
---
--- Behaviour:
---  * Returns nil when `cfg.ui.dashboard.alpha_section` is false.
---  * Returns nil when `session.list()` is empty.
---  * Otherwise returns `{ type = "group", val = { ...buttons... },
---    opts = { spacing = 1 } }` with up to 5 buttons in modified-time
---    order. Pressing a button calls `session.load(name, { force = true })`.
---@return table|nil
function M.alpha_section()
  local cfg = cfg_get()
  if cfg and cfg.ui and cfg.ui.dashboard and cfg.ui.dashboard.alpha_section == false then
    return nil
  end

  local ok, session = pcall(require, "workspace.session.api")
  if not ok then return nil end

  local items = session.list() or {}
  if #items == 0 then return nil end

  -- session.list() already sorts by modified_at desc; defensively re-sort.
  table.sort(items, function(a, b)
    return (a.modified_at or 0) > (b.modified_at or 0)
  end)

  local buttons = {}
  local max = math.min(5, #items)
  for i = 1, max do
    local it = items[i]
    local label = string.format(
      "  %s  (%d tabs, %d projects)",
      it.name, it.tab_count or 0, it.project_count or 0
    )
    local shortcut = tostring(i)
    local name = it.name
    buttons[#buttons + 1] = make_button(shortcut, label, function()
      session.load(name, { force = true })
    end)
  end

  return {
    type = "group",
    val = {
      { type = "text", val = "Workspace — recent sessions",
        opts = { hl = "SpecialComment", position = "center" } },
      { type = "padding", val = 1 },
      { type = "group", val = buttons, opts = { spacing = 1 } },
    },
    opts = { spacing = 1 },
  }
end

return M
