-- Session sub-tree nodes (§3.4)
local M = {}

M.workspace_session = {
  title = "Session Actions",
  items = {
    { id = "list",   label = "List & Load",          text = "list List & Load" },
    { id = "save",   label = "Save current as...",   text = "save Save current as..." },
    { id = "delete", label = "Delete...",             text = "delete Delete..." },
    { id = "info",   label = "Current session info", text = "info Current session info" },
  },
  child_prefix = "workspace_session_",
  on_confirm = function(item) return "workspace_session_" .. item.id end,
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_session_list = {
  title = "Sessions",
  items = function()
    local result = {}
    for _, s in ipairs(require("workspace.session").list()) do
      result[#result + 1] = vim.tbl_extend("force", s, {
        text = s.name .. " (" .. (s.tab_count or 0) .. " tabs, " .. (s.project_count or 0) .. " projects)",
      })
    end
    return result
  end,
  preview = require("workspace.router_subtree.preview").session,
  -- Picking a session from the list IS the confirmation — load directly
  -- (force = true) instead of opening a nested Load/Cancel select.
  on_confirm = function(item)
    require("workspace.session").load(item.name, { force = true })
    return nil
  end,
  actions = {
    { key = "<CR>",  desc = "Load session",
      run = function(item) require("workspace.session").load(item.name, { force = true }) end,
      after = "close" },
    { key = "<C-d>", desc = "Delete",
      run = function(item) require("workspace.session").delete(item.name) end,
      after = "stay" },
    { key = "<C-r>", desc = "Rename",
      run = function(item)
        vim.ui.input({ prompt = "New name: " }, function(name)
          if name then require("workspace.session").rename(item.name, name) end
        end)
      end, after = "stay" },
    { key = "<C-y>", desc = "Yank session JSON path",
      run = function(item)
        vim.fn.setreg("+", require("workspace.session").path(item.name))
      end, after = "stay" },
  },
  -- F11: list with preview.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_session_save = {
  title = "Save Current Session",
  items = function()
    local result = {}
    for _, s in ipairs(require("workspace.session").save_candidates()) do
      result[#result + 1] = vim.tbl_extend("force", s, {
        text = s.name .. (s.current and " (current)" or ""),
      })
    end
    return result
  end,
  on_confirm = function(item)
    require("workspace.session").save(item.name)
    return nil
  end,
  actions = {
    { key = "<C-i>", desc = "Type new name",
      run = function()
        vim.ui.input({ prompt = "Session name: " }, function(n)
          if n then require("workspace.session").save(n) end
        end)
      end, after = "close" },
  },
  -- F11: small action menu.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_session_delete = {
  title = "Delete Session",
  items = function()
    local result = {}
    for _, s in ipairs(require("workspace.session").list()) do
      result[#result + 1] = vim.tbl_extend("force", s, {
        text = s.name .. " (" .. (s.tab_count or 0) .. " tabs, " .. (s.project_count or 0) .. " projects)",
      })
    end
    return result
  end,
  on_confirm = function(item)
    require("workspace.session").delete(item.name)
    return nil
  end,
  -- F11: list of sessions to delete.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_session_info = {
  title = "Current Session Info",
  items = function()
    local info = require("workspace.session").current_info()
    if not info then return {} end
    return { vim.tbl_extend("force", info, {
      text = info.name .. " " .. (info.path or ""),
    }) }
  end,
  on_confirm = function(_item) return nil end,
  -- F11: single-row info node.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

return M
