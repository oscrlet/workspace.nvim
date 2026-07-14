--- workspace/migrate/projections.lua
--- One-shot migration tool from projections.nvim's projections.json
--- into workspace.nvim's project registry.
---
--- Source format (per projections.nvim storage):
---   {
---     "<session-name>": ["<root-path>", "<root-path>", ...],
---     ...
---   }
--- Each session-name maps to a list of project root paths. We flatten
--- the union of roots across all session-names, deduplicate by realpath,
--- and register each as a workspace project with meta.auto =
--- "migrate_projections".
local M = {}

--- Default source path: projections.nvim writes to nvim data dir.
---@return string
local function default_src()
  return vim.fn.stdpath("data") .. "/projections.json"
end

--- Read and decode the source file.
---@param src_path string
---@return table|nil decoded, string|nil err
local function parse(src_path)
  local f = io.open(src_path, "r")
  if not f then return nil, "src not found: " .. src_path end
  local raw = f:read("*a")
  f:close()
  if not raw or raw == "" then
    return nil, "src empty: " .. src_path
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    return nil, "invalid JSON: " .. tostring(decoded)
  end
  if type(decoded) ~= "table" then
    return nil, "invalid JSON: top-level not an object"
  end
  return decoded
end

--- Normalize a path: expand ~, resolve realpath when possible.
---@param p string
---@return string
local function normalize(p)
  if p:sub(1, 1) == "~" then
    p = vim.fn.expand(p)
  end
  if vim.uv and vim.uv.fs_realpath then
    local real = vim.uv.fs_realpath(p)
    if real then return real end
  end
  return p
end

--- Run the migration.
---@param opts { src_path?: string, dry_run?: boolean }|nil
---@return table|nil result  { added, skipped, errors } on success
---@return string|nil err     non-nil only on parse / IO failure
function M.run(opts)
  opts = opts or {}
  local src = opts.src_path or default_src()
  local data, err = parse(src)
  if not data then return nil, err end

  local registry = require("workspace.project.registry")
  local id_util = require("workspace.util.id")

  local added, skipped, errors = {}, {}, {}
  local seen_roots = {}  -- realpath -> id (dedup across session-names)

  -- Build current taken-id set so derive() avoids collisions with
  -- already-registered ids that don't conflict on root.
  local taken = {}
  for _, p in ipairs(registry.list()) do
    taken[p.id] = true
  end

  for _, roots in pairs(data) do
    if type(roots) == "table" then
      for _, root in ipairs(roots) do
        if type(root) == "string" and root ~= "" then
          local real = normalize(root)
          if not seen_roots[real] then
            -- Try to find an existing project by root first; if so, skip.
            local by_root = registry.find_by_root(real)
            if by_root then
              skipped[#skipped + 1] = {
                id   = by_root.id,
                root = real,
                reason = "root already registered",
              }
              seen_roots[real] = by_root.id
            else
              local id = id_util.derive(real, taken)
              local existing = registry.get(id)
              if existing then
                local existing_real = normalize(existing.root or "")
                if existing_real == real then
                  skipped[#skipped + 1] = {
                    id   = id,
                    root = real,
                    reason = "id+root already registered",
                  }
                  seen_roots[real] = id
                else
                  errors[#errors + 1] = {
                    id            = id,
                    src_root      = real,
                    existing_root = existing.root,
                  }
                  -- Don't claim this id; mark as seen so we don't loop.
                  seen_roots[real] = false
                end
              else
                local entry = {
                  id   = id,
                  name = id,
                  root = real,
                  meta = { auto = "migrate_projections" },
                }
                if not opts.dry_run then
                  -- registry.register uses opts.path (not opts.root).
                  registry.register({
                    id   = id,
                    name = entry.name,
                    path = real,
                    meta = entry.meta,
                  })
                end
                added[#added + 1] = entry
                seen_roots[real] = id
                taken[id] = true
              end
            end
          end
        end
      end
    end
  end

  return { added = added, skipped = skipped, errors = errors }
end

return M
