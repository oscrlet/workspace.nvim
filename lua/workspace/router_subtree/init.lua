-- workspace.nvim router subtree registration spec
-- See picker-router-workspace.md §2.2
local M = {}

-- The subtree spec returned/exported:
local subtree = {
  parent = "root",
  entry  = {
    id    = "workspace",
    label = "Workspace: project / session / tab",
  },
  nodes  = require("workspace.router_subtree.nodes"),
}

--- Register this subtree with the given router module.
--- Called by workspace/init.lua when router.enabled = true.
---@param router_mod table  the router module (require("router"))
function M.register_router_subtree(router_mod)
  router_mod.register_subtree("workspace", subtree)
end

-- Return the subtree spec so router.register_subtree can also be called
-- directly: require("router").register_subtree("workspace", require("workspace.router_subtree"))
return setmetatable(subtree, { __index = M })
