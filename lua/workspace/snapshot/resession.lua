--- workspace/snapshot/resession.lua
--- Adapter for the resession.nvim plugin. resession's public API is whole-
--- session save/load (`resession.save(name)` / `resession.load(name)`); it
--- does not expose a stable per-tab subset capture. We work around that by
--- writing a *named* resession session per workspace tab and stashing the
--- name in the blob; restore loads that named session.
---
--- Limitations:
---   * Each capture creates one resession-managed session per tab (named
---     `__workspace_tab_<tabnr>_<short>`); cleanup of stale names is best-effort.
---   * If the resession plugin is missing or its API doesn't match
---     expectations, `available()` returns false and the dispatcher falls
---     back to winlayout.
local M = {}

M.kind = "resession"

local function load_resession()
  local ok, mod = pcall(require, "resession")
  if not ok or type(mod) ~= "table" then return nil end
  if type(mod.save) ~= "function" or type(mod.load) ~= "function" then
    return nil
  end
  return mod
end

function M.available()
  return load_resession() ~= nil
end

local function session_name_for(tabnr)
  -- A short, deterministic-per-call session name. Using time + tabnr +
  -- random keeps consecutive captures unique without us having to track state.
  local rand = math.random(0, 0xFFFFFF)
  return string.format("__workspace_tab_%d_%x_%x", tabnr, os.time() % 0xFFFFFF, rand)
end

--- Capture a tabpage by delegating to resession.save(name, ...). Stores
--- the chosen session name in the blob so restore can load it again.
---@param tabnr integer
---@return table|nil
function M.capture(tabnr)
  local resession = load_resession()
  if not resession then return nil end
  if not pcall(vim.api.nvim_set_current_tabpage, tabnr) then
    return nil
  end
  local name = session_name_for(tabnr)
  local ok = pcall(resession.save, name, { notify = false })
  if not ok then return nil end
  return {
    kind         = "resession",
    session_name = name,
  }
end

--- Restore by calling resession.load(name).
---@param decoded table
---@param tabnr integer
function M.restore(decoded, tabnr)
  if type(decoded) ~= "table" or type(decoded.session_name) ~= "string" then return end
  local resession = load_resession()
  if not resession then return end
  pcall(vim.cmd, "silent only")
  pcall(resession.load, decoded.session_name, { notify = false, attach = false })
end

return M
