--- workspace/router_subtree/preview.lua
--- Snacks ctx-style preview generators for router subtree nodes.
---
--- Snacks invokes node.preview as f(ctx) where ctx is a table with
--- ctx.item, ctx.preview (a buffer-writer), ctx.picker, etc. Each helper
--- here populates ctx.preview via :reset() + :set_lines(lines), guarded
--- against nil/missing fields.

local ui_preview = require("workspace.ui.preview")

local function set(ctx, lines)
  pcall(function() ctx.preview:reset() end)
  pcall(function() ctx.preview:set_lines(lines or { "" }) end)
end

--- Project ctx-preview: reads ctx.item.root (or .path) and renders project_tree.
local function project(ctx)
  local item = ctx and ctx.item or nil
  local root = item and (item.root or item.path) or nil
  if not root then
    return set(ctx, { "(no root)" })
  end
  -- Reuse router's dir_peek so project previews share the devicon + color
  -- directory rendering (governed by router's preview.command), instead of a
  -- separate plain-text eza expander. Fall back to project_tree if
  -- router.preview is unavailable.
  local ok, rp = pcall(require, "router.preview")
  if ok and type(rp.dir_peek) == "function" then
    ctx.item = ctx.item or {}
    if type(ctx.item.dir) ~= "string" then ctx.item.dir = root end
    return rp.dir_peek(ctx)
  end
  set(ctx, ui_preview.project_tree(root))
end

-- Expand `sections` via router's dirs_peek (shared devicon dir rendering)
-- with a markdown metadata `header` on top; fall back to a plain-text
-- renderer if router.preview is unavailable or there's nothing to expand.
local function expand_or(ctx, sections, opts, fallback)
  local ok, rp = pcall(require, "router.preview")
  if ok and type(rp.dirs_peek) == "function" and #sections > 0 then
    return rp.dirs_peek(ctx, sections, opts)
  end
  return set(ctx, fallback())
end

--- Session ctx-preview: markdown metadata (tabs → projects, active marked)
--- on top, then each distinct project root expanded with icons.
local function session(ctx)
  local item = ctx and ctx.item or nil
  local name = item and item.name or nil
  if not name then
    return set(ctx, { "(no session name)" })
  end
  local registry = require("workspace.project.registry")
  local ok, data = pcall(require("workspace.session.store").read, name)

  local header = { "# Session: " .. name, "" }
  local sections, seen = {}, {}
  if ok and data and type(data.tabs) == "table" then
    for i, ts in ipairs(data.tabs) do
      local tlabel = ts.label or ("Tab " .. (ts.order or i))
      header[#header + 1] = "- **" .. tlabel .. "**:"
      local ids = ts.project_ids or {}
      if #ids == 0 then header[#header + 1] = "  - (empty)" end
      for _, pid in ipairs(ids) do
        local p = registry.get(pid)
        local pname = (p and p.name) or pid
        header[#header + 1] = (pid == ts.active_project_id)
          and ("  - **" .. pname .. "** _(active)_") or ("  - " .. pname)
        local root = p and p.root
        if root and not seen[root] then
          seen[root] = true
          sections[#sections + 1] = { label = pname, path = root }
        end
      end
    end
  end

  expand_or(ctx, sections, { header = header, ft = "markdown" },
    function() return ui_preview.session_tree(name) end)
end

--- Tab ctx-preview: markdown metadata (cwd / projects / active) on top, then
--- each distinct project root expanded with icons.
local function tab(ctx)
  local item = ctx and ctx.item or nil
  local t = item and (item.tab or item) or nil
  if not t or type(t) ~= "table" then
    return set(ctx, { "(no tab)" })
  end
  local registry = require("workspace.project.registry")
  local header = {
    "# Tab: " .. (t.label or t.cwd or "(tab)"),
    "",
    "- **cwd**: " .. (t.cwd or "(none)"),
    "- **projects**:",
  }
  local sections, seen = {}, {}
  local ids = t.project_ids or {}
  if #ids == 0 then header[#header + 1] = "  - (none)" end
  for _, pid in ipairs(ids) do
    local p = registry.get(pid)
    local pname = (p and p.name) or pid
    header[#header + 1] = (pid == t.active_project_id)
      and ("  - **" .. pname .. "** _(active)_") or ("  - " .. pname)
    local root = p and p.root
    if root and not seen[root] then
      seen[root] = true
      sections[#sections + 1] = { label = pname, path = root }
    end
  end

  expand_or(ctx, sections, { header = header, ft = "markdown" },
    function() return ui_preview.tab_detail(t) end)
end

return {
  project = project,
  session = session,
  tab     = tab,
}
