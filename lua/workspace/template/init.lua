--- workspace/template/init.lua
--- Template module initialization.
local M = {}

function M.setup(cfg)
  -- No-op for now; just export api.
end

M.api = require("workspace.template.api")

return M
