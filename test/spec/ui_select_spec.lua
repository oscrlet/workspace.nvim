-- Verifies the router-styled vim.ui.select override:
-- * install() replaces vim.ui.select
-- * with Snacks present, M.select drives Snacks.picker.pick with the items
--   and confirm action, and on_choice receives the selected value
-- * Esc / on_close path delivers nil per vim.ui.select contract
-- * without Snacks, falls back to the previously-saved vim.ui.select

local ui_select = require("workspace.integration.ui_select")

describe("integration.ui_select", function()
  local saved_ui_select
  local saved_snacks

  before_each(function()
    saved_ui_select = vim.ui.select
    saved_snacks = _G.Snacks
    ui_select._previous_select = nil
  end)

  after_each(function()
    vim.ui.select = saved_ui_select
    _G.Snacks = saved_snacks
  end)

  it("install() replaces vim.ui.select and stashes the previous impl", function()
    local prev = function() end
    vim.ui.select = prev
    ui_select.install()
    assert.equals(ui_select.select, vim.ui.select)
    assert.equals(prev, ui_select._previous_select)
  end)

  it("install() is idempotent", function()
    ui_select.install()
    local prev_after_first = ui_select._previous_select
    ui_select.install()
    -- Second install must not capture the now-installed select as previous.
    assert.equals(prev_after_first, ui_select._previous_select)
  end)

  it("with Snacks: delegates to Snacks.picker.select (compact dropdown source)", function()
    local got_items, got_opts, got_cb
    _G.Snacks = {
      picker = {
        select = function(items, opts, cb)
          got_items, got_opts, got_cb = items, opts, cb
        end,
      },
    }

    local handler = function(v, i) end
    ui_select.select({ "Load", "Cancel" },
      { prompt = "Load session?" },
      handler)

    assert.is_table(got_items)
    assert.equals(2, #got_items)
    assert.equals("Load", got_items[1])
    assert.equals("Cancel", got_items[2])
    assert.equals("Load session?", got_opts.prompt)
    assert.equals(handler, got_cb)
  end)

  it("with Snacks: forwards items/opts/cb to Snacks.picker.select", function()
    local got_items, got_opts, got_cb
    _G.Snacks = {
      picker = {
        select = function(items, opts, cb)
          got_items, got_opts, got_cb = items, opts, cb
        end,
      },
    }
    local handler = function() end
    ui_select.select({ "a", "b" }, { prompt = "?" }, handler)
    assert.is_table(got_items)
    assert.equals(2, #got_items)
    assert.equals("a", got_items[1])
    assert.equals("?", got_opts.prompt)
    assert.equals(handler, got_cb)
  end)

  it("with host-pinned layout: overrides into opts.snacks.layout + hidden preview", function()
    local got_opts
    _G.Snacks = {
      config = { picker = { layout = { preset = "router_block" } } },
      picker = {
        select = function(_, opts, _) got_opts = opts end,
      },
    }
    ui_select.select({ "a", "b" }, { prompt = "?" }, function() end)
    assert.is_table(got_opts.snacks)
    assert.equals("router_block", got_opts.snacks.layout.preset)
    assert.same({ "preview" }, got_opts.snacks.layout.hidden)
  end)

  it("with host-pinned layout as string: normalizes to table form", function()
    local got_opts
    _G.Snacks = {
      config = { picker = { layout = "router_block" } },
      picker = {
        select = function(_, opts, _) got_opts = opts end,
      },
    }
    ui_select.select({ "a", "b" }, {}, function() end)
    assert.is_table(got_opts.snacks.layout)
    assert.equals("router_block", got_opts.snacks.layout.preset)
    assert.same({ "preview" }, got_opts.snacks.layout.hidden)
  end)

  it("without host-pinned layout: leaves opts.snacks unset", function()
    local got_opts
    _G.Snacks = {
      config = { picker = {} },
      picker = {
        select = function(_, opts, _) got_opts = opts end,
      },
    }
    ui_select.select({ "a", "b" }, {}, function() end)
    assert.is_nil(got_opts.snacks)
  end)

  it("without Snacks: forwards to the stashed previous vim.ui.select", function()
    _G.Snacks = nil
    local prev_called_with
    ui_select._previous_select = function(items, opts, cb)
      prev_called_with = { items = items, opts = opts, cb = cb }
    end
    ui_select.select({ "x", "y" }, { prompt = "?" }, function() end)
    assert.is_table(prev_called_with)
    assert.equals(2, #prev_called_with.items)
    assert.equals("?", prev_called_with.opts.prompt)
  end)
end)
