--- test/spec/snacks_format_spec.lua
--- Busted: integration.snacks make_format / normalize_item helpers.
--- Guards against the recurring picker shape footgun (flat row instead of
--- nested rows) and against missing `text` on picker items.

local snacks_int = require("workspace.integration.snacks")

describe("integration.snacks.make_format", function()
  it("returns nested rows shaped {{str, hl}, ...}", function()
    local fmt = snacks_int.make_format({
      { "name", "SnacksPickerLabel" },
      { "root", "SnacksPickerComment" },
    })
    local row = fmt({ name = "alpha", root = "/tmp/alpha" })
    assert.equals("table", type(row))
    assert.equals("table", type(row[1]))
    assert.equals("string", type(row[1][1]))
    assert.equals("alpha", row[1][1])
    assert.equals("SnacksPickerLabel", row[1][2])
    assert.equals("table", type(row[2]))
    assert.equals("/tmp/alpha", row[2][1])
    assert.equals("SnacksPickerComment", row[2][2])
  end)

  it("resolves segment with function value", function()
    local fmt = snacks_int.make_format({
      { function(it) return it.label end, "Hl" },
    })
    local row = fmt({ label = "hello" })
    assert.equals("hello", row[1][1])
    assert.equals("Hl", row[1][2])
  end)

  it("applies width opt as left-pad", function()
    local fmt = snacks_int.make_format({
      { "name", "SnacksPickerLabel", { width = 10 } },
    })
    local row = fmt({ name = "x" })
    assert.equals(10, #row[1][1])
    assert.equals("x         ", row[1][1])
  end)

  it("defaults missing key to empty string and missing hl to Normal", function()
    local fmt = snacks_int.make_format({
      { "missing" },
    })
    local row = fmt({})
    assert.equals("", row[1][1])
    assert.equals("Normal", row[1][2])
  end)

  it("matches project_picker spec shape on a sample item", function()
    -- Same spec used in project_picker / tab_projects_picker.
    local fmt = snacks_int.make_format({
      { "name", "SnacksPickerLabel", { width = 24 } },
      { function(it) return " " .. (it.root or "") end, "SnacksPickerComment" },
    })
    local row = fmt({ id = "p1", name = "myproj", root = "/tmp/myproj" })
    assert.equals("table", type(row))
    assert.equals("table", type(row[1]))
    assert.equals("string", type(row[1][1]))
    assert.equals(24, #row[1][1])
    assert.is_truthy(row[1][1]:match("^myproj"))
    assert.equals(" /tmp/myproj", row[2][1])
    assert.equals("SnacksPickerComment", row[2][2])
  end)
end)

describe("integration.snacks.normalize_item", function()
  it("backfills text from label", function()
    local it = snacks_int.normalize_item({ label = "L", name = "N", id = "I" })
    assert.equals("L", it.text)
  end)

  it("backfills text from name when label missing", function()
    local it = snacks_int.normalize_item({ name = "N", id = "I" })
    assert.equals("N", it.text)
  end)

  it("backfills text from id when label and name missing", function()
    local it = snacks_int.normalize_item({ id = "I" })
    assert.equals("I", it.text)
  end)

  it("falls back to empty string when no candidate present", function()
    local it = snacks_int.normalize_item({})
    assert.equals("", it.text)
  end)

  it("preserves existing non-empty text", function()
    local it = snacks_int.normalize_item({ text = "keep", label = "L" })
    assert.equals("keep", it.text)
  end)

  it("is idempotent", function()
    local it = snacks_int.normalize_item({ label = "L" })
    local first = it.text
    snacks_int.normalize_item(it)
    snacks_int.normalize_item(it)
    assert.equals(first, it.text)
    assert.equals("L", it.text)
  end)

  it("returns non-table values unchanged", function()
    assert.equals("nope", snacks_int.normalize_item("nope"))
    assert.equals(nil, snacks_int.normalize_item(nil))
  end)
end)
