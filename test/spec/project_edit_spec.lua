--- test/spec/project_edit_spec.lua
--- Busted: :ProjectEdit interactive metadata editor.

local commands   = require("workspace.commands")
local registry   = require("workspace.project.registry")
local proj_store = require("workspace.project.store")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function rmdir(d) vim.fn.delete(d, "rf") end

describe(":ProjectEdit", function()
  local proj_dir, root_a, root_b
  local orig_notify, orig_input
  local notifies, inputs_queue, captured_pick
  local update_events

  before_each(function()
    -- Isolate registry store.
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    root_a = tmpdir()
    root_b = tmpdir()
    -- Account for fs_realpath symlink resolution inside the registry.
    root_a = (vim.uv and vim.uv.fs_realpath and vim.uv.fs_realpath(root_a)) or root_a
    root_b = (vim.uv and vim.uv.fs_realpath and vim.uv.fs_realpath(root_b)) or root_b
    registry.register({ path = root_a, id = "alpha", name = "Alpha", meta = { lang = "lua" } })

    -- Capture notifications.
    notifies = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level) table.insert(notifies, { msg = msg, level = level }) end

    -- Stub vim.ui.input — fed from inputs_queue.
    inputs_queue = {}
    orig_input = vim.ui.input
    vim.ui.input = function(opts, on_confirm)
      local entry = table.remove(inputs_queue, 1)
      -- entry can be a string, nil-marker, or a function(opts) -> answer
      local answer
      if type(entry) == "function" then
        answer = entry(opts)
      elseif entry == "<<NIL>>" then
        answer = nil
      else
        answer = entry
      end
      on_confirm(answer)
    end

    -- Stub Snacks.picker.pick.
    captured_pick = nil
    _G.Snacks = {
      picker = {
        pick = function(spec)
          captured_pick = spec
          return spec
        end,
      },
    }

    -- Listen for WorkspaceProjectUpdated events.
    update_events = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "WorkspaceProjectUpdated",
      callback = function(args)
        table.insert(update_events, args.data)
      end,
    })

    commands.setup_project_commands()
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.ui.input = orig_input
    _G.Snacks = nil
    pcall(vim.api.nvim_clear_autocmds, { event = "User", pattern = "WorkspaceProjectUpdated" })
    proj_store._path = nil
    rmdir(proj_dir)
    rmdir(root_a)
    rmdir(root_b)
  end)

  it("edits name + root → registry reflects changes, id preserved, event fired", function()
    -- Order: name, root, meta JSON.
    inputs_queue = {
      "RenamedAlpha",
      root_b,
      vim.json.encode({ lang = "rust" }),
    }
    vim.cmd("ProjectEdit alpha")
    -- Drain scheduled callbacks.
    vim.wait(50, function() return false end)

    local p = registry.get("alpha")
    assert.is_table(p)
    assert.equals("alpha", p.id)
    assert.equals("RenamedAlpha", p.name)
    assert.equals(root_b, p.root)
    assert.equals("rust", p.meta.lang)

    assert.is_true(#update_events >= 1)
    local last = update_events[#update_events]
    assert.equals("alpha", last.id)
    assert.equals("RenamedAlpha", last.project.name)
  end)

  it("aborting (vim.ui.input → nil) cancels without partial mutation", function()
    inputs_queue = {
      "ShouldNotApply",
      "<<NIL>>",  -- abort on root step
      "ignored",
    }
    update_events = {}
    vim.cmd("ProjectEdit alpha")
    vim.wait(50, function() return false end)

    local p = registry.get("alpha")
    assert.equals("Alpha", p.name)
    assert.equals(root_a, p.root)
    assert.equals("lua", p.meta.lang)
    assert.equals(0, #update_events)
  end)

  it("invalid meta JSON shows error notify and does not mutate registry", function()
    inputs_queue = {
      "Alpha2",
      root_a,
      "{not valid json",
    }
    update_events = {}
    vim.cmd("ProjectEdit alpha")
    vim.wait(50, function() return false end)

    local p = registry.get("alpha")
    -- Pre-meta fields untouched because update never ran.
    assert.equals("Alpha", p.name)
    assert.equals(root_a, p.root)
    assert.equals(0, #update_events)

    local saw_invalid = false
    for _, n in ipairs(notifies) do
      if type(n.msg) == "string" and n.msg:match("invalid meta JSON") then
        saw_invalid = true
        break
      end
    end
    assert.is_true(saw_invalid)
  end)

  it("unknown id triggers error notify", function()
    vim.cmd("ProjectEdit nope_unknown")
    local saw = false
    for _, n in ipairs(notifies) do
      if type(n.msg) == "string" and n.msg:match("no such project") then
        saw = true
        break
      end
    end
    assert.is_true(saw)
  end)

  it("empty arg triggers project picker", function()
    vim.cmd("ProjectEdit")
    assert.is_not_nil(captured_pick)
    assert.is_table(captured_pick.items)
    assert.equals("Edit project", captured_pick.title)
  end)
end)
