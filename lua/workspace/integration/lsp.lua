--- workspace/integration/lsp.lua
--- LSP workspace folders sync: union of all tab project roots.
local M = {}

local function tab_api()
  return require("workspace.tab.api")
end

local function tab_state()
  return require("workspace.tab.state")
end

local function project_mod()
  return require("workspace.project")
end

--- Collect all roots from all tabs; deduplicate via realpath.
---@return string[]
function M.union_roots()
  local seen = {}
  local roots = {}

  -- Iterate all tabs
  for _, tab in ipairs(tab_state().all()) do
    -- Add tab's cwd if present
    if tab.cwd and tab.cwd ~= "" then
      local real = vim.uv.fs_realpath(tab.cwd) or tab.cwd
      if not seen[real] then
        seen[real] = true
        table.insert(roots, real)
      end
    end

    -- Add each project root
    for _, proj_id in ipairs(tab.project_ids or {}) do
      local proj = project_mod().get(proj_id)
      if proj and proj.root and proj.root ~= "" then
        local real = vim.uv.fs_realpath(proj.root) or proj.root
        if not seen[real] then
          seen[real] = true
          table.insert(roots, real)
        end
      end
    end
  end

  return roots
end

--- Compute diff between current and new workspace folders.
--- Returns { added: string[], removed: string[] }
---@param current table|nil
---@param new string[]
---@return table
local function compute_diff(current, new)
  local curr_set = {}
  if current then
    for _, uri in ipairs(current) do
      if type(uri) == "table" and uri.name then
        curr_set[uri.name] = true
      elseif type(uri) == "string" then
        curr_set[uri] = true
      end
    end
  end

  local new_set = {}
  for _, path in ipairs(new) do
    new_set[path] = true
  end

  local added = {}
  for path, _ in pairs(new_set) do
    if not curr_set[path] then
      table.insert(added, path)
    end
  end

  local removed = {}
  for path, _ in pairs(curr_set) do
    if not new_set[path] then
      table.insert(removed, path)
    end
  end

  return { added = added, removed = removed }
end

--- Sync workspace folders for a single LSP client.
---@param client table LSP client
---@param new_roots string[]
local function sync_client(client, new_roots)
  if not client then return end

  local diff = compute_diff(client.workspace_folders, new_roots)

  -- Nothing to do if no changes
  if #diff.added == 0 and #diff.removed == 0 then
    return
  end

  -- Build didChangeWorkspaceFolders event payload
  local added = {}
  for _, path in ipairs(diff.added) do
    table.insert(added, { uri = vim.uri_from_fname(path), name = path })
  end

  local removed = {}
  for _, path in ipairs(diff.removed) do
    table.insert(removed, { uri = vim.uri_from_fname(path), name = path })
  end

  -- Send workspace/didChangeWorkspaceFolders notification
  if client.notify then
    client:notify("workspace/didChangeWorkspaceFolders", {
      event = {
        added = added,
        removed = removed,
      }
    })
  end

  -- Replace client.workspace_folders with the new set.
  -- The reset is unconditional only here, on the path that is about
  -- to overwrite folders; early returns above leave existing folders intact.
  client.workspace_folders = {}
  for _, path in ipairs(new_roots) do
    table.insert(client.workspace_folders, {
      uri = vim.uri_from_fname(path),
      name = path,
    })
  end
end

--- Refresh workspace folders for all active LSP clients.
function M.refresh_workspace_folders()
  local cfg = require("workspace.config").get()
  local excluded = cfg.lsp and cfg.lsp.excluded_clients or {}
  local excluded_set = {}
  for _, name in ipairs(excluded) do
    excluded_set[name] = true
  end

  local new_roots = M.union_roots()

  -- Get all active LSP clients
  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do
    if not excluded_set[client.name] then
      sync_client(client, new_roots)
    end
  end
end

--- Inject workspace folders into LSP client on attach.
---@param client table LSP client
---@param bufnr number buffer number
function M.on_lsp_attach(client, bufnr)
  if not client then return end

  local cfg = require("workspace.config").get()
  local excluded = cfg.lsp and cfg.lsp.excluded_clients or {}
  local excluded_set = {}
  for _, name in ipairs(excluded) do
    excluded_set[name] = true
  end

  if excluded_set[client.name] then
    return
  end

  -- Initialize workspace_folders if not present
  if not client.workspace_folders then
    client.workspace_folders = {}
  end

  -- Set initial workspace folders
  local new_roots = M.union_roots()
  for _, path in ipairs(new_roots) do
    table.insert(client.workspace_folders, {
      uri = vim.uri_from_fname(path),
      name = path,
    })
  end
end

--- Setup LSP integration: register autocmds.
---@param cfg table workspace.lsp config section
function M.setup(cfg)
  local group = vim.api.nvim_create_augroup("workspace.lsp", { clear = true })

  -- Listen to tab project changes
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "WorkspaceTabProjectAdded",
    callback = function()
      M.refresh_workspace_folders()
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "WorkspaceTabProjectRemoved",
    callback = function()
      M.refresh_workspace_folders()
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "WorkspaceSessionLoaded",
    callback = function()
      M.refresh_workspace_folders()
    end,
  })

  -- Listen to LSP attach
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      M.on_lsp_attach(client, args.buf)
    end,
  })
end

return M
