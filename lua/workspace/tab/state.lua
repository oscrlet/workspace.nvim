--- workspace/tab/state.lua
--- Module-local tab state map: uuid <-> tabnr.
local M = {}

-- state[tabnr] = TabSession
local _by_tabnr = {}
-- uuid -> tabnr index
local _by_uuid = {}

local function gen_uuid()
  -- Use vim.fn.sha256 on tabnr + time + random for a stable uuid-like string.
  local raw = tostring(math.random(1e15)) .. tostring(vim.loop.hrtime())
  return vim.fn.sha256(raw):sub(1, 32)
end

--- Create or return existing TabSession for tabnr.
---@param tabnr number
---@return table TabSession
function M.ensure(tabnr)
  if _by_tabnr[tabnr] then
    return _by_tabnr[tabnr]
  end
  local uuid = gen_uuid()
  local tab = {
    id               = uuid,
    uuid             = uuid,
    tabnr            = tabnr,
    label            = nil,
    order            = tabnr,
    cwd              = vim.fn.getcwd(),
    project_ids      = {},
    active_project_id = nil,
    nvim_state       = "",
  }
  _by_tabnr[tabnr] = tab
  _by_uuid[uuid]   = tabnr
  return tab
end

--- Lookup by tabnr.
---@param tabnr number
---@return table|nil
function M.by_tabnr(tabnr)
  return _by_tabnr[tabnr]
end

--- Lookup by uuid.
---@param uuid string
---@return table|nil
function M.by_uuid(uuid)
  local nr = _by_uuid[uuid]
  if not nr then return nil end
  return _by_tabnr[nr]
end

--- Return all TabSessions sorted by order.
---@return table[]
function M.all()
  local result = {}
  for _, tab in pairs(_by_tabnr) do
    result[#result + 1] = tab
  end
  table.sort(result, function(a, b)
    return (a.order or 0) < (b.order or 0)
  end)
  return result
end

--- Remove entry for tabnr.
---@param tabnr number
function M.remove(tabnr)
  local tab = _by_tabnr[tabnr]
  if not tab then return end
  _by_uuid[tab.id] = nil
  _by_tabnr[tabnr] = nil
end

--- Reset all state (for testing).
function M._reset()
  _by_tabnr = {}
  _by_uuid  = {}
end

return M
