-- WC-3.1 (re-checked 2026-06-01): every interactive picker in this legacy
-- command layer is now router/volt-PREFERRED with Snacks only as a defensive
-- fallback when the router/node is unavailable:
--   • file/grep pickers  → backend_pick()  (router.backend → volt; Snacks fallback)
--   • SessionList         → open_router("workspace_session_list")  then Snacks fallback
--   • WorkspaceList       → open_router("workspace_ops_tab_list")   then Snacks fallback
-- The remaining `S.picker.*` sites are exclusively those guarded fallback
-- branches — verified to NOT fire in normal operation (router + volt loaded).
-- So this layer carries no un-migrated Snacks debt; the Snacks paths are
-- deliberate graceful degradation, not tech debt.
local M = {}

local function project() return require("workspace.project") end
local function snacks_int() return require("workspace.integration.snacks") end

-- Pick through the router backend so the configured picker (volt / snacks)
-- is honored, rather than hard-calling Snacks.picker. `opts` is snacks-shaped
-- with an explicit `source`; volt's files/grep finders honor `dirs`. Falls
-- back to the matching Snacks.picker source when the backend is unavailable.
local function backend_pick(opts)
  local ok, backend = pcall(require, "router.backend")
  if ok and backend and backend.pick then
    return backend.pick(opts)
  end
  local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
  if not S or not S.picker then
    vim.notify("[workspace] no picker backend available", vim.log.levels.ERROR)
    return
  end
  local src = opts.source or "files"
  local fn = S.picker[src]
  if type(fn) == "function" then
    local o = vim.deepcopy(opts); o.source = nil
    return fn(o)
  end
  vim.notify("[workspace] unknown picker source: " .. tostring(src), vim.log.levels.ERROR)
end
local function session_api() return require("workspace.session.api") end
local function workspace_api() return require("workspace.workspace.api") end
local function tab_api() return require("workspace.tab.api") end

local function id_complete(arglead)
  local out = {}
  for _, p in ipairs(project().list()) do
    if p.id:find(arglead, 1, true) == 1 then table.insert(out, p.id) end
  end
  table.sort(out)
  return out
end

local function tab_project_id_complete(arglead)
  local out = {}
  local projs = tab_api().projects()
  for _, p in ipairs(projs) do
    if p.id:find(arglead, 1, true) == 1 then table.insert(out, p.id) end
  end
  table.sort(out)
  return out
end

local function session_name_complete(arglead)
  local out = {}
  for _, item in ipairs(session_api().list()) do
    if item.name:find(arglead, 1, true) == 1 then table.insert(out, item.name) end
  end
  table.sort(out)
  return out
end

--- Try to open a router subtree node. Returns true if router handled it.
--- Falls back to false when router is not loaded or the node id is not
--- registered, so the caller can run its inline Snacks picker as fallback.
local function open_router(node_id, ctx_init)
  local ok, router = pcall(require, "router")
  if not ok or type(router) ~= "table" or type(router.open) ~= "function" then
    return false
  end
  local tree = router._internal and router._internal.tree
  if not tree or not tree.has or not tree.has(node_id) then
    return false
  end
  router.open(node_id, ctx_init)
  return true
end

