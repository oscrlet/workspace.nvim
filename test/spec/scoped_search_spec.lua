--- test/spec/scoped_search_spec.lua
--- Busted: test scoped grep/find pickers with tab scope_roots.

local tab_state   = require("workspace.tab.state")
local tab_api     = require("workspace.tab.api")
local ses_api     = require("workspace.session.api")
local proj_store  = require("workspace.project.store")
local registry    = require("workspace.project.registry")
local snacks_m    = require("workspace.integration.snacks")

-- Temp dir helper.
local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

-- Remove a directory tree (best-effort).
local function rmdir(d)
  vim.fn.delete(d, "rf")
end

describe("scoped_search (snacks integration)", function()
  local proj_dir
  local r1, r2
  local p1, p2

  before_each(function()
    -- Isolate project store.
    proj_dir = tmpdir()
    proj_store._path = proj_dir .. "/projects.json"
    registry.setup({})

    -- Reset in-memory tab state.
    tab_state._reset()

    -- Create temp roots
    r1 = tmpdir()
    r2 = tmpdir()

    -- Register projects
    p1 = registry.register({ path = r1, name = "P1" })
    p2 = registry.register({ path = r2, name = "P2" })
  end)

  after_each(function()
    tab_state._reset()
    proj_store._path = nil
    rmdir(proj_dir)
    rmdir(r1)
    rmdir(r2)
  end)

  it("grep_tab() captures roots when tab has projects", function()
    -- Stub Snacks.picker.grep to capture last opts
    _G._captured_grep = nil
    local stub_S = {
      picker = {
        grep = function(opts)
          _G._captured_grep = opts
        end,
      },
    }
    _G.Snacks = stub_S

    -- Setup: add 2 projects to tab 1
    tab_api.add_project(1, p1.id)
    tab_api.add_project(1, p2.id)

    -- Call grep_tab
    snacks_m.grep_tab({})

    -- Verify opts.dirs contains both roots (realpath-deduped)
    assert.is_not_nil(_G._captured_grep)
    assert.is_table(_G._captured_grep.dirs)
    assert.equal(2, #_G._captured_grep.dirs)
    -- Roots should be realpath'd
    assert.is_string(_G._captured_grep.dirs[1])
    assert.is_string(_G._captured_grep.dirs[2])

    _G.Snacks = nil
    _G._captured_grep = nil
  end)

  it("find_tab() captures roots when tab has projects", function()
    -- Stub Snacks.picker.files to capture last opts
    _G._captured_find = nil
    local stub_S = {
      picker = {
        files = function(opts)
          _G._captured_find = opts
        end,
      },
    }
    _G.Snacks = stub_S

    -- Setup: add 2 projects
    tab_api.add_project(1, p1.id)
    tab_api.add_project(1, p2.id)

    -- Call find_tab
    snacks_m.find_tab({})

    -- Verify opts.dirs contains both roots
    assert.is_not_nil(_G._captured_find)
    assert.is_table(_G._captured_find.dirs)
    assert.equal(2, #_G._captured_find.dirs)

    _G.Snacks = nil
    _G._captured_find = nil
  end)

  it("grep_tab() falls back to cwd when no projects", function()
    -- Stub Snacks.picker.grep
    _G._captured_grep = nil
    local stub_S = {
      picker = {
        grep = function(opts)
          _G._captured_grep = opts
        end,
      },
    }
    _G.Snacks = stub_S

    -- Empty tab, no projects
    -- Call grep_tab
    snacks_m.grep_tab({})

    -- Should fallback to getcwd()
    assert.is_not_nil(_G._captured_grep)
    assert.is_table(_G._captured_grep.dirs)
    assert.equal(1, #_G._captured_grep.dirs)
    assert.is_string(_G._captured_grep.dirs[1])

    _G.Snacks = nil
    _G._captured_grep = nil
  end)

  it("grep_workspace() unions across all tabs", function()
    -- Stub Snacks.picker.grep
    _G._captured_grep = nil
    local stub_S = {
      picker = {
        grep = function(opts)
          _G._captured_grep = opts
        end,
      },
    }
    _G.Snacks = stub_S

    -- Create 2 tabs with different projects
    tab_api.add_project(1, p1.id)
    tab_api.add_project(2, p2.id)

    -- Call grep_workspace
    snacks_m.grep_workspace({})

    -- Should union both projects' roots
    assert.is_not_nil(_G._captured_grep)
    assert.is_table(_G._captured_grep.dirs)
    assert.equal(2, #_G._captured_grep.dirs)

    _G.Snacks = nil
    _G._captured_grep = nil
  end)

  it("Snacks not loaded returns nil and notifies", function()
    _G.Snacks = nil

    -- Suppress vim.notify output for test
    local notify_called = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      notify_called = true
    end

    local result = snacks_m.grep_tab({})

    -- Should return nil and have notified
    assert.is_nil(result)
    assert.is_true(notify_called)

    vim.notify = orig_notify
  end)

  it("scoped_grep_picker returns nil when Snacks missing", function()
    _G.Snacks = nil

    local notify_called = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      notify_called = true
    end

    local result = snacks_m.scoped_grep_picker({})

    assert.is_nil(result)
    assert.is_true(notify_called)

    vim.notify = orig_notify
  end)

  -- F17 regression: the two-step picker→grep flow rewritten in 3ff0861 must
  -- (a) open the project picker with all known projects,
  -- (b) on confirm, commit the multi-selection (or fall back to current item),
  -- (c) close the project picker, and
  -- (d) launch S.picker.grep with `dirs` populated from the chosen roots
  --     while preserving caller `opts` (e.g. `search`).
  describe("scoped_grep_picker two-step flow (F17 regression)", function()
    local function install_stub_snacks(captured, selected_factory)
      _G.Snacks = {
        picker = {
          pick = function(spec)
            captured.pick_spec = spec
            local fake = {
              selected = function(_, _)
                return selected_factory(spec)
              end,
              current = function(_)
                return spec.items[1]
              end,
              close = function(_)
                captured.closed = true
              end,
            }
            spec.actions.confirm(fake)
          end,
          grep = function(opts)
            captured.grep_opts = opts
          end,
          files = function(opts)
            captured.files_opts = opts
          end,
        },
      }
    end

    it("multi-select commits both roots and triggers grep with dirs + opts", function()
      local captured = {}
      install_stub_snacks(captured, function(spec)
        return { spec.items[1], spec.items[2] }
      end)

      snacks_m.scoped_grep_picker({ search = "needle" })

      -- (a) project picker was opened with both projects
      assert.is_not_nil(captured.pick_spec)
      assert.equal("Select projects for grep", captured.pick_spec.title)
      assert.equal(2, #captured.pick_spec.items)

      -- (c) project picker was closed before launching grep
      assert.is_true(captured.closed)

      -- (d) grep called with dirs populated and opts preserved
      assert.is_not_nil(captured.grep_opts)
      assert.equal(2, #captured.grep_opts.dirs)
      assert.equal("needle", captured.grep_opts.search)

      _G.Snacks = nil
    end)

    it("falls back to picker:current() when nothing multi-selected", function()
      local captured = {}
      install_stub_snacks(captured, function(_)
        return {} -- empty :selected() — should fall back to :current()
      end)

      registry.register({ path = r1, name = "P1-extra" }) -- no-op-ish; r1 already there
      snacks_m.scoped_grep_picker({})

      assert.is_not_nil(captured.grep_opts)
      assert.equal(1, #captured.grep_opts.dirs)
      assert.is_true(captured.closed)

      _G.Snacks = nil
    end)

    it("zero selection (no current, empty :selected) does not call grep", function()
      local captured = {}
      _G.Snacks = {
        picker = {
          pick = function(spec)
            captured.pick_spec = spec
            local fake = {
              selected = function() return {} end,
              current = function() return nil end,
              close = function() captured.closed = true end,
            }
            spec.actions.confirm(fake)
          end,
          grep = function(opts) captured.grep_opts = opts end,
        },
      }

      snacks_m.scoped_grep_picker({})

      assert.is_not_nil(captured.pick_spec)
      assert.is_true(captured.closed)
      assert.is_nil(captured.grep_opts)

      _G.Snacks = nil
    end)

    it("scoped_find_picker mirrors the two-step flow into S.picker.files", function()
      local captured = {}
      install_stub_snacks(captured, function(spec)
        return { spec.items[1], spec.items[2] }
      end)

      snacks_m.scoped_find_picker({ search = "main.lua" })

      assert.is_not_nil(captured.pick_spec)
      assert.equal("Select projects for find", captured.pick_spec.title)
      assert.is_true(captured.closed)
      assert.is_not_nil(captured.files_opts)
      assert.equal(2, #captured.files_opts.dirs)
      assert.equal("main.lua", captured.files_opts.search)

      _G.Snacks = nil
    end)
  end)

end)
