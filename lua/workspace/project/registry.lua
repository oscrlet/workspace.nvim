--- workspace/project/registry.lua
--- In-memory project registry backed by store.lua for persistence.
local M = {}

local store = require("workspace.project.store")
local id_util = require("workspace.util.id")

--- Internal state.
local state = {
  projects = {},  -- table<id, Project>
  cfg = {},
}

--- Build a lookup table of taken ids from current state.
---@return table<string, boolean>
local function taken_ids()
  local t = {}
  for id, _ in pairs(state.projects) do
    t[id] = true
  end
  return t
end

--- Canonicalize a path (resolve ~, realpath if possible).
---@param path string
---@return string
local function normalize_path(path)
  -- Expand tilde.
  if path:sub(1, 1) == "~" then
    path = vim.fn.expand(path)
  end
  -- Realpath for symlink resolution.
  if vim.uv and vim.uv.fs_realpath then
    local real = vim.uv.fs_realpath(path)
    if real then path = real end
  end
  return path
end

--- Flush current state to disk.
---@return boolean ok
local function persist()
  local list = {}
  for _, proj in pairs(state.projects) do
    list[#list + 1] = proj
  end
  local ok, err = store.write({ version = 1, projects = list })
  if not ok then
    vim.notify("[workspace/registry] persist failed: " .. tostring(err), vim.log.levels.ERROR)
  end
  return ok
end

--- Initialize registry from config and stored data.
---@param cfg table
function M.setup(cfg)
  state.cfg = cfg or {}
  M.reload()
end

--- Reload in-memory state from disk.
function M.reload()
  local data = store.read()
  state.projects = {}
  if type(data.projects) == "table" then
    for _, proj in ipairs(data.projects) do
      if type(proj) == "table" and type(proj.id) == "string" then
        state.projects[proj.id] = proj
      end
    end
  end
end

--- Register a new project (or update if force=true and id matches).
---@param opts { path: string, id?: string, name?: string, meta?: table, force?: boolean, markers?: string[] }
---@return table Project
function M.register(opts)
  assert(type(opts) == "table", "register: opts must be a table")
  assert(type(opts.path) == "string", "register: opts.path must be a string")

  local root = normalize_path(opts.path)

  -- Prefer caller-supplied id, else derive unique one.
  local id
  if type(opts.id) == "string" and opts.id ~= "" then
    id = opts.id
    if state.projects[id] and not opts.force then
      error(string.format("[workspace/registry] id '%s' already taken; use force=true to overwrite", id))
    end
  else
    id = id_util.derive(root, taken_ids())
  end

  -- Derive name: caller-supplied or sanitized basename.
  local name = opts.name
  if not name or name == "" then
    name = id_util.from_basename(root)
  end

  local now = os.time()
  local existing = state.projects[id]

  local proj = {
    id         = id,
    name       = name,
    root       = root,
    markers    = opts.markers or (state.cfg.default_markers) or {},
    meta       = opts.meta or {},
    created_at = (existing and existing.created_at) or now,
  }

  state.projects[id] = proj
  persist()
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = existing and "WorkspaceProjectUpdated" or "WorkspaceProjectRegistered",
    data = { id = id, project = proj },
  })
  return proj
end

--- Register a list of preset paths or preset tables.
---@param list (string|{ path: string, id?: string, name?: string, meta?: table })[]
function M.register_presets(list)
  if type(list) ~= "table" then return end
  for _, preset in ipairs(list) do
    local path
    if type(preset) == "string" then
      path = preset
    elseif type(preset) == "table" then
      path = preset.path
    end
    if not path then goto skip_preset end

    -- Skip if already registered by root path.
    if M.find_by_root(path) then
      goto skip_preset
    end

    local ok, err
    if type(preset) == "string" then
      ok, err = pcall(M.register, { path = preset })
    elseif type(preset) == "table" then
      ok, err = pcall(M.register, preset)
    end
    if not ok then
      vim.notify("[workspace/registry] preset register error: " .. tostring(err), vim.log.levels.WARN)
    end

    ::skip_preset::
  end
end

--- Remove a project by id.
---@param id string
---@return boolean  true if found and removed
function M.unregister(id)
  if not state.projects[id] then return false end
  state.projects[id] = nil
  persist()
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WorkspaceProjectUnregistered",
    data = { id = id },
  })
  return true
end

--- Patch fields on an existing project.
---@param id string
---@param patch table
---@return table Project
function M.update(id, patch)
  local proj = state.projects[id]
  if not proj then
    error(string.format("[workspace/registry] update: project '%s' not found", id))
  end
  -- Merge patch (shallow; meta gets merged one level deep).
  for k, v in pairs(patch) do
    if k == "meta" and type(v) == "table" and type(proj.meta) == "table" then
      for mk, mv in pairs(v) do
        proj.meta[mk] = mv
      end
    elseif k ~= "id" and k ~= "created_at" then
      proj[k] = v
    end
  end
  state.projects[id] = proj
  persist()
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WorkspaceProjectUpdated",
    data = { id = id, project = proj },
  })
  return proj
end

--- Get a project by id.
---@param id string
---@return table|nil
function M.get(id)
  return state.projects[id]
end

--- List projects, optionally filtered by meta fields.
---@param filter table?  key/value pairs matched against project.meta
---@return table[]  Project[]
function M.list(filter)
  local results = {}
  for _, proj in pairs(state.projects) do
    local match = true
    if type(filter) == "table" then
      for k, v in pairs(filter) do
        if proj.meta == nil or proj.meta[k] ~= v then
          match = false
          break
        end
      end
    end
    if match then
      results[#results + 1] = proj
    end
  end
  -- Sort by created_at for stable ordering.
  table.sort(results, function(a, b)
    return (a.created_at or 0) < (b.created_at or 0)
  end)
  return results
end

--- Find a project whose root matches the given path.
---@param path string
---@return table|nil
function M.find_by_root(path)
  local norm = normalize_path(path)
  for _, proj in pairs(state.projects) do
    if proj.root == norm then return proj end
  end
  return nil
end

--- Check whether an id is registered.
---@param id string
---@return boolean
function M.exists(id)
  return state.projects[id] ~= nil
end

return M
