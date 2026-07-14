-- Verifies the mksession backend captures and restores per-tab state.
-- Focus: sanitization correctness + window-count roundtrip.

local mks = require("workspace.snapshot.mksession")

local function tmpfile(content)
  local p = vim.fn.tempname()
  local f = io.open(p, "w"); f:write(content or "x\n"); f:close()
  return vim.uv.fs_realpath(p) or p
end

describe("workspace.snapshot.mksession", function()
  describe("sanitization", function()
    it("drops cross-tab control commands", function()
      local raw = table.concat({
        "let SessionLoad = 1",
        "silent only",
        "silent tabonly",
        "tabnew",
        "tabnext 2",
        "tabprevious",
        "tabfirst",
        "tablast",
        "edit somefile",
        "badd otherfile",
        "wincmd =",
        "set lines=42",
        "unlet SessionLoad",
      }, "\n")
      local out = mks._sanitize(raw)
      assert.is_nil(out:match("silent only"))
      assert.is_nil(out:match("silent tabonly"))
      -- Bare `tabnew` and tab-nav lines should be gone.
      assert.is_nil(out:match("\ntabnew\n"))
      assert.is_nil(out:match("tabnext"))
      assert.is_nil(out:match("tabprevious"))
      assert.is_nil(out:match("tabfirst"))
      assert.is_nil(out:match("tablast"))
      -- Useful lines preserved.
      assert.truthy(out:match("edit somefile"))
      assert.truthy(out:match("badd otherfile"))
      assert.truthy(out:match("wincmd ="))
      assert.truthy(out:match("set lines=42"))
      assert.truthy(out:match("let SessionLoad = 1"))
      assert.truthy(out:match("unlet SessionLoad"))
    end)
  end)

  describe("kind / available", function()
    it("reports kind='mksession' and is always available", function()
      assert.equals("mksession", mks.kind)
      assert.is_true(mks.available())
    end)
  end)

  describe("capture / restore roundtrip", function()
    before_each(function()
      pcall(vim.cmd, "silent! tabonly")
      pcall(vim.cmd, "silent! enew")
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end)

    it("captures a vsplit and restores ≥2 windows", function()
      local f1 = tmpfile("alpha\n")
      local f2 = tmpfile("beta\n")
      vim.cmd("edit " .. vim.fn.fnameescape(f1))
      vim.cmd("vsplit " .. vim.fn.fnameescape(f2))

      local nr = vim.api.nvim_get_current_tabpage()
      local blob = mks.capture(nr)
      assert.is_table(blob)
      assert.equals("mksession", blob.kind)
      assert.is_string(blob.script)
      assert.truthy(#blob.script > 0)
      -- Sanitization invariants hold on the live capture too.
      assert.is_nil(blob.script:match("\nsilent only\n"))
      assert.is_nil(blob.script:match("\nsilent tabonly"))

      -- Wipe windows + buffers, restore.
      pcall(vim.cmd, "silent only")
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end

      mks.restore(blob, nr)
      local wins = vim.api.nvim_tabpage_list_wins(nr)
      assert.is_true(#wins >= 2,
        "expected ≥2 windows after mksession restore, got " .. #wins)
    end)
  end)
end)
