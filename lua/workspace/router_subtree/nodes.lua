-- Aggregate all node files into one keyed table
local M = {}

local function merge(t)
  for k, v in pairs(t) do
    M[k] = v
  end
end

merge(require("workspace.router_subtree.nodes.workspace"))
merge(require("workspace.router_subtree.nodes.project"))
merge(require("workspace.router_subtree.nodes.session"))
merge(require("workspace.router_subtree.nodes.tab"))
merge(require("workspace.router_subtree.nodes.ops"))
merge(require("workspace.router_subtree.nodes.search"))

return M