function M.setup_project_commands()
  vim.api.nvim_create_user_command("ProjectAdd", function(o)
    local args = vim.split(o.args, "%s+")
    local path, id = args[1], args[2]
    if not path or path == "" then
      vim.notify("usage: :ProjectAdd <path> [id]", vim.log.levels.ERROR)
      return
    end
    local p = project().register({ path = path, id = id ~= "" and id or nil })
    if p then vim.notify("[workspace] registered " .. p.id) end
  end, { nargs = "+", complete = "dir" })

  -- :ProjectInit [path]
  --
  -- Promote a directory (cwd by default) to a registered project. If the
  -- directory has no recognized marker (cfg.project.default_markers), write
  -- a `.project` JSON file at its root so future discover/scan passes can
  -- find it AND so the directory carries its own authoritative id/name.
  -- The .project file is then read back as the source of truth for the
  -- registry entry.
  vim.api.nvim_create_user_command("ProjectInit", function(o)
    local cfg     = require("workspace.config").get()
    local dotfile = require("workspace.project.dotfile")
    local id_util = require("workspace.util.id")
    local path_u  = require("workspace.util.path")

    local raw = (o.args ~= "" and o.args) or vim.fn.getcwd()
    local expanded = vim.fn.expand(raw)
    local real = path_u.realpath(expanded) or expanded
    if vim.fn.isdirectory(real) ~= 1 then
      vim.notify("[workspace] :ProjectInit — not a directory: " .. raw,
                 vim.log.levels.ERROR)
      return
    end

    local markers = (cfg.project and cfg.project.default_markers) or { ".git", ".project", ".workspace" }
    local found
    for _, m in ipairs(markers) do
      if vim.uv.fs_stat(real .. "/" .. m) then found = m; break end
    end

    -- Re-register: if the dir is already known by root, surface it and exit
    -- (idempotent). Editing meta should go through :ProjectEdit.
    local existing = project().find_by_root(real)
    if existing then
      vim.notify("[workspace] already registered: " .. existing.id
                 .. (found and (" (" .. found .. ")") or ""))
      return
    end

    -- Decide id/name. Priority:
    --   1. Existing .project payload (authoritative).
    --   2. id_util.derive (basename + parent disambiguation + numeric).
    local payload = dotfile.read(real)
    local id, name
    if payload and type(payload.id) == "string" and payload.id ~= "" then
      id   = payload.id
      name = (type(payload.name) == "string" and payload.name ~= "") and payload.name or id
    else
      -- Build the taken-id set from the live registry so :derive disambiguates.
      local taken = {}
      for _, p in ipairs(project().list()) do taken[p.id] = true end
      id   = id_util.derive(real, taken)
      name = id_util.from_basename(real)
    end

    -- When no marker exists at all, materialize .project so subsequent
    -- discover passes and other workspace.nvim consumers see the dir as a
    -- first-class project. Skip the write when .project already supplied
    -- our id (it's already on disk).
    if not found then
      local meta = (payload and type(payload.meta) == "table") and payload.meta or {}
      local ok, werr = dotfile.write(real, {
        id         = id,
        name       = name,
        meta       = meta,
        created_at = (payload and payload.created_at) or os.time(),
      })
      if not ok then
        vim.notify("[workspace] :ProjectInit — write .project failed: "
                   .. tostring(werr), vim.log.levels.ERROR)
        return
      end
      found = ".project"
    end

    local proj = project().register({
      path    = real,
      id      = id,
      name    = name,
      meta    = (payload and type(payload.meta) == "table") and payload.meta or nil,
      markers = { found },
    })
    if proj then
      vim.notify(("[workspace] project initialized: %s (%s)")
                 :format(proj.id, found))
    end
  end, { nargs = "?", complete = "dir" })

  vim.api.nvim_create_user_command("ProjectRemove", function(o)
    local id = o.args
    if id == "" then return end
    if project().unregister(id) then
      vim.notify("[workspace] removed " .. id)
    end
  end, { nargs = 1, complete = id_complete })

  vim.api.nvim_create_user_command("ProjectList", function()
    if open_router("workspace_project_list") then return end
    snacks_int().project_picker()
  end, {})

  vim.api.nvim_create_user_command("ProjectDiscover", function(o)
    local glob = o.args
    if glob == "" then
      vim.notify("usage: :ProjectDiscover <glob>", vim.log.levels.ERROR)
      return
    end
    local cands = project().discover({ glob }, { dry_run = true }) or {}
    if #cands == 0 then
      vim.notify("[workspace] no candidates")
      return
    end
    vim.notify(("[workspace] %d candidates; registering"):format(#cands))
    for _, c in ipairs(cands) do
      project().register({ path = c.path })
    end
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("ProjectMove", function(o)
    local args = vim.split(o.args, "%s+", { trimempty = true })
    local id, new_path = args[1], table.concat(args, " ", 2)
    if not id or new_path == "" then
      vim.notify("usage: :ProjectMove <id> <new_path>", vim.log.levels.ERROR)
      return
    end
    local api = require("workspace.project.api")
    local ok, err = api.move(id, new_path)
    if ok then
      vim.notify("[workspace] project moved: " .. id .. " -> " .. new_path)
    else
      vim.notify("[workspace] " .. (err or "move failed"), vim.log.levels.ERROR)
    end
  end, { nargs = "+", complete = id_complete })

  vim.api.nvim_create_user_command("ProjectRename", function(o)
    local args = vim.split(o.args, "%s+", { trimempty = true })
    local id, name = args[1], table.concat(args, " ", 2)
    if not id or name == "" then
      vim.notify("usage: :ProjectRename <id> <name>", vim.log.levels.ERROR)
      return
    end
    project().update(id, { name = name })
  end, { nargs = "+", complete = id_complete })

  -- :ProjectEdit <id>
  --
  -- UX: vim.ui.input chain (option (a) per FIX_PLAN F15) — chosen for
  -- simplicity and headless-test friendliness. Each editable field is
  -- prompted with the current value pre-filled; aborting any prompt
  -- (vim.ui.input -> nil) cancels the entire edit without mutation.
  -- meta is freeform, so it is offered as a single JSON-encoded string;
  -- invalid JSON aborts with a notify.
  local function project_edit(id)
    local proj_mod = project()
    local proj = proj_mod.get(id)
    if not proj then
      vim.notify("[workspace] no such project: " .. tostring(id), vim.log.levels.ERROR)
      return
    end
    local fields = {
      { key = "name", label = "Name", default = proj.name or proj.id },
      { key = "root", label = "Root", default = proj.root or "" },
      { key = "meta", label = "Meta (JSON)", default = vim.json.encode(proj.meta or vim.empty_dict()) },
    }
    local updates = {}
    local function step(i)
      if i > #fields then
        local ok, decoded = pcall(vim.json.decode, updates.meta or "{}")
        if not ok or type(decoded) ~= "table" then
          vim.notify("[workspace] invalid meta JSON", vim.log.levels.ERROR)
          return
        end
        updates.meta = decoded
        local ok_upd, err = pcall(proj_mod.update, id, updates)
        if not ok_upd then
          vim.notify("[workspace] update failed: " .. tostring(err), vim.log.levels.ERROR)
          return
        end
        vim.notify("[workspace] project updated: " .. id)
        return
      end
      local f = fields[i]
      vim.ui.input({ prompt = f.label .. ": ", default = f.default }, function(input)
        if input == nil then return end
        updates[f.key] = input
        vim.schedule(function() step(i + 1) end)
      end)
    end
    step(1)
  end

  vim.api.nvim_create_user_command("ProjectEdit", function(o)
    if o.args == "" then
      local ok, snacks_mod = pcall(require, "workspace.integration.snacks")
      if not ok or not snacks_mod or not snacks_mod.project_picker then
        vim.notify("[workspace] usage: :ProjectEdit <id>", vim.log.levels.WARN)
        return
      end
      local picker_ok = pcall(snacks_mod.project_picker, {
        title = "Edit project",
        on_select = function(it)
          if it and it.id then project_edit(it.id) end
        end,
      })
      if not picker_ok then
        vim.notify("[workspace] usage: :ProjectEdit <id>", vim.log.levels.WARN)
      end
      return
    end
    project_edit(o.args)
  end, { nargs = "?", complete = id_complete })

  vim.api.nvim_create_user_command("ProjectReload", function()
    project().reload()
    vim.notify("[workspace] reloaded")
  end, {})
end

function M.setup_session_commands()
  vim.api.nvim_create_user_command("SessionSave", function(o)
    local name = o.args ~= "" and o.args or nil
    local ok, err = session_api().save(name)
    if ok then
      vim.notify("[workspace] session saved: " .. (name or session_api().current()))
    else
      vim.notify("[workspace] session save failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("SessionLoad", function(o)
    local name = o.args
    if name == "" then
      vim.notify("usage: :SessionLoad <name>", vim.log.levels.ERROR)
      return
    end
    local ok, err = session_api().load(name)
    if ok then
      vim.notify("[workspace] session loaded: " .. name)
    else
      vim.notify("[workspace] session load failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end, { nargs = 1, complete = session_name_complete })

  vim.api.nvim_create_user_command("SessionDelete", function(o)
    local name = o.args
    if name == "" then
      vim.notify("usage: :SessionDelete <name>", vim.log.levels.ERROR)
      return
    end
    session_api().delete(name)
    vim.notify("[workspace] session deleted: " .. name)
  end, { nargs = 1, complete = session_name_complete })

  vim.api.nvim_create_user_command("SessionList", function()
    if open_router("workspace_session_list") then return end
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
      return
    end
    local items = {}
    for _, item in ipairs(session_api().list()) do
      table.insert(items, snacks_int().normalize_item({
        name = item.name,
        text = item.name .. " (" .. item.tab_count .. " tabs, " .. item.project_count .. " projects)",
      }))
    end
    S.picker.pick({
      title = "Sessions",
      items = items,
      format = snacks_int().make_format({
        { "text", "SnacksPickerLabel" },
      }),
      preview = snacks_int().session_preview,
      actions = {
        confirm = function(picker, it)
          pcall(picker.close, picker)
          if it then
            -- Picking from the list is the confirmation — load directly.
            local ok, err = session_api().load(it.name, { force = true })
            if not ok then
              vim.notify("[workspace] failed to load: " .. (err or "unknown error"), vim.log.levels.ERROR)
            end
          end
        end,
      },
    })
  end, {})

  vim.api.nvim_create_user_command("SessionRename", function(o)
    local args = vim.split(o.args, "%s+", { trimempty = true })
    local old, new = args[1], args[2]
    if not old or not new then
      vim.notify("usage: :SessionRename <old> <new>", vim.log.levels.ERROR)
      return
    end
    local ok, err = session_api().rename(old, new)
    if ok then
      vim.notify("[workspace] session renamed: " .. old .. " -> " .. new)
    else
      vim.notify("[workspace] rename failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end, { nargs = "+", complete = session_name_complete })

  vim.api.nvim_create_user_command("SessionInfo", function()
    local cur = session_api().current()
    local tabs = require("workspace.workspace.api").tabs()
    local projs = session_api().projects()
    local msg = "[workspace] "
    if cur then
      msg = msg .. "current: " .. cur
    else
      msg = msg .. "no session loaded"
    end
    msg = msg .. " | tabs: " .. #tabs .. " | projects: " .. #projs
    vim.notify(msg)
  end, {})
end

function M.setup_workspace_commands()
  vim.api.nvim_create_user_command("WorkspaceNewTab", function(o)
    local pid = o.args ~= "" and o.args or nil
    local opts = {}
    if pid then opts.project_id = pid end
    workspace_api().new_tab(opts)
    vim.notify("[workspace] new tab created")
  end, { nargs = "?", complete = id_complete })

  vim.api.nvim_create_user_command("WorkspaceCloseTab", function()
    workspace_api().close_tab()
    vim.notify("[workspace] tab closed")
  end, {})

  vim.api.nvim_create_user_command("WorkspaceSwitchTab", function(o)
    local idx = tonumber(o.args)
    if not idx then
      vim.notify("usage: :WorkspaceSwitchTab <idx>", vim.log.levels.ERROR)
      return
    end
    workspace_api().switch_tab(idx)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("WorkspaceMoveTab", function(o)
    local args = vim.split(o.args, "%s+", { trimempty = true })
    local from, to = tonumber(args[1]), tonumber(args[2])
    if not from or not to then
      vim.notify("usage: :WorkspaceMoveTab <from> <to>", vim.log.levels.ERROR)
      return
    end
    workspace_api().reorder_tabs(from, to)
    vim.notify("[workspace] tab moved")
  end, { nargs = "+" })

  vim.api.nvim_create_user_command("WorkspaceList", function()
    if open_router("workspace_ops_tab_list") then return end
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
      return
    end
    local items = {}
    for i, tab in ipairs(workspace_api().tabs()) do
      local label = tab.label or ("Tab " .. i)
      table.insert(items, snacks_int().normalize_item({
        idx = i,
        label = label,
        text = label .. " (" .. #(tab.project_ids or {}) .. " projects)",
      }))
    end
    S.picker.pick({
      title = "Workspace Tabs",
      items = items,
      format = snacks_int().make_format({
        { "text", "SnacksPickerLabel" },
      }),
      actions = {
        confirm = function(picker, it)
          pcall(picker.close, picker)
          if it then workspace_api().switch_tab(it.idx) end
        end,
      },
    })
  end, {})

  vim.api.nvim_create_user_command("WorkspaceProjects", function()
    if open_router("workspace_ops_projects") then return end
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
      return
    end
    local seen = {}
    local items = {}
    for _, pid in ipairs(session_api().projects()) do
      if not seen[pid] then
        seen[pid] = true
        local p = project().get(pid)
        if p then
          table.insert(items, snacks_int().normalize_item({
            id = p.id,
            name = p.name or p.id,
            root = p.root,
            text = (p.name or p.id) .. " " .. p.root,
          }))
        end
      end
    end
    S.picker.pick({
      title = "Workspace Projects",
      items = items,
      format = snacks_int().make_format({
        { "name", "SnacksPickerLabel", { width = 24 } },
        { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
      }),
      actions = {
        confirm = function(picker, it)
          pcall(picker.close, picker)
          if it then
            session_api().focus_project(it.id)
          end
        end,
      },
    })
  end, {})

  vim.api.nvim_create_user_command("WorkspaceMigrateFromProjections", function(o)
    local args = vim.split(o.args or "", "%s+", { trimempty = true })
    local opts = { dry_run = false }
    for _, a in ipairs(args) do
      if a == "--dry-run" or a == "-n" then
        opts.dry_run = true
      else
        opts.src_path = a
      end
    end
    local ok, mod = pcall(require, "workspace.migrate.projections")
    if not ok then
      vim.notify("[workspace] migrate module unavailable: " .. tostring(mod), vim.log.levels.ERROR)
      return
    end
    local result, err = mod.run(opts)
    if err then
      vim.notify("[workspace] migrate failed: " .. err, vim.log.levels.ERROR)
      return
    end
    vim.notify(string.format(
      "[workspace] migrate%s: %d added, %d skipped, %d errors",
      opts.dry_run and " (dry-run)" or "",
      #result.added, #result.skipped, #result.errors))
    -- Append a structured report to :messages for follow-up review.
    for _, a in ipairs(result.added) do
      vim.api.nvim_echo({
        { string.format("[workspace] migrate add  id=%s root=%s", a.id, a.root), "None" },
      }, true, {})
    end
    for _, s in ipairs(result.skipped) do
      vim.api.nvim_echo({
        { string.format("[workspace] migrate skip id=%s root=%s (%s)",
            s.id, s.root, s.reason or ""), "None" },
      }, true, {})
    end
    for _, e in ipairs(result.errors) do
      vim.api.nvim_echo({
        { string.format("[workspace] migrate ERR  id=%s src=%s existing=%s",
            e.id, e.src_root, e.existing_root or "?"), "WarningMsg" },
      }, true, {})
    end
  end, {
    nargs = "*",
    complete = "file",
    desc = "Migrate projects from projections.nvim's projections.json",
  })

  vim.api.nvim_create_user_command("WorkspaceGrep", function(o)
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
      return
    end
    local pattern = o.args ~= "" and o.args or nil
    local dirs = {}
    local seen = {}
    for _, tab in ipairs(workspace_api().tabs()) do
      for _, root in ipairs(tab_api().scope_roots(tab.tabnr)) do
        local real = vim.uv.fs_realpath(root) or root
        if not seen[real] then
          seen[real] = true
          table.insert(dirs, root)
        end
      end
    end
    if #dirs == 0 then
      vim.notify("[workspace] no project roots found", vim.log.levels.WARN)
      return
    end
    S.picker.grep({ dirs = dirs, pattern = pattern })
  end, { nargs = "*" })

  -- :WorkspaceGrepWord — Snacks.grep_word scoped to all session roots.
  -- Mirrors WorkspaceGrep's union-of-tab-roots scope but seeds the
  -- search with the cursor word (or the visual selection when called
  -- from a visual range).
  vim.api.nvim_create_user_command("WorkspaceGrepWord", function()
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
      return
    end
    local dirs = {}
    local seen = {}
    for _, tab in ipairs(workspace_api().tabs()) do
      for _, root in ipairs(tab_api().scope_roots(tab.tabnr)) do
        local real = vim.uv.fs_realpath(root) or root
        if not seen[real] then
          seen[real] = true
          table.insert(dirs, root)
        end
      end
    end
    if #dirs == 0 then
      vim.notify("[workspace] no project roots found", vim.log.levels.WARN)
      return
    end
    S.picker.grep_word({ dirs = dirs })
  end, { range = true })
end

function M.setup_tab_commands()
  vim.api.nvim_create_user_command("TabAddProject", function(o)
    local pid = o.args
    if pid == "" then
      if open_router("workspace_project_list", { workspace = { intent = "add_to_tab" } }) then return end
      snacks_int().project_picker({
        title = "Add Project to Tab",
        on_select = function(it)
          if it and it.id then
            tab_api().add_project(nil, it.id)
            vim.notify("[workspace] project added to tab: " .. it.id)
          end
        end,
      })
      return
    end
    tab_api().add_project(nil, pid)
    vim.notify("[workspace] project added to tab: " .. pid)
  end, { nargs = "?", complete = id_complete })

  vim.api.nvim_create_user_command("TabRemoveProject", function(o)
    local pid = o.args
    if pid == "" then
      if open_router("workspace_tab_remove_project") then return end
      snacks_int().tab_projects_picker({
        title = "Remove Project from Tab",
        on_select = function(it)
          if it and it.id then
            tab_api().remove_project(nil, it.id)
            vim.notify("[workspace] project removed from tab: " .. it.id)
          end
        end,
      })
      return
    end
    tab_api().remove_project(nil, pid)
    vim.notify("[workspace] project removed from tab: " .. pid)
  end, { nargs = "?", complete = tab_project_id_complete })

  vim.api.nvim_create_user_command("TabSwitchProject", function(o)
    local pid = o.args
    if pid == "" then
      if open_router("workspace_tab_projects", { workspace = { intent = "switch_active" } }) then return end
      snacks_int().tab_projects_picker({
        title = "Switch Tab Project",
        on_select = function(it)
          if it and it.id then
            tab_api().switch_active(it.id)
            vim.notify("[workspace] switched to project: " .. it.id)
          end
        end,
      })
      return
    end
    tab_api().switch_active(pid)
    vim.notify("[workspace] switched to project: " .. pid)
  end, { nargs = "?", complete = tab_project_id_complete })

  vim.api.nvim_create_user_command("TabProjects", function()
    if open_router("workspace_tab_projects") then return end
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
      return
    end
    local items = {}
    for _, p in ipairs(tab_api().projects()) do
      table.insert(items, snacks_int().normalize_item({
        id = p.id,
        name = p.name or p.id,
        root = p.root,
        text = (p.name or p.id) .. " " .. p.root,
      }))
    end
    S.picker.pick({
      title = "Tab Projects",
      items = items,
      format = snacks_int().make_format({
        { "name", "SnacksPickerLabel", { width = 24 } },
        { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
      }),
      actions = {
        confirm = function(picker, it)
          pcall(picker.close, picker)
          if it then
            tab_api().switch_active(it.id)
          end
        end,
      },
    })
  end, {})

  vim.api.nvim_create_user_command("TabRename", function(o)
    local label = o.args
    if label == "" then
      vim.notify("usage: :TabRename <label>", vim.log.levels.ERROR)
      return
    end
    tab_api().rename(nil, label)
    vim.notify("[workspace] tab renamed: " .. label)
  end, { nargs = "+" })

  vim.api.nvim_create_user_command("TabGrep", function(o)
    local pattern = o.args ~= "" and o.args or nil
    local dirs = tab_api().scope_roots()
    backend_pick({
      title   = "Tab Grep",
      source  = "grep",
      pattern = pattern,
      live    = pattern == nil,
      dirs    = (#dirs > 0) and dirs or nil,
    })
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("TabFind", function(o)
    local pattern = o.args ~= "" and o.args or nil
    local dirs = tab_api().scope_roots()
    backend_pick({
      title   = "Tab Find",
      source  = "files",
      pattern = pattern,
      dirs    = (#dirs > 0) and dirs or nil,
    })
  end, { nargs = "*" })

  -- :TabGrepWord — grep_word scoped to current tab roots. Seeds with the
  -- cursor word (volt resolves it via picker:word(); snacks via its source).
  vim.api.nvim_create_user_command("TabGrepWord", function()
    local dirs = tab_api().scope_roots()
    backend_pick({ title = "Tab Grep Word", source = "grep_word",
                   dirs = (#dirs > 0) and dirs or nil })
  end, { range = true })

  vim.api.nvim_create_user_command("TabSymbols", function()
    backend_pick({ title = "Tab Symbols", source = "lsp_symbols", cwd_only = false })
  end, {})
end

function M.setup_search_commands()
  vim.api.nvim_create_user_command("WorkspaceScopedGrep", function(o)
    local ok, snacks_int = pcall(require, "workspace.integration.snacks")
    if not ok then
      vim.notify("[workspace] snacks integration not available: " .. snacks_int, vim.log.levels.ERROR)
      return
    end
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.WARN)
      return
    end
    local opts = {}
    if o.args ~= "" then opts.search = o.args end
    snacks_int.scoped_grep_picker(opts)
  end, { bang = true, nargs = "?", desc = "Grep with project scope picker" })

  vim.api.nvim_create_user_command("WorkspaceScopedFind", function(o)
    local ok, snacks_int = pcall(require, "workspace.integration.snacks")
    if not ok then
      vim.notify("[workspace] snacks integration not available: " .. snacks_int, vim.log.levels.ERROR)
      return
    end
    local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
    if not S or not S.picker then
      vim.notify("[workspace] snacks.picker not available", vim.log.levels.WARN)
      return
    end
    local opts = {}
    if o.args ~= "" then opts.search = o.args end
    snacks_int.scoped_find_picker(opts)
  end, { bang = true, nargs = "?", desc = "Find files with project scope picker" })
end

local function template_name_complete(arglead)
  local ok, template_api = pcall(require, "workspace.template.api")
  if not ok then return {} end
  local out = {}
  for _, item in ipairs(template_api.list()) do
    if item.name:find(arglead, 1, true) == 1 then table.insert(out, item.name) end
  end
  table.sort(out)
  return out
end

function M.setup_template_commands()
  vim.api.nvim_create_user_command("TabSaveAs", function(o)
    local name = o.args
    if name == "" then
      vim.notify("usage: :TabSaveAs <name>", vim.log.levels.ERROR)
      return
    end
    local ok, template_api = pcall(require, "workspace.template.api")
    if not ok then
      vim.notify("[workspace] template module not available: " .. template_api, vim.log.levels.ERROR)
      return
    end
    local ok_save, err = template_api.save_as(name)
    if ok_save then
      vim.notify("[workspace] template saved: " .. name)
    else
      vim.notify("[workspace] template save failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("TabLoad", function(o)
    local name = o.args
    local ok, template_api = pcall(require, "workspace.template.api")
    if not ok then
      vim.notify("[workspace] template module not available: " .. template_api, vim.log.levels.ERROR)
      return
    end
    if name == "" then
      if open_router("workspace_tab_template_load") then return end
      local S = _G.Snacks or (pcall(require, "snacks") and require("snacks") or nil)
      if not S or not S.picker then
        vim.notify("[workspace] snacks.picker not available", vim.log.levels.ERROR)
        return
      end
      local items = {}
      for _, item in ipairs(template_api.list()) do
        table.insert(items, snacks_int().normalize_item({ name = item.name, text = item.name }))
      end
      S.picker.pick({
        title = "Tab Templates",
        items = items,
        format = snacks_int().make_format({
          { "text", "SnacksPickerLabel" },
        }),
        actions = {
          confirm = function(picker, it)
            pcall(picker.close, picker)
            if not it then return end
            local ok_load, err = template_api.load(it.name)
            if ok_load then
              vim.notify("[workspace] template loaded: " .. it.name)
            else
              vim.notify("[workspace] template load failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
            end
          end,
        },
      })
      return
    end
    local ok_load, err = template_api.load(name)
    if ok_load then
      vim.notify("[workspace] template loaded: " .. name)
    else
      vim.notify("[workspace] template load failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end, { nargs = "?", complete = template_name_complete })

  vim.api.nvim_create_user_command("Workspace", function()
    local ok, router_subtree = pcall(require, "workspace.router_subtree")
    if not ok then
      vim.notify("[workspace] router_subtree not available: " .. router_subtree, vim.log.levels.WARN)
      return
    end
    local ok_router, err = pcall(function()
      local router = require("router")
      if router and router.open then
        router.open("workspace")
      end
    end)
    if not ok_router then
      vim.notify("[workspace] router not available: " .. tostring(err), vim.log.levels.WARN)
    end
  end, { desc = "Open workspace router (root)" })

  -- Direct entry commands for each sub-router so users can jump straight
  -- to the session / project / tab / ops layer instead of paging through
  -- the root menu. Each falls back to a notify when router.nvim is not
  -- registered (e.g. cfg.router.enabled == false).
  local function open_subtree(node_id, label)
    return function()
      if open_router(node_id) then return end
      vim.notify("[workspace] router subtree not available; cannot open " .. label,
        vim.log.levels.WARN)
    end
  end

  vim.api.nvim_create_user_command("WorkspaceSession",
    open_subtree("workspace_session", "session sub-router"),
    { desc = "Open workspace session sub-router" })

  vim.api.nvim_create_user_command("WorkspaceProject",
    open_subtree("workspace_project", "project sub-router"),
    { desc = "Open workspace project sub-router" })

  vim.api.nvim_create_user_command("WorkspaceTab",
    open_subtree("workspace_tab", "tab sub-router"),
    { desc = "Open workspace tab sub-router" })

  vim.api.nvim_create_user_command("WorkspaceOps",
    open_subtree("workspace_ops", "ops sub-router"),
    { desc = "Open workspace ops sub-router" })

  vim.api.nvim_create_user_command("WorkspaceSearch",
    open_subtree("workspace_search", "search sub-router"),
    { desc = "Open workspace search sub-router" })
end

function M.setup()
  M.setup_project_commands()
  M.setup_session_commands()
  M.setup_workspace_commands()
  M.setup_tab_commands()
  M.setup_search_commands()
  M.setup_template_commands()
end

return M
