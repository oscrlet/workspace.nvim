-- Live-refresh the router-rendered picker on workspace mutation events.
-- When any of the listed User events fires, invalidate router's items()
-- cache and re-apply the active frame in place so items are re-pulled from
-- the (now-updated) registry / session / tab state. Without this, an action
-- like "remove project" with after = "stay" leaves the deleted item
-- visible in the list until the user closes and re-opens the picker.
--
-- 收口4 (T3): this goes entirely through router's L1 public API
-- (router.invalidate_items + router.refresh_active). It no longer reaches
-- into router.renderer.invalidate_items_cache nor calls Snacks.picker.get /
-- closes pickers itself — refresh_active() owns the in-place re-apply, and
-- works for both volt and snacks backends behind the L1 seam.

local M = {}

local EVENTS = {
  "WorkspaceProjectRegistered",
  "WorkspaceProjectUnregistered",
  "WorkspaceProjectUpdated",
  "WorkspaceSessionSaved",
  "WorkspaceSessionDeleted",
  "WorkspaceSessionRenamed",
  "WorkspaceTabProjectAdded",
  "WorkspaceTabProjectRemoved",
}

local timer = nil
local DEBOUNCE_MS = 50

-- Set via M.set_debug(true) to print each refresh step to :messages.
local debug = false
local function dbg(msg) if debug then vim.notify("[router_refresh] " .. msg) end end

local function refresh_now()
  timer = nil

  local ok_router, router = pcall(require, "router")
  if not ok_router or not router then
    dbg("router unavailable"); return
  end

  -- Always invalidate router's items() cache, even when no picker is open.
  -- The TTL cache otherwise serves stale items the next time the user
  -- opens the same node — e.g. ProjectDiscover registers projects with
  -- no picker open, then :ProjectList shows the pre-discover (empty) list
  -- until the cache TTL expires or the user restarts.
  if type(router.invalidate_items) == "function" then
    pcall(router.invalidate_items)
  end

  -- Re-apply the active frame in place. refresh_active() is a no-op when no
  -- frame is on the stack, so guard on router.current() to keep the debug
  -- trace meaningful and avoid an unnecessary call when nothing is open.
  if type(router.current) ~= "function" then return end
  local current = router.current()
  if not current then dbg("no active frame (cache cleared)"); return end

  dbg("refresh_active current=" .. tostring(current))
  if type(router.refresh_active) == "function" then
    local ok, err = pcall(router.refresh_active)
    if not ok then dbg("refresh_active error: " .. tostring(err)) end
  end
end

local function schedule_refresh()
  if timer then
    pcall(vim.fn.timer_stop, timer)
  end
  timer = vim.fn.timer_start(DEBOUNCE_MS, function()
    vim.schedule(refresh_now)
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("WorkspaceRouterRefresh", { clear = true })
  for _, ev in ipairs(EVENTS) do
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = ev,
      callback = schedule_refresh,
    })
  end
  M._events = EVENTS
  M._refresh = refresh_now
end

function M.set_debug(on) debug = on and true or false end

return M
