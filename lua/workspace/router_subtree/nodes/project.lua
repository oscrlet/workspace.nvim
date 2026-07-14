-- Project sub-tree nodes (§3.3)
local M = {}

M.workspace_project = {
  title = "Project Actions",
  items = {
    { id = "list",     label = "List & Pick (default: add to current tab)", text = "list List & Pick (default: add to current tab)" },
    { id = "add",      label = "Add new (path input)",                      text = "add Add new (path input)" },
    { id = "init",     label = "Init current directory as project",         text = "init Init current directory as project" },
    { id = "discover", label = "Discover via glob",                         text = "discover Discover via glob" },
  },
  child_prefix = "workspace_project_",
  on_confirm = function(item)
    return "workspace_project_" .. item.id
  end,
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_project_list = {
  title = function(ctx)
    return ({
      add_to_tab     = "Pick Projects to Add (Tab=multi)",
      switch_active  = "Pick Project to Switch Active",
      search_scope   = "Pick Projects for Search Scope",
      [false]        = "Pick Project (default: add to current tab)",
    })[ctx.workspace and ctx.workspace.intent or false]
  end,
  items = function()
    local result = {}
    for _, p in ipairs(require("workspace.project").list()) do
      result[#result + 1] = vim.tbl_extend("force", p, {
        label = p.name or p.id,
        text  = (p.name or p.id) .. " " .. (p.root or ""),
      })
    end
    return result
  end,
  multi_select = true,
  preview = require("workspace.router_subtree.preview").project,
  on_confirm = function(items, ctx)
    -- router's renderer passes the current single item (a table shaped
    -- like {id="...", root="...", ...}). The legacy `type==table and
    -- items or {items}` check wrapped nothing because a single-item
    -- table IS a table; ipairs() then iterated zero times. Detect
    -- single-item shape via `.id` and wrap explicitly.
    if type(items) == "table" and items.id ~= nil then
      items = { items }
    end
    ctx.workspace = ctx.workspace or {}
    local intent = ctx.workspace.intent or "add_to_tab"
    if intent == "add_to_tab" then
      for _, p in ipairs(items) do
        require("workspace.tab").add_project_to_active(p.id)
      end
      return nil
    elseif intent == "switch_active" then
      require("workspace.tab").switch_active(items[1].id)
      return nil
    elseif intent == "search_scope" then
      ctx.workspace.search_roots = vim.tbl_map(
        function(p) return p.root end, items)
      return "workspace_search_kind"
    end
  end,
  actions = {
    { key = "<C-a>", desc = "Add to current tab",
      run = function(items)
        if type(items) == "table" and items.id ~= nil then
          items = { items }
        end
        for _, p in ipairs(items) do
          require("workspace.tab").add_project_to_active(p.id)
        end
      end, after = "close" },
    { key = "<C-s>", desc = "Switch active to this",
      run = function(item)
        require("workspace.tab").switch_active(item.id)
      end, after = "close" },
    { key = "<C-t>", desc = "Open in new tab",
      run = function(item)
        require("workspace.workspace").new_tab({ project_id = item.id })
      end, after = "close" },
    -- 收口3 (T3) — Q2 选项A: route grep/find through router.navigate instead
    -- of hard-calling Snacks.picker. The project picker is alive when the
    -- action fires → navigate{kind=open} reuses its View in-place and pushes
    -- a back-able frame (C-W5: back returns to the project list). 裁决5:
    -- workspace resolves the single project root into the dirs override here.
    -- after = nil — the run no longer closes/aborts; navigate owns the frame
    -- transition (after="close" would abort right after navigate opened).
    { key = "<C-g>", desc = "Grep in this project",
      run = function(item)
        local ok, router = pcall(require, "router")
        if not ok or not router or type(router.navigate) ~= "function" then return end
        router.navigate({
          kind = "open", to_id = "search_grep",
          overrides = { picker_opts = { dirs = { item.root } } },
        })
      end },
    { key = "<C-f>", desc = "Find files in this project",
      run = function(item)
        local ok, router = pcall(require, "router")
        if not ok or not router or type(router.navigate) ~= "function" then return end
        router.navigate({
          kind = "open", to_id = "search_find",
          overrides = { picker_opts = { dirs = { item.root } } },
        })
      end },
    { key = "<C-d>", desc = "Remove from registry",
      run = function(item)
        require("workspace.project").unregister(item.id)
      end, after = "stay" },
    { key = "<C-r>", desc = "Rename",
      run = function(item)
        vim.ui.input({ prompt = "New name: " }, function(name)
          if name then
            require("workspace.project").update(item.id, { name = name })
          end
        end)
      end, after = "stay" },
    { key = "<C-y>", desc = "Yank root path",
      run = function(item) vim.fn.setreg("+", item.root) end, after = "stay" },
  },
  -- F11: list-style node — keep default layout, fuzzy matcher.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_project_add = {
  title = "Add Project",
  items = function()
    local result = {}
    for _, str in ipairs(require("workspace.project").input_path_candidates()) do
      result[#result + 1] = { path = str, label = str, text = str }
    end
    return result
  end,
  on_confirm = function(item)
    require("workspace.project").register({ path = item.path })
    return "workspace_project_list"
  end,
  actions = {
    { key = "<C-i>", desc = "Type path manually",
      run = function()
        vim.ui.input({ prompt = "Project path: " }, function(p)
          if p then require("workspace.project").register({ path = p }) end
        end)
      end, after = "back" },
  },
  -- F11: small input-style node — compact select layout.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_project_init = {
  title = "Init Directory as Project",
  items = function()
    local path_mod = require("workspace.util.path")
    local cwd      = vim.fn.getcwd()
    local real     = (path_mod.realpath and path_mod.realpath(cwd)) or cwd
    local cfg      = require("workspace.config").get()
    local markers  = (cfg.project and cfg.project.default_markers)
                     or { ".git", ".project", ".workspace" }
    local found
    for _, m in ipairs(markers) do
      if vim.uv.fs_stat(real .. "/" .. m) then found = m; break end
    end
    local payload = require("workspace.project.dotfile").read(real)
    local hint
    if payload and type(payload.id) == "string" then
      hint = ".project present (id=" .. payload.id .. ") — register only"
    elseif found then
      hint = "marker " .. found .. " — register, skip .project write"
    else
      hint = "no marker — will write .project"
    end
    local label = real .. "  [" .. hint .. "]"
    return { { path = real, label = label, text = label } }
  end,
  on_confirm = function(item)
    vim.cmd("ProjectInit " .. vim.fn.fnameescape(item.path))
    return "workspace_project_list"
  end,
  actions = {
    { key = "<C-i>", desc = "Type a different path",
      run = function()
        vim.ui.input({ prompt = "Init path: ", default = vim.fn.getcwd() }, function(p)
          if p and p ~= "" then
            vim.cmd("ProjectInit " .. vim.fn.fnameescape(p))
          end
        end)
      end, after = "back" },
  },
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

M.workspace_project_discover = {
  title = "Discover Projects",
  items = function()
    local candidates = require("workspace.project").discover(
      require("workspace").config and
        require("workspace").config.project and
        require("workspace").config.project.auto_scan and
        require("workspace").config.project.auto_scan.globs or {},
      { dry_run = true }
    )
    -- Filter out roots that are already in the registry — discover
    -- itself is path-based and does not deduplicate against registry,
    -- so without this the picker keeps showing projects the user just
    -- registered in the previous confirm.
    local registered = {}
    local path_mod = require("workspace.util.path")
    for _, p in ipairs(require("workspace.project").list()) do
      local real = (path_mod.realpath and path_mod.realpath(p.root)) or p.root
      if real then registered[real] = true end
    end
    local result = {}
    for _, c in ipairs(candidates) do
      if not registered[c.path] then
        result[#result + 1] = vim.tbl_extend("force", c, {
          text = (c.suggested_id or "") .. " " .. (c.path or ""),
        })
      end
    end
    return result
  end,
  multi_select = true,
  preview = require("workspace.router_subtree.preview").project,
  on_confirm = function(items)
    if type(items) == "table" and items.path ~= nil then
      items = { items }
    end
    for _, candidate in ipairs(items) do
      require("workspace.project").register({ path = candidate.path })
    end
    return "workspace_project_list"
  end,
  -- F11: preview-heavy multi-select — vertical layout.
  on_back = function(_ctx) end,
  picker_opts = { matcher = { fuzzy = true } },
}

return M
