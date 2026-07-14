local M = {}

local path = require("workspace.util.path")
local log = require("workspace.util.log")
local config = require("workspace.config")
local id = require("workspace.util.id")

local function has_marker(dir, markers)
  for _, marker in ipairs(markers) do
    local marker_path = dir .. "/" .. marker
    local stat = vim.uv.fs_stat(marker_path)
    if stat then
      return true
    end
  end
  return false
end

-- When a candidate dir contains `.project`, the file's id/name are
-- authoritative (set by :ProjectInit or hand-edited). Fall back to the
-- basename-derived id when the file is missing or invalid.
local function suggested_from(dir)
  local dotfile = require("workspace.project.dotfile")
  local payload = dotfile.read(dir)
  if payload and type(payload.id) == "string" and payload.id ~= "" then
    return payload.id, payload.name
  end
  return id.from_basename(dir), nil
end

local function scan_directory(dir, markers, seen_dirs)
  local candidates = {}
  seen_dirs = seen_dirs or {}

  local real_dir = path.realpath(dir)
  if not real_dir or seen_dirs[real_dir] then
    return candidates
  end
  seen_dirs[real_dir] = true

  if has_marker(real_dir, markers) then
    local sid, sname = suggested_from(real_dir)
    table.insert(candidates, {
      path = real_dir,
      markers_found = markers,
      suggested_id = sid,
      suggested_name = sname,
    })
  end

  return candidates
end

function M.scan_path(target_path, opts)
  opts = opts or {}
  local markers = opts.markers or config.get().project.auto_scan.markers
  return scan_directory(target_path, markers, {})
end

function M.discover(globs, opts)
  opts = opts or {}
  local markers = opts.markers or config.get().project.auto_scan.markers
  local candidates = {}
  local seen = {}

  for _, pattern in ipairs(globs) do
    -- vim.fn.glob with 3rd arg=true returns a list AND handles `~` expansion.
    -- Do NOT pre-expand the pattern — vim.fn.expand would itself glob the `*`
    -- and yield a newline-joined string that vim.fn.glob can no longer match.
    local matches = vim.fn.glob(pattern, false, true)

    for _, match_path in ipairs(matches) do
      local stat = vim.uv.fs_stat(match_path)
      if stat and stat.type == "directory" then
        local real = path.realpath(match_path)
        if real and not seen[real] then
          seen[real] = true

          local found_markers = {}
          for _, marker in ipairs(markers) do
            if vim.uv.fs_stat(real .. "/" .. marker) then
              table.insert(found_markers, marker)
            end
          end

          if #found_markers > 0 then
            local sid, sname = suggested_from(real)
            table.insert(candidates, {
              path = real,
              markers_found = found_markers,
              suggested_id = sid,
              suggested_name = sname,
            })

            if opts.on_match then
              opts.on_match(candidates[#candidates])
            end
          end
        end
      end
    end
  end

  if not opts.dry_run then
    local registry = require("workspace.project.registry")
    for _, candidate in ipairs(candidates) do
      registry.register({
        path = candidate.path,
        id = candidate.suggested_id,
        name = candidate.suggested_name,
        markers = candidate.markers_found,
      })
    end
  end

  return candidates
end

return M
