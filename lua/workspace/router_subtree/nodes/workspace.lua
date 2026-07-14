-- Entry node for the workspace subtree
local M = {}

M.workspace = {
  title = "Workspace",
  items = {
    { id = "project",  label = "Project — global element management", text = "project Project — global element management" },
    { id = "session",  label = "Session — named work slices",         text = "session Session — named work slices" },
    { id = "tab",      label = "Tab — current tab projects",          text = "tab Tab — current tab projects" },
    { id = "ops",      label = "Workspace ops — tabs container",      text = "ops Workspace ops — tabs container" },
    { id = "search",   label = "Search — cross-project search",       text = "search Search — cross-project search" },
  },
  child_prefix = "workspace_",
  on_confirm = function(item) return "workspace_" .. item.id end,
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

return M
