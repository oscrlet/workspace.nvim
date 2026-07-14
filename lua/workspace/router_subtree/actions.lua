-- Shared action definitions reusable across workspace nodes
-- Each action is a table: { key, desc, run, after }
local M = {}

--- Standard delete/remove action factory.
---@param run_fn fun(item:table)
---@return table
function M.delete_action(run_fn)
  return {
    key   = "<C-d>",
    desc  = "Delete",
    run   = run_fn,
    after = "stay",
  }
end

--- Standard rename action factory.
---@param prompt string
---@param rename_fn fun(item:table, new_name:string)
---@return table
function M.rename_action(prompt, rename_fn)
  return {
    key  = "<C-r>",
    desc = "Rename",
    run  = function(item)
      vim.ui.input({ prompt = prompt or "New name: " }, function(name)
        if name then rename_fn(item, name) end
      end)
    end,
    after = "stay",
  }
end

--- Standard yank path action factory.
---@param path_fn fun(item:table):string
---@return table
function M.yank_action(path_fn)
  return {
    key  = "<C-y>",
    desc = "Yank path",
    run  = function(item) vim.fn.setreg("+", path_fn(item)) end,
    after = "stay",
  }
end

-- Common shared action tables keyed by semantic name:
M.common = {
  delete = {
    key   = "<C-d>",
    desc  = "Delete / Remove",
    after = "stay",
  },
  rename = {
    key   = "<C-r>",
    desc  = "Rename",
    after = "stay",
  },
  yank = {
    key   = "<C-y>",
    desc  = "Yank path",
    after = "stay",
  },
}

return M
