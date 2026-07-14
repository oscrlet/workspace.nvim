local M = {}

local function snacks()
  return _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
end

--- Ensure an item has a non-empty `text` field. Idempotent.
--- Backfills from item.label, then item.name, then item.id, else "".
---@param item table|any
---@return table|any
function M.normalize_item(item)
  if type(item) ~= "table" then return item end
  if item.text == nil or item.text == "" then
    item.text = item.label or item.name or item.id or ""
  end
  return item
end

--- Build a Snacks picker `format` callback that always returns nested rows
--- of the shape `{ {str, hl}, {str, hl}, ... }`.
---
--- spec: list of segments. Each segment is `{ key_or_fn, hl, opts? }` where:
---   * `key_or_fn` is either a string field name (value = `tostring(item[key] or "")`)
---     or a function `(item) -> string`.
---   * `hl` is the highlight group (defaults to "Normal").
---   * `opts` is optional. Supported keys:
---       - `width = N` -> left-pad value to width N (string.format "%-Ns").
---@param spec table
---@return fun(item: any): table
function M.make_format(spec)
  return function(item)
    local row = {}
    for _, seg in ipairs(spec) do
      local key_or_fn, hl, opts = seg[1], seg[2], seg[3]
      local val
      if type(key_or_fn) == "function" then
        local ok, result = pcall(key_or_fn, item)
        val = ok and result or ""
        if val == nil then val = "" end
        val = tostring(val)
      else
        val = tostring((type(item) == "table" and item[key_or_fn]) or "")
      end
      if opts and opts.width then
        val = string.format("%-" .. tonumber(opts.width) .. "s", val)
      end
      row[#row + 1] = { val, hl or "Normal" }
    end
    return row
  end
end

function M.project_picker(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
    return
  end
  local registry = require("workspace.project")
  local items = {}
  for _, p in ipairs(registry.list()) do
    table.insert(items, M.normalize_item({
      id = p.id,
      name = p.name or p.id,
      root = p.root,
      meta = p.meta,
      text = (p.name or p.id) .. " " .. p.root,
    }))
  end
  S.picker.pick({
    title = opts.title or "Projects",
    items = items,
    format = M.make_format({
      { "name", "SnacksPickerLabel", { width = 24 } },
      { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
    }),
    preview = M.project_preview,
    actions = {
      confirm = function(picker, it)
        pcall(picker.close, picker)
        if not it then return end
        if opts.on_select then
          opts.on_select(it)
        else
          vim.cmd("tcd " .. vim.fn.fnameescape(it.root))
        end
      end,
    },
  })
end

--- Snacks previewer for a project item: renders project_tree(item.root).
--- Defensive: nil item / missing root -> single fallback line, never errors.
---@param ctx table snacks.picker.preview.ctx
function M.project_preview(ctx)
  local item = ctx and ctx.item
  local lines
  if not item or not item.root or item.root == "" then
    lines = { "(no root)" }
  else
    local ok, result = pcall(require("workspace.ui.preview").project_tree, item.root)
    if ok and type(result) == "table" and #result > 0 then
      lines = result
    else
      lines = { "(unable to preview)" }
    end
  end
  if ctx and ctx.preview then
    pcall(function() ctx.preview:reset() end)
    pcall(function() ctx.preview:set_lines(lines) end)
  end
  return lines
end

--- Snacks previewer for a session item: renders session_tree(item.name).
--- Defensive: nil item / missing name -> single fallback line, never errors.
---@param ctx table snacks.picker.preview.ctx
function M.session_preview(ctx)
  local item = ctx and ctx.item
  local lines
  if not item or not item.name or item.name == "" then
    lines = { "(no session name)" }
  else
    local ok, result = pcall(require("workspace.ui.preview").session_tree, item.name)
    if ok and type(result) == "table" and #result > 0 then
      lines = result
    else
      lines = { "(unable to preview)" }
    end
  end
  if ctx and ctx.preview then
    pcall(function() ctx.preview:reset() end)
    pcall(function() ctx.preview:set_lines(lines) end)
  end
  return lines
end

function M.session_picker(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
    return
  end
  local session = require("workspace.session.api")
  local items = {}
  for _, item in ipairs(session.list()) do
    table.insert(items, M.normalize_item({
      name = item.name,
      text = item.name .. " (" .. item.tab_count .. " tabs, " .. item.project_count .. " projects)",
    }))
  end
  S.picker.pick({
    title = opts.title or "Sessions",
    items = items,
    format = M.make_format({
      { "text", "SnacksPickerLabel" },
    }),
    actions = {
      confirm = function(picker, it)
        pcall(picker.close, picker)
        if not it then return end
        if opts.on_select then
          opts.on_select(it)
        else
          local ok, err = session.load(it.name)
          if not ok then
            vim.notify("[workspace] load failed: " .. (err or "unknown"), vim.log.levels.ERROR)
          end
        end
      end,
    },
  })
end

function M.workspace_tabs_picker(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
    return
  end
  local workspace = require("workspace.workspace.api")
  local items = {}
  for i, tab in ipairs(workspace.tabs()) do
    local label = tab.label or ("Tab " .. i)
    table.insert(items, M.normalize_item({
      idx = i,
      label = label,
      text = label .. " (" .. #(tab.project_ids or {}) .. " projects)",
    }))
  end
  S.picker.pick({
    title = opts.title or "Workspace Tabs",
    items = items,
    format = M.make_format({
      { "text", "SnacksPickerLabel" },
    }),
    actions = {
      confirm = function(picker, it)
        pcall(picker.close, picker)
        if not it then return end
        if opts.on_select then
          opts.on_select(it)
        else
          workspace.switch_tab(it.idx)
        end
      end,
    },
  })
end

function M.tab_projects_picker(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
    return
  end
  local tab = require("workspace.tab.api")
  local items = {}
  for _, p in ipairs(tab.projects()) do
    table.insert(items, M.normalize_item({
      id = p.id,
      name = p.name or p.id,
      root = p.root,
      text = (p.name or p.id) .. " " .. p.root,
    }))
  end
  S.picker.pick({
    title = opts.title or "Tab Projects",
    items = items,
    format = M.make_format({
      { "name", "SnacksPickerLabel", { width = 24 } },
      { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
    }),
    actions = {
      confirm = function(picker, it)
        pcall(picker.close, picker)
        if not it then return end
        if opts.on_select then
          opts.on_select(it)
        else
          tab.switch_active(it.id)
        end
      end,
    },
  })
end

function M.workspace_projects_picker(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
    return
  end
  local session = require("workspace.session.api")
  local project = require("workspace.project")
  local seen = {}
  local items = {}
  for _, pid in ipairs(session.projects()) do
    if not seen[pid] then
      seen[pid] = true
      local p = project.get(pid)
      if p then
        table.insert(items, M.normalize_item({
          id = p.id,
          name = p.name or p.id,
          root = p.root,
          text = (p.name or p.id) .. " " .. p.root,
        }))
      end
    end
  end
  S.picker.pick({
    title = opts.title or "Workspace Projects",
    items = items,
    format = M.make_format({
      { "name", "SnacksPickerLabel", { width = 24 } },
      { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
    }),
    actions = {
      confirm = function(picker, it)
        pcall(picker.close, picker)
        if not it then return end
        if opts.on_select then
          opts.on_select(it)
        else
          session.focus_project(it.id)
        end
      end,
    },
  })
end

--- Deduplicate and realpath-ify directory list.
---@param dirs string[]
---@return string[]
local function normalize_dirs(dirs)
  if not dirs or #dirs == 0 then
    return { vim.fn.getcwd() }
  end
  local seen = {}
  local result = {}
  for _, d in ipairs(dirs) do
    local real = vim.uv.fs_realpath(d) or vim.fn.fnamemodify(d, ":p")
    if not seen[real] then
      seen[real] = true
      result[#result + 1] = real
    end
  end
  return result
end

--- Grep in current tab scope (tab project roots).
---@param opts table|nil
function M.grep_tab(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] Snacks.picker missing", vim.log.levels.WARN)
    return nil
  end
  local tab = require("workspace.tab.api")
  local roots = tab.scope_roots()
  local dirs = normalize_dirs(roots)
  local grep_opts = vim.tbl_extend("force", opts, { dirs = dirs })
  return S.picker.grep(grep_opts)
end

--- Find files in current tab scope.
---@param opts table|nil
function M.find_tab(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] Snacks.picker missing", vim.log.levels.WARN)
    return nil
  end
  local tab = require("workspace.tab.api")
  local roots = tab.scope_roots()
  local dirs = normalize_dirs(roots)
  local find_opts = vim.tbl_extend("force", opts, { dirs = dirs })
  return S.picker.files(find_opts)
end

--- List LSP workspace symbols (no dirs param — LSP scope).
---@param opts table|nil
function M.symbols_tab(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] Snacks.picker missing", vim.log.levels.WARN)
    return nil
  end
  return S.picker.lsp_workspace_symbols(opts)
end

--- Grep across all workspace projects.
---@param opts table|nil
function M.grep_workspace(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] Snacks.picker missing", vim.log.levels.WARN)
    return nil
  end
  local session = require("workspace.session.api")
  local project = require("workspace.project")
  local roots = {}
  for _, pid in ipairs(session.projects()) do
    local p = project.get(pid)
    if p and p.root then
      roots[#roots + 1] = p.root
    end
  end
  local dirs = normalize_dirs(roots)
  local grep_opts = vim.tbl_extend("force", opts, { dirs = dirs })
  return S.picker.grep(grep_opts)
end

--- Pick projects, then grep in their roots.
---@param opts table|nil
function M.scoped_grep_picker(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] Snacks.picker missing", vim.log.levels.WARN)
    return nil
  end
  local project = require("workspace.project")
  local items = {}
  for _, p in ipairs(project.list()) do
    table.insert(items, M.normalize_item({
      id = p.id,
      name = p.name or p.id,
      root = p.root,
      text = (p.name or p.id) .. " " .. p.root,
    }))
  end
  S.picker.pick({
    title = opts.title or "Select projects for grep",
    items = items,
    format = M.make_format({
      { "name", "SnacksPickerLabel", { width = 24 } },
      { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
    }),
    actions = {
      confirm = function(picker)
        local sel = (picker.selected and picker:selected({ fallback = true })) or {}
        if type(sel) ~= "table" or #sel == 0 then
          local cur = picker.current and picker:current()
          if cur then sel = { cur } end
        end
        if picker.close then picker:close() end
        if #sel == 0 then return end
        local roots = {}
        for _, item in ipairs(sel) do
          if item.root then roots[#roots + 1] = item.root end
        end
        local dirs = normalize_dirs(roots)
        local grep_opts = vim.tbl_extend("force", opts, { dirs = dirs })
        S.picker.grep(grep_opts)
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-a>"] = { "toggle_all", mode = { "i", "n" } },
        },
      },
    },
  })
end

--- Pick projects, then find files in their roots.
---@param opts table|nil
function M.scoped_find_picker(opts)
  opts = opts or {}
  local S = snacks()
  if not S or not S.picker then
    vim.notify("[workspace] Snacks.picker missing", vim.log.levels.WARN)
    return nil
  end
  local project = require("workspace.project")
  local items = {}
  for _, p in ipairs(project.list()) do
    table.insert(items, M.normalize_item({
      id = p.id,
      name = p.name or p.id,
      root = p.root,
      text = (p.name or p.id) .. " " .. p.root,
    }))
  end
  S.picker.pick({
    title = opts.title or "Select projects for find",
    items = items,
    format = M.make_format({
      { "name", "SnacksPickerLabel", { width = 24 } },
      { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
    }),
    actions = {
      confirm = function(picker)
        local sel = (picker.selected and picker:selected({ fallback = true })) or {}
        if type(sel) ~= "table" or #sel == 0 then
          local cur = picker.current and picker:current()
          if cur then sel = { cur } end
        end
        if picker.close then picker:close() end
        if #sel == 0 then return end
        local roots = {}
        for _, item in ipairs(sel) do
          if item.root then roots[#roots + 1] = item.root end
        end
        local dirs = normalize_dirs(roots)
        local find_opts = vim.tbl_extend("force", opts, { dirs = dirs })
        S.picker.files(find_opts)
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-a>"] = { "toggle_all", mode = { "i", "n" } },
        },
      },
    },
  })
end

return M
