-- Loop 6 — end-to-end regression probe for workspace.nvim.
-- Run with:
--   nvim --headless --clean -u NONE -l test/regression.lua
-- Exits 0 when all 25 PASS, non-zero otherwise.

local rt = vim.fn.expand("~/code/neovim/plugins/")
vim.opt.runtimepath:append(rt .. "router.nvim")
vim.opt.runtimepath:append(rt .. "workspace.nvim")
vim.opt.runtimepath:append(vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"))

local pass, fail = 0, 0
local function check(name, ok, msg)
  if ok then
    pass = pass + 1
    print("[PASS] " .. name)
  else
    fail = fail + 1
    print("[FAIL] " .. name .. ": " .. tostring(msg))
  end
end

-- ---------------------------------------------------------------------------
-- Sandbox: tmp data dir
-- ---------------------------------------------------------------------------
local tmp_root = vim.fn.tempname()
vim.fn.mkdir(tmp_root, "p")

-- Track event firings.
local events_seen = {}
local function record_event(pat)
  vim.api.nvim_create_autocmd("User", {
    pattern = pat,
    callback = function(args)
      events_seen[pat] = events_seen[pat] or {}
      table.insert(events_seen[pat], args.data)
    end,
  })
end
for _, pat in ipairs({
  "WorkspaceProjectRegistered", "WorkspaceProjectUnregistered", "WorkspaceProjectUpdated",
  "WorkspaceSessionSaved", "WorkspaceSessionDeleted", "WorkspaceSessionRenamed", "WorkspaceSessionLoaded",
  "WorkspaceTabProjectAdded", "WorkspaceTabProjectRemoved",
}) do record_event(pat) end

-- Mock Snacks before workspace setup so router/integration sees it.
local picker_calls = {}
local active_pickers = {}
_G.Snacks = {
  picker = {
    pick = function(opts)
      table.insert(picker_calls, opts)
      local picker = {
        _opts = opts,
        close = function(self) end,
      }
      table.insert(active_pickers, picker)
      return picker
    end,
    get = function(_filter) return active_pickers end,
    grep = function(opts) table.insert(picker_calls, { kind = "grep", opts = opts }) end,
    files = function(opts) table.insert(picker_calls, { kind = "files", opts = opts }) end,
    lsp_symbols = function(opts) table.insert(picker_calls, { kind = "lsp_symbols", opts = opts }) end,
  },
}

-- ---------------------------------------------------------------------------
-- A. Plumbing
-- ---------------------------------------------------------------------------

-- A1
local ok_setup, err_setup = pcall(function()
  require("workspace").setup({
    data_dir = tmp_root,
    session = {
      autoload_last_on_startup = false,
      confirm_before_load = false,
    },
    project = {
      preview = { command = "eza" },
    },
    ui = {
      dashboard = { alpha_section = true },
    },
    router = { enabled = true },
  })
end)
check("A1 setup() returns without error", ok_setup, err_setup)

-- A2: :Workspace exists + dispatches to router.open("workspace")
do
  local exists = vim.fn.exists(":Workspace") == 2
  -- Spy on router.open
  local router = require("router")
  local orig_open = router.open
  local captured
  router.open = function(id, ctx_init) captured = { id = id, ctx_init = ctx_init } end
  local ok, err = pcall(vim.cmd, "Workspace")
  router.open = orig_open
  check("A2 :Workspace exists + dispatches router.open(\"workspace\")",
    exists and ok and captured and captured.id == "workspace",
    string.format("exists=%s ok=%s captured=%s", tostring(exists), tostring(ok),
      vim.inspect(captured)))
end

-- A3
do
  local missing = {}
  for _, c in ipairs({
    "ProjectList", "SessionList", "WorkspaceList",
    "TabAddProject", "TabSwitchProject", "TabRemoveProject", "TabLoad",
  }) do
    if vim.fn.exists(":" .. c) ~= 2 then table.insert(missing, c) end
  end
  check("A3 user commands registered (7)", #missing == 0, "missing=" .. vim.inspect(missing))
end

-- A4
do
  local missing = {}
  for _, c in ipairs({ "ProjectMove", "ProjectEdit", "WorkspaceMigrateFromProjections" }) do
    if vim.fn.exists(":" .. c) ~= 2 then table.insert(missing, c) end
  end
  check("A4 user commands ProjectMove/ProjectEdit/WorkspaceMigrateFromProjections",
    #missing == 0, "missing=" .. vim.inspect(missing))
end

-- ---------------------------------------------------------------------------
-- B. Reactive sync (router_refresh)
-- ---------------------------------------------------------------------------

-- B2: augroup exists and has 8 patterns
do
  local autocmds = vim.api.nvim_get_autocmds({ group = "WorkspaceRouterRefresh" })
  local patterns = {}
  for _, a in ipairs(autocmds) do patterns[a.pattern] = true end
  local expected = {
    "WorkspaceProjectRegistered", "WorkspaceProjectUnregistered", "WorkspaceProjectUpdated",
    "WorkspaceSessionSaved", "WorkspaceSessionDeleted", "WorkspaceSessionRenamed",
    "WorkspaceTabProjectAdded", "WorkspaceTabProjectRemoved",
  }
  local missing = {}
  for _, p in ipairs(expected) do if not patterns[p] then table.insert(missing, p) end end
  check("B2 WorkspaceRouterRefresh augroup has 8 patterns",
    #missing == 0 and #autocmds >= 8,
    string.format("count=%d missing=%s", #autocmds, vim.inspect(missing)))
end

-- B1: invalidate_items_cache callable; firing event triggers it (via debounce timer)
do
  local renderer = require("router.renderer")
  local ok_call = type(renderer.invalidate_items_cache) == "function"
  local invalidated = false
  local orig = renderer.invalidate_items_cache
  renderer.invalidate_items_cache = function() invalidated = true; return orig() end
  vim.api.nvim_exec_autocmds("User", { pattern = "WorkspaceProjectUnregistered", data = { id = "x" } })
  vim.wait(200, function() return invalidated end)
  renderer.invalidate_items_cache = orig
  check("B1 router_refresh invalidates renderer cache on event", ok_call and invalidated,
    "callable=" .. tostring(ok_call) .. " invalidated=" .. tostring(invalidated))
end

-- B3: ProjectDiscover candidates filter out already-registered roots
do
  local project = require("workspace.project")
  -- Set up two real dirs as candidates; register one.
  local d1 = tmp_root .. "/disc1"
  local d2 = tmp_root .. "/disc2"
  vim.fn.mkdir(d1 .. "/.git", "p")
  vim.fn.mkdir(d2 .. "/.git", "p")
  -- Register d1 already.
  project.register({ path = d1, id = "disc1" })
  -- Use the router_subtree node to get filtered items.
  local nodes = require("workspace.router_subtree.nodes")
  local node = nodes.workspace_project_discover
  -- Override globs in config so discover can find these dirs.
  local cfg = require("workspace.config").get()
  cfg.project.auto_scan = cfg.project.auto_scan or {}
  cfg.project.auto_scan.globs = { tmp_root .. "/disc*" }
  cfg.project.auto_scan.markers = { ".git" }
  local items = node.items()
  local seen_d1, seen_d2 = false, false
  local path_mod = require("workspace.util.path")
  local r1 = path_mod.realpath(d1)
  local r2 = path_mod.realpath(d2)
  for _, it in ipairs(items) do
    if it.path == r1 then seen_d1 = true end
    if it.path == r2 then seen_d2 = true end
  end
  check("B3 ProjectDiscover filters already-registered roots",
    (not seen_d1) and seen_d2,
    string.format("d1_present=%s d2_present=%s items=%s",
      tostring(seen_d1), tostring(seen_d2), vim.inspect(items)))
  -- Cleanup.
  project.unregister("disc1")
end

-- ---------------------------------------------------------------------------
-- C. Snapshot / restore
-- ---------------------------------------------------------------------------

-- Build state: 2 nvim tabs, vsplit + hidden buf in tab 1, split in tab 2.
local files = {}
for i = 1, 4 do
  local p = tmp_root .. "/file" .. i .. ".txt"
  local f = io.open(p, "w")
  f:write("file " .. i .. "\n")
  f:close()
  files[i] = vim.uv.fs_realpath(p) or p
end

-- Reset all tabs/buffers first.
vim.cmd("silent! %bwipeout!")
vim.cmd("silent! tabonly")

-- Tab 1: vsplit with file1, file2; badd file3 (hidden buf).
vim.cmd("edit " .. vim.fn.fnameescape(files[1]))
vim.cmd("vsplit " .. vim.fn.fnameescape(files[2]))
vim.cmd("badd " .. vim.fn.fnameescape(files[3]))
-- Tab 2: split with file4
vim.cmd("tabnew " .. vim.fn.fnameescape(files[4]))
vim.cmd("split")

-- Register one project.
local snapshot_mod = require("workspace.workspace.snapshot")
local project = require("workspace.project")
local proj_dir = tmp_root .. "/proj_for_snap"
vim.fn.mkdir(proj_dir .. "/.git", "p")
project.register({ path = proj_dir, id = "snap_proj" })

-- ensure tab_state for both tabs
local tab_state = require("workspace.tab.state")
for _, nr in ipairs(vim.api.nvim_list_tabpages()) do tab_state.ensure(nr) end

-- C1
do
  local tabs = vim.api.nvim_list_tabpages()
  local has_state = tab_state.by_tabnr(tabs[1]) ~= nil and tab_state.by_tabnr(tabs[2]) ~= nil
  check("C1 build state: 2 tabs + tab_state for both", #tabs == 2 and has_state,
    string.format("tabs=%d has_state=%s", #tabs, tostring(has_state)))
end

-- C2
local snap
do
  snap = snapshot_mod.snapshot()
  local tabs_count = (snap.tabs and #snap.tabs) or 0
  local listed = (snap.listed_buffers and #snap.listed_buffers) or 0
  local both_winlayout = true
  for _, e in ipairs(snap.tabs or {}) do
    local ok, dec = pcall(vim.json.decode, e.nvim_state or "")
    if not (ok and type(dec) == "table" and dec.kind == "winlayout"
            and dec.layout and dec.wins) then
      both_winlayout = false
    end
  end
  check("C2 snapshot.snapshot() captures 2 tabs / winlayout / listed buffers",
    tabs_count == 2 and listed >= #files and both_winlayout,
    string.format("tabs=%d listed=%d winlayout=%s", tabs_count, listed, tostring(both_winlayout)))
end

-- C3: wipe and restore
do
  vim.cmd("silent! tabonly")
  vim.cmd("silent! %bwipeout!")
  snapshot_mod.restore(snap)
  local tabs = vim.api.nvim_list_tabpages()
  local win_counts = {}
  for _, nr in ipairs(tabs) do
    win_counts[#win_counts + 1] = #vim.api.nvim_tabpage_list_wins(nr)
  end
  -- Tab1 had vsplit (2 wins). Tab2 had a split (2 wins).
  local listed_names = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted then
      local n = vim.api.nvim_buf_get_name(b)
      if n ~= "" then listed_names[n] = true end
    end
  end
  local listed_count = vim.tbl_count(listed_names)
  check("C3 restore: 2 tabs, win counts >= 2 each, files restored",
    #tabs == 2 and win_counts[1] >= 2 and win_counts[2] >= 2 and listed_count >= #files,
    string.format("tabs=%d wins=%s listed=%d", #tabs, vim.inspect(win_counts), listed_count))
end

-- C5: default backend resolves to winlayout when resession is absent.
do
  package.loaded["resession"] = nil
  package.preload["resession"] = nil
  package.loaded["workspace.snapshot"] = nil
  package.loaded["workspace.snapshot.resession"] = nil
  local dispatch = require("workspace.snapshot")
  local cfg = require("workspace.config").get()
  local picked = dispatch.resolve(cfg.session.snapshot_backend or "resession-auto")
  check("C5 default backend (resession-auto, no plugin) resolves to winlayout",
    picked and picked.kind == "winlayout",
    "kind=" .. tostring(picked and picked.kind))
end

-- C6: explicit override selects the requested backend.
do
  local dispatch = require("workspace.snapshot")
  local mks = dispatch.resolve("mksession")
  local win = dispatch.resolve("winlayout")
  check("C6 explicit backend override (mksession, winlayout)",
    mks and mks.kind == "mksession" and win and win.kind == "winlayout",
    string.format("mks=%s win=%s",
      tostring(mks and mks.kind), tostring(win and win.kind)))
end

-- ---------------------------------------------------------------------------
-- D. Session API
-- ---------------------------------------------------------------------------

local session_api = require("workspace.session.api")
local session_store = require("workspace.session.store")

-- D1
do
  events_seen.WorkspaceSessionSaved = nil
  local ok = session_api.save("test1")
  local fired = events_seen.WorkspaceSessionSaved ~= nil
  local on_disk = vim.fn.filereadable(session_store.path("test1")) == 1
  check("D1 session.save fires + writes file", ok and fired and on_disk,
    string.format("ok=%s fired=%s disk=%s", tostring(ok), tostring(fired), tostring(on_disk)))
end

-- D2: load with force=true → no vim.ui.select call
do
  local select_called = false
  local orig_select = vim.ui.select
  vim.ui.select = function(...) select_called = true; return orig_select(...) end
  local ok = session_api.load("test1", { force = true })
  vim.ui.select = orig_select
  check("D2 session.load with force=true does not call vim.ui.select",
    ok and not select_called,
    string.format("ok=%s select_called=%s", tostring(ok), tostring(select_called)))
end

-- D3: confirm_before_load = true
do
  local cfg = require("workspace.config").get()
  cfg.session.confirm_before_load = true

  -- Cancel branch
  local restore_called = 0
  local snapshot_real = require("workspace.workspace.snapshot")
  local orig_restore = snapshot_real.restore
  snapshot_real.restore = function(...) restore_called = restore_called + 1; return orig_restore(...) end

  local capture
  local orig_select = vim.ui.select
  vim.ui.select = function(items, opts, cb) capture = { items = items, opts = opts }; cb(nil) end
  session_api.load("test1")
  local cancel_no_change = (restore_called == 0) and (capture ~= nil)

  -- Load branch
  vim.ui.select = function(items, opts, cb) cb("Load") end
  session_api.load("test1")
  local load_proceeds = restore_called == 1

  vim.ui.select = orig_select
  snapshot_real.restore = orig_restore
  cfg.session.confirm_before_load = false
  check("D3 confirm_before_load: cancel→no-op, Load→proceeds",
    cancel_no_change and load_proceeds,
    string.format("cancel_ok=%s load_ok=%s captured=%s",
      tostring(cancel_no_change), tostring(load_proceeds), vim.inspect(capture)))
end

-- D4
do
  events_seen.WorkspaceSessionDeleted = nil
  session_api.save("delme")
  session_api.delete("delme")
  check("D4 session.delete fires WorkspaceSessionDeleted",
    events_seen.WorkspaceSessionDeleted ~= nil,
    "events=" .. vim.inspect(events_seen.WorkspaceSessionDeleted))
end

-- D5
do
  events_seen.WorkspaceSessionRenamed = nil
  session_api.save("rn_old")
  local ok = session_api.rename("rn_old", "rn_new")
  local data = events_seen.WorkspaceSessionRenamed
  local matches = data and data[1] and data[1].from == "rn_old" and data[1].to == "rn_new"
  check("D5 session.rename fires { from, to }", ok and matches,
    "ok=" .. tostring(ok) .. " data=" .. vim.inspect(data))
  session_api.delete("rn_new")
end

-- ---------------------------------------------------------------------------
-- E. Project API
-- ---------------------------------------------------------------------------

-- E1
do
  events_seen.WorkspaceProjectRegistered = nil
  local pdir = tmp_root .. "/projE1"
  vim.fn.mkdir(pdir .. "/.git", "p")
  project.register({ path = pdir, id = "projE1" })
  check("E1 register fires WorkspaceProjectRegistered",
    events_seen.WorkspaceProjectRegistered ~= nil,
    "events=" .. vim.inspect(events_seen.WorkspaceProjectRegistered))
end

-- E2
do
  events_seen.WorkspaceProjectUpdated = nil
  project.update("projE1", { name = "ProjectE1Renamed" })
  check("E2 update fires WorkspaceProjectUpdated",
    events_seen.WorkspaceProjectUpdated ~= nil,
    "events=" .. vim.inspect(events_seen.WorkspaceProjectUpdated))
end

-- E3
do
  events_seen.WorkspaceProjectUnregistered = nil
  project.unregister("projE1")
  check("E3 unregister fires WorkspaceProjectUnregistered",
    events_seen.WorkspaceProjectUnregistered ~= nil,
    "events=" .. vim.inspect(events_seen.WorkspaceProjectUnregistered))
end

-- E4
do
  local pdir1 = tmp_root .. "/projE4_a"
  local pdir2 = tmp_root .. "/projE4_b"
  vim.fn.mkdir(pdir1 .. "/.git", "p")
  vim.fn.mkdir(pdir2 .. "/.git", "p")
  project.register({ path = pdir1, id = "projE4" })
  events_seen.WorkspaceProjectUpdated = nil
  local proj_api = require("workspace.project.api")
  local ok, err = proj_api.move("projE4", pdir2)
  local proj = project.get("projE4")
  local real2 = vim.uv.fs_realpath(pdir2) or pdir2
  check("E4 move() updates root + fires Updated",
    ok and proj and proj.root == real2 and events_seen.WorkspaceProjectUpdated ~= nil,
    string.format("ok=%s err=%s root=%s expected=%s",
      tostring(ok), tostring(err), proj and proj.root or "nil", real2))
  project.unregister("projE4")
end

-- ---------------------------------------------------------------------------
-- F. Preview command branching
-- ---------------------------------------------------------------------------

local preview_ui = require("workspace.ui.preview")

local function with_preview_command(name, exec_set, fn)
  local cfg = require("workspace.config").get()
  local prev = cfg.project.preview.command
  cfg.project.preview.command = name
  local orig_exe = vim.fn.executable
  local orig_sl = vim.fn.systemlist
  local sl_calls = {}
  vim.fn.executable = function(bin) return exec_set[bin] and 1 or 0 end
  vim.fn.systemlist = function(argv)
    table.insert(sl_calls, argv)
    -- Pretend success with non-empty output
    vim.v.shell_error = 0
    return { "fake-output-line" }
  end
  local ok, err = pcall(fn, sl_calls)
  vim.fn.executable = orig_exe
  vim.fn.systemlist = orig_sl
  cfg.project.preview.command = prev
  if not ok then error(err) end
end

local probe_root = tmp_root  -- a real directory

-- F1: tree
with_preview_command("tree", { tree = true }, function(sl_calls)
  preview_ui.project_tree(probe_root)
  local matched = false
  for _, c in ipairs(sl_calls) do
    if type(c) == "table" and c[1] == "tree" then matched = true end
  end
  check("F1 preview command tree → invokes tree", matched, "calls=" .. vim.inspect(sl_calls))
end)

-- F2: fd
with_preview_command("fd", { fd = true }, function(sl_calls)
  preview_ui.project_tree(probe_root)
  local matched = false
  for _, c in ipairs(sl_calls) do
    if type(c) == "table" and c[1] == "fd" then matched = true end
  end
  check("F2 preview command fd → invokes fd", matched, "calls=" .. vim.inspect(sl_calls))
end)

-- F3: eza
with_preview_command("eza", { eza = true }, function(sl_calls)
  preview_ui.project_tree(probe_root)
  local matched = false
  for _, c in ipairs(sl_calls) do
    if type(c) == "table" and c[1] == "eza" then matched = true end
  end
  check("F3 preview command eza → invokes eza", matched, "calls=" .. vim.inspect(sl_calls))
end)

-- F4: all missing → builtin (no systemlist)
with_preview_command("eza", {}, function(sl_calls)
  local out = preview_ui.project_tree(probe_root)
  check("F4 all binaries missing → builtin readdir (no systemlist)",
    #sl_calls == 0 and type(out) == "table" and #out > 0,
    string.format("sl_calls=%d out_len=%d", #sl_calls, type(out) == "table" and #out or -1))
end)

-- ---------------------------------------------------------------------------
-- G. Dashboard
-- ---------------------------------------------------------------------------

local dashboard = require("workspace.ui.dashboard")

-- G1: alpha_section = false → returns nil
do
  local cfg = require("workspace.config").get()
  cfg.ui.dashboard.alpha_section = false
  local r = dashboard.alpha_section()
  cfg.ui.dashboard.alpha_section = true
  check("G1 alpha_section=false returns nil", r == nil, "got=" .. vim.inspect(r))
end

-- G2: with ≥1 saved session → group with ≥1 button
do
  -- Ensure at least one session
  session_api.save("dash1")
  local r = dashboard.alpha_section()
  local ok = r and r.type == "group" and type(r.val) == "table"
  -- Find buttons subgroup
  local btn_count = 0
  if ok then
    for _, child in ipairs(r.val) do
      if type(child) == "table" and child.type == "group" and type(child.val) == "table" then
        for _, b in ipairs(child.val) do
          if type(b) == "table" and b.type == "button" then btn_count = btn_count + 1 end
        end
      end
    end
  end
  check("G2 dashboard.alpha_section returns group with buttons",
    ok and btn_count >= 1,
    string.format("ok=%s buttons=%d", tostring(ok), btn_count))
end

-- G3: button on_press calls session.load(name, { force = true })
do
  local r = dashboard.alpha_section()
  -- Stub session.load
  local captured
  local orig_load = session_api.load
  session_api.load = function(name, opts) captured = { name = name, opts = opts } end
  -- Also stub the cached session module that dashboard.lua require()'d.
  -- It uses its own require, so we patch the same module table.
  local sess_mod = require("workspace.session.api")
  sess_mod.load = session_api.load

  -- Find first button
  local first_btn
  for _, child in ipairs(r.val) do
    if type(child) == "table" and child.type == "group" and type(child.val) == "table" then
      for _, b in ipairs(child.val) do
        if type(b) == "table" and b.type == "button" then first_btn = b; break end
      end
    end
    if first_btn then break end
  end
  if first_btn and type(first_btn.on_press) == "function" then
    pcall(first_btn.on_press)
  end

  session_api.load = orig_load
  sess_mod.load = orig_load

  check("G3 dashboard button on_press calls session.load(name, {force=true})",
    captured ~= nil and captured.opts and captured.opts.force == true,
    "captured=" .. vim.inspect(captured))
end

-- ---------------------------------------------------------------------------
-- H. Autoload + tabufline
-- ---------------------------------------------------------------------------

-- H1: autoload_last_on_startup=false → no augroup
do
  -- Already set false in initial setup, but augroup may exist from previous tests if true
  -- Verify: query for the augroup
  local has_group = false
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "WorkspaceAutoload" })
  if ok then has_group = #autocmds > 0 end
  check("H1 autoload_last_on_startup=false → no WorkspaceAutoload augroup",
    not has_group,
    "autocmds=" .. vim.inspect(autocmds))
end

-- H2: =true → augroup exists; firing VimEnter calls session.load(name, { force = true })
do
  -- Re-setup with autoload=true
  local captured
  local sess_mod = require("workspace.session.api")
  local orig_load = sess_mod.load
  sess_mod.load = function(name, opts) captured = { name = name, opts = opts }; return true end

  -- Make sure there is at least one session, and pretend none is current.
  local ss = require("workspace.session.state")
  ss.set_current(nil)

  require("workspace").setup({
    data_dir = tmp_root,
    session = { autoload_last_on_startup = true, confirm_before_load = false },
  })

  local has_group = false
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "WorkspaceAutoload" })
  if ok then has_group = #autocmds > 0 end

  -- Fire VimEnter manually.
  vim.api.nvim_exec_autocmds("VimEnter", {})
  vim.wait(50, function() return captured ~= nil end)

  sess_mod.load = orig_load
  check("H2 autoload_last_on_startup=true → augroup + VimEnter triggers load(force)",
    has_group and captured and captured.opts and captured.opts.force == true,
    string.format("has_group=%s captured=%s", tostring(has_group), vim.inspect(captured)))
end

-- H3: tabufline.setup() returns OK whether NvChad present or absent.
do
  -- Absent (already loaded; the module's setup is idempotent on require failure).
  package.loaded["nvchad.tabufline.modules"] = nil
  -- Reload the integration module to reset _nvchad_present probing.
  package.loaded["workspace.integration.tabufline"] = nil
  local tabu = require("workspace.integration.tabufline")
  local ok_absent = pcall(tabu.setup)
  local absent_state = tabu._nvchad_present == false

  -- Present (mock the require target).
  package.loaded["nvchad.tabufline.modules"] = { tabs = function() end }
  package.loaded["workspace.integration.tabufline"] = nil
  local tabu2 = require("workspace.integration.tabufline")
  local ok_present = pcall(tabu2.setup)
  local present_state = tabu2._nvchad_present == true
  -- Reset.
  package.loaded["nvchad.tabufline.modules"] = nil

  check("H3 tabufline.setup() works in both presence states",
    ok_absent and ok_present and absent_state and present_state,
    string.format("ok_absent=%s ok_present=%s flags=%s/%s",
      tostring(ok_absent), tostring(ok_present),
      tostring(absent_state), tostring(present_state)))
end

-- ---------------------------------------------------------------------------
-- I. Snacks.explorer integration smoke
-- ---------------------------------------------------------------------------

-- I1: setup() runs without error (with default cfg).
do
  package.loaded["workspace.integration.explorer"] = nil
  require("workspace.config")._reset()
  local ok, err = pcall(function()
    require("workspace.integration.explorer").setup()
  end)
  check("I1 integration.explorer.setup() runs without error", ok, err)
end

-- I2: augroup `WorkspaceExplorerFollow` exists with default config.
do
  local has_group = false
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, {
    group = "WorkspaceExplorerFollow",
    event = "User",
    pattern = "WorkspaceTabActiveChanged",
  })
  if ok then has_group = #autocmds > 0 end
  check("I2 WorkspaceExplorerFollow augroup exists with default cfg",
    has_group,
    "autocmds=" .. vim.inspect(autocmds))
end

-- I3: firing WorkspaceTabActiveChanged with a registered project does not error.
do
  local proj = require("workspace.project").register({
    id = "explorer-probe", path = tmp_root, force = true,
  })
  require("workspace.tab").add_project_to_active(proj.id)
  local ok, err = pcall(function()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "WorkspaceTabActiveChanged",
      data = { project_id = proj.id },
    })
  end)
  check("I3 firing WorkspaceTabActiveChanged is error-free", ok, err)
end

-- I4: _tree_open is safe to call without a global Snacks (returns false).
do
  local prev_snacks = _G.Snacks
  _G.Snacks = nil
  local ok, opened = pcall(function()
    return require("workspace.integration.explorer")._tree_open()
  end)
  _G.Snacks = prev_snacks
  check("I4 explorer._tree_open is safe without Snacks (returns false)",
    ok and opened == false,
    string.format("ok=%s opened=%s", tostring(ok), tostring(opened)))
end

-- ---------------------------------------------------------------------------
-- J. Multi-root explorer (Scheme B) smoke
-- ---------------------------------------------------------------------------

-- J1: setup() with enabled=true does not error.
do
  package.loaded["workspace.integration.explorer_multiroot"] = nil
  local cfg = require("workspace.config").get()
  cfg.ui.explorer_multiroot = cfg.ui.explorer_multiroot or {}
  cfg.ui.explorer_multiroot.enabled = true
  local ok, err = pcall(function()
    require("workspace.integration.explorer_multiroot").setup()
  end)
  check("J1 explorer_multiroot.setup(enabled=true) runs without error", ok, err)
end

-- J2: augroup `WorkspaceExplorerMultiroot` exists when enabled.
do
  local has_group = false
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, {
    group = "WorkspaceExplorerMultiroot",
  })
  if ok then has_group = #autocmds > 0 end
  check("J2 WorkspaceExplorerMultiroot augroup exists when enabled",
    has_group,
    "autocmds=" .. vim.inspect(autocmds))
end

-- J3: firing 3 relevant events is error-free.
do
  local mr = require("workspace.integration.explorer_multiroot")
  local ok_total = true
  local last_err
  for _, pat in ipairs({
    "WorkspaceTabProjectAdded",
    "WorkspaceTabProjectRemoved",
    "WorkspaceTabActiveChanged",
  }) do
    local ok, err = pcall(function()
      vim.api.nvim_exec_autocmds("User", { pattern = pat, data = {} })
    end)
    if not ok then ok_total = false; last_err = err end
  end
  check("J3 firing TabProjectAdded/Removed/ActiveChanged is error-free",
    ok_total, tostring(last_err))
end

-- ---------------------------------------------------------------------------
-- K. Persistent tab/project state (state.json)
-- ---------------------------------------------------------------------------

-- K1: setup with default cfg creates state.json on first mutation.
do
  local k_dir = vim.fn.tempname()
  vim.fn.mkdir(k_dir, "p")
  -- Reset module-level state so the new setup binds to the new data_dir.
  pcall(vim.api.nvim_del_augroup_by_name, "WorkspacePersistState")
  require("workspace.tab.state")._reset()
  require("workspace.workspace.state")._reset()
  require("workspace.config")._reset()
  require("workspace.session.state")._reset()

  require("workspace").setup({
    data_dir = k_dir,
    session = { confirm_before_load = false, autoload_last_on_startup = false },
    persistent_state = { enabled = true, debounce_ms = 30 },
  })

  local pdir_k1 = k_dir .. "/proj_k1"
  vim.fn.mkdir(pdir_k1 .. "/.git", "p")
  require("workspace.project").register({ path = pdir_k1, id = "k1_proj" })
  require("workspace.tab").add_project_to_active("k1_proj")
  vim.wait(300, function()
    return vim.fn.filereadable(k_dir .. "/state.json") == 1
  end)
  check("K1 default cfg creates state.json on mutation",
    vim.fn.filereadable(k_dir .. "/state.json") == 1,
    "state.json missing at " .. k_dir)
end

-- K2: cold-start rehydration is error-free even when state.json exists.
do
  local k_dir = vim.fn.tempname()
  vim.fn.mkdir(k_dir, "p")
  -- Hand-craft a state.json.
  local f = io.open(k_dir .. "/state.json", "w")
  f:write(vim.json.encode({
    version = 1,
    tabs = {
      { id = "k2tab", label = "k2", order = 1, cwd = k_dir,
        project_ids = { "k2_proj" }, active_project_id = "k2_proj",
        nvim_state = "" },
    },
    active_tab_id = "k2tab",
    active_tab_index = 1,
  }))
  f:close()

  pcall(vim.api.nvim_del_augroup_by_name, "WorkspacePersistState")
  require("workspace.tab.state")._reset()
  require("workspace.workspace.state")._reset()
  require("workspace.config")._reset()
  require("workspace.session.state")._reset()

  local ok, err = pcall(function()
    require("workspace").setup({
      data_dir = k_dir,
      session = { confirm_before_load = false, autoload_last_on_startup = false },
      persistent_state = { enabled = true, debounce_ms = 30 },
    })
  end)
  -- The current tab should now carry the rehydrated project.
  local nr = vim.api.nvim_get_current_tabpage()
  local tab = require("workspace.tab.state").by_tabnr(nr)
  local has_proj = false
  if tab then
    for _, pid in ipairs(tab.project_ids or {}) do
      if pid == "k2_proj" then has_proj = true end
    end
  end
  check("K2 cold-start rehydration error-free + populates tab",
    ok and has_proj,
    string.format("ok=%s err=%s has_proj=%s", tostring(ok), tostring(err), tostring(has_proj)))
end

-- K3: setup with enabled=false does not create state.json.
do
  local k_dir = vim.fn.tempname()
  vim.fn.mkdir(k_dir, "p")
  pcall(vim.api.nvim_del_augroup_by_name, "WorkspacePersistState")
  require("workspace.tab.state")._reset()
  require("workspace.workspace.state")._reset()
  require("workspace.config")._reset()
  require("workspace.session.state")._reset()

  require("workspace").setup({
    data_dir = k_dir,
    session = { confirm_before_load = false, autoload_last_on_startup = false },
    persistent_state = { enabled = false },
  })
  local pdir_k3 = k_dir .. "/proj_k3"
  vim.fn.mkdir(pdir_k3 .. "/.git", "p")
  require("workspace.project").register({ path = pdir_k3, id = "k3_proj" })
  require("workspace.tab").add_project_to_active("k3_proj")
  vim.wait(200, function() return false end)
  check("K3 enabled=false does not create state.json",
    vim.fn.filereadable(k_dir .. "/state.json") == 0,
    "unexpected state.json at " .. k_dir)
end

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
print(string.format("=== %d PASS / %d FAIL ===", pass, fail))
if fail > 0 then os.exit(1) else os.exit(0) end
