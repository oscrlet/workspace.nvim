local M = {}

local registry = require("workspace.project.registry")
local discover = require("workspace.project.discover")

-- Re-export registry methods
M.setup = registry.setup
M.register = registry.register
M.register_presets = registry.register_presets
M.unregister = registry.unregister
M.update = registry.update
M.get = registry.get
M.list = registry.list
M.find_by_root = registry.find_by_root
M.exists = registry.exists
M.reload = registry.reload

-- Re-export discover methods
M.discover = discover.discover
M.scan_path = discover.scan_path

-- Re-export dotfile helpers (.project read/write).
local dotfile = require("workspace.project.dotfile")
M.dotfile = dotfile

function M.input_path_candidates()
  local projects = registry.list()
  local seen_parents = {}
  local parents = {}

  -- Collect unique parent dirs, sorted by creation time (newest first)
  for i = #projects, 1, -1 do
    local proj = projects[i]
    local parent = vim.fn.fnamemodify(proj.root, ":h")
    if not seen_parents[parent] then
      seen_parents[parent] = true
      table.insert(parents, parent)
      if #parents >= 10 then
        break
      end
    end
  end

  return parents
end

return M
