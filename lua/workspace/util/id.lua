--- workspace/util/id.lua
--- Derive unique project ids from filesystem paths.
local M = {}

--- Sanitize a name component: lowercase, replace non-alnum with '_', collapse runs.
---@param s string
---@return string
local function sanitize(s)
  return (s:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

--- Return the basename of a path (last component, no trailing slash).
---@param path string
---@return string
local function basename(path)
  local p = path:gsub("/+$", "")
  return p:match("([^/]+)$") or p
end

--- Return the parent directory of a path.
---@param path string
---@return string
local function parent(path)
  local p = path:gsub("/+$", "")
  return p:match("^(.*)/[^/]+$") or "."
end

--- Produce a candidate id from basename only.
---@param path string
---@return string
function M.from_basename(path)
  local b = basename(path)
  local s = sanitize(b)
  if s == "" then s = "project" end
  return s
end

--- Derive a unique id for `path` given a set of already-taken ids.
--- Strategy:
---   1. basename  →  "myproject"
---   2. collision → parentdir_basename  →  "work_myproject"
---   3. further   → append numeric suffix  →  "work_myproject_2", "_3", ...
---@param path string
---@param taken table<string, any>   keys are taken ids (values ignored)
---@return string
function M.derive(path, taken)
  taken = taken or {}

  -- Canonicalize via realpath if available (handles symlinks).
  if vim and vim.uv and vim.uv.fs_realpath then
    local real = vim.uv.fs_realpath(path)
    if real then path = real end
  end

  -- Step 1: basename
  local id = M.from_basename(path)
  if not taken[id] then return id end

  -- Step 2: parentdir_basename
  local par = basename(parent(path))
  local par_s = sanitize(par)
  if par_s ~= "" then
    local id2 = par_s .. "_" .. id
    if not taken[id2] then return id2 end
    -- Step 3: numeric suffix on the compound form
    local n = 2
    while true do
      local idn = id2 .. "_" .. n
      if not taken[idn] then return idn end
      n = n + 1
    end
  else
    -- No useful parent; fall back straight to numeric suffix on base id.
    local n = 2
    while true do
      local idn = id .. "_" .. n
      if not taken[idn] then return idn end
      n = n + 1
    end
  end
end

return M
