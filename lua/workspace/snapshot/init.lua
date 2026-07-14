--- workspace/snapshot/init.lua
--- Dispatcher: routes capture/restore to the right backend based on
--- cfg.session.snapshot_backend (capture path) or blob.kind (restore path).
local M = {}

local function load_backend(name)
  local ok, mod = pcall(require, "workspace.snapshot." .. name)
  if ok and type(mod) == "table" then return mod end
  return nil
end

--- Resolve a backend name to a backend module. "resession-auto" picks
--- resession if its `available()` returns true, else falls back to winlayout.
---@param name string|nil
---@return table backend module
function M.resolve(name)
  name = name or "resession-auto"
  if name == "resession-auto" then
    local resession = load_backend("resession")
    if resession and resession.available and resession.available() then
      return resession
    end
    return load_backend("winlayout")
  end
  local b = load_backend(name)
  if b and b.available and b.available() then return b end
  -- Last-resort fallback.
  return load_backend("winlayout")
end

--- Capture a single tabpage. Returns the encoded JSON blob string, or "" on failure.
---@param tabnr integer
---@param cfg table|nil  workspace config (uses cfg.session.snapshot_backend)
---@return string nvim_state JSON
function M.capture(tabnr, cfg)
  local backend_name = (cfg and cfg.session and cfg.session.snapshot_backend) or "resession-auto"
  local backend = M.resolve(backend_name)
  if not backend then return "" end
  local blob = backend.capture(tabnr)
  if type(blob) ~= "table" then return "" end
  local ok, encoded = pcall(vim.json.encode, blob)
  if ok then return encoded end
  return ""
end

--- Restore a single tabpage from a decoded blob. Caller has already
--- focused the target tabpage. Selects the backend by `decoded.kind`,
--- falling back to winlayout for legacy / missing kinds.
---@param decoded table
---@param tabnr integer
function M.restore(decoded, tabnr)
  if type(decoded) ~= "table" then return end
  local kind = decoded.kind or "winlayout"
  -- Legacy "files" form is handled by winlayout.
  if kind == "files" then
    local backend = load_backend("winlayout")
    if backend then backend.restore(decoded, tabnr) end
    return
  end
  local backend = load_backend(kind) or load_backend("winlayout")
  if backend then backend.restore(decoded, tabnr) end
end

return M
