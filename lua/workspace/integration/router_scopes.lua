-- Registers workspace-aware search scopes into router.nvim's scope chooser.
-- router stays decoupled: it exposes router.scope.register; we contribute
-- Tab projects (multi-root), Session projects (multi-root), and an
-- interactive Project… picker (source → single project → its root).
local M = {}

local function safe(mod)
  local ok, m = pcall(require, mod)
  if ok then return m end
  return nil
end

-- All distinct project roots in the session (resolved from session project
-- ids via the registry).
local function session_roots()
  local session  = safe("workspace.session")
  local registry = safe("workspace.project.registry")
  if not (session and registry) then return {} end
  local seen, dirs = {}, {}
  for _, id in ipairs(session.projects() or {}) do
    local p = registry.get(id)
    if p and p.root and not seen[p.root] then
      seen[p.root] = true
      dirs[#dirs + 1] = p.root
    end
  end
  return dirs
end

-- Candidate projects ({ name, root } list) for a source id.
local function candidates(source_id)
  local registry = safe("workspace.project.registry")
  if not registry then return {} end
  local out = {}
  if source_id == "global" then
    for _, p in ipairs(registry.list() or {}) do
      out[#out + 1] = { name = p.name, root = p.root }
    end
    return out
  end
  local mod = (source_id == "tab") and safe("workspace.tab")
                                   or  safe("workspace.session")
  if not mod then return {} end
  for _, id in ipairs(mod.projects() or {}) do
    local p = registry.get(id)
    if p and p.root then out[#out + 1] = { name = p.name, root = p.root } end
  end
  return out
end

-- Interactive Project… scope (收口1 进取档): pick a source, then a single
-- project, as a TWO-NODE router chain — ws_scope_source → ws_scope_project.
-- These are in-stack apply frames (custom items), reusing the active picker
-- View and back-able (NOT an overlay, NOT new_subpicker). This replaces the
-- old backend.pick + router._skip_next_abort side channel entirely.
--
-- The scope chooser's on_done callback is a one-shot async handoff that can't
-- ride ctx (functions don't survive deepcopy on go_back), so we stash it in a
-- module-level _pending_cb (方案B, ratified by R4). Leakage is BOUNDED, not
-- growing: every choose_project entry overwrites _pending_cb; an abandoned
-- closure is never read again (only ws_scope_project.on_confirm reads it) and
-- is overwritten on the next entry. Cleanup: consume → nil, and
-- ws_scope_source.on_back (cancel at the source level) → nil.
local _pending_cb = nil

local ws_scope_nodes = {
  ws_scope_source = {
    title = "Project source",
    items = {
      { id = "tab",     label = "Tab projects",     text = "tab Tab projects" },
      { id = "session", label = "Session projects", text = "session Session projects" },
      { id = "global",  label = "Global projects",  text = "global Global projects" },
    },
    on_confirm = function(item, ctx)
      ctx.workspace = ctx.workspace or {}
      ctx.workspace._scope_source = item.id
      return "ws_scope_project"
    end,
    -- Cancel at the source level aborts the whole pick → drop the pending cb.
    on_back = function(_ctx) _pending_cb = nil end,
    picker_opts = { matcher = { fuzzy = true } },
  },

  ws_scope_project = {
    title = "Choose project",
    items = function(ctx)
      local src = (ctx.workspace and ctx.workspace._scope_source) or "global"
      local projs = candidates(src)
      for _, it in ipairs(projs) do
        it.label = it.name
        it.text  = it.name
      end
      return projs
    end,
    -- WC-3.2: lazy-require preview so a missing/broken preview module (or a
    -- require cycle) can't fail this module's load and silently skip
    -- M.register() — that would make the whole scope chooser vanish.
    preview = function(ctx)
      return require("workspace.router_subtree.preview").project(ctx)
    end,
    on_confirm = function(item, _ctx)
      -- Consume the pending cb (one-shot). 裁决5: workspace resolves the
      -- single project root here; the scope chooser only ever sees dirs.
      local cb = _pending_cb
      _pending_cb = nil
      if cb then cb({ item.root }, item.name) end
      return nil  -- done: the scope chooser now drives the actual search
    end,
    -- WC-3.3: back at the project level is a cancel too — drop the pending cb
    -- so a later close path (WinClosed) or stray confirm can't fire a stale
    -- closure that would resolve a scope the user abandoned.
    on_back = function(_ctx) _pending_cb = nil end,
    picker_opts = { matcher = { fuzzy = true } },
  },
}

-- ws_project scope entry point: stash the chooser callback and navigate into
-- the two-node chain. The scope chooser is a router overlay (kind=menu) whose
-- on_choice fires AFTER the overlay is dismissed, so by the time get() runs the
-- menu is closed and navigate{open ws_scope_source} enters a clean frame chain.
local function choose_project(on_done)
  local router = safe("router")
  if not (router and type(router.navigate) == "function") then
    on_done(nil); return
  end
  _pending_cb = on_done
  router.navigate({ kind = "open", to_id = "ws_scope_source" })
end

function M.register()
  -- Register the two-node project-chooser chain (收口1). Idempotent:
  -- register_node overwrites on re-setup.
  local router = safe("router")
  if router and type(router.register_node) == "function" then
    for id, spec in pairs(ws_scope_nodes) do
      router.register_node(id, spec)
    end
  end

  local scope = safe("router.scope")
  if not scope or not scope.register then return end

  scope.register({
    id = "ws_tab", label = "Tab projects",
    get = function(cb)
      local tab = safe("workspace.tab")
      local dirs = tab and tab.scope_roots() or {}
      if #dirs == 0 then cb(nil) else cb(dirs, "tab") end
    end,
  })

  scope.register({
    id = "ws_session", label = "Session projects",
    get = function(cb)
      local dirs = session_roots()
      if #dirs == 0 then cb(nil) else cb(dirs, "session") end
    end,
  })

  scope.register({
    id = "ws_project", label = "Project…",
    get = function(cb) choose_project(cb) end,
  })
end

return M
