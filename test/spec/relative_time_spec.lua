--- test/spec/relative_time_spec.lua
--- Busted: workspace.session.format_relative bucket boundaries.

local session = require("workspace.session")

describe("session.format_relative", function()
  local now = 1700000000 -- fixed reference

  it("returns 'just now' for diff < 5s", function()
    assert.equals("just now", session.format_relative(now, now))
    assert.equals("just now", session.format_relative(now - 4, now))
  end)

  it("returns Ns ago in [5, 60)", function()
    assert.equals("5s ago", session.format_relative(now - 5, now))
    assert.equals("59s ago", session.format_relative(now - 59, now))
  end)

  it("returns Nm ago in [60s, 60m)", function()
    assert.equals("1m ago", session.format_relative(now - 60, now))
    assert.equals("2m ago", session.format_relative(now - 120, now))
    assert.equals("59m ago", session.format_relative(now - 3599, now))
  end)

  it("returns Nh ago in [1h, 24h)", function()
    assert.equals("1h ago", session.format_relative(now - 3600, now))
    assert.equals("3h ago", session.format_relative(now - (3 * 3600), now))
    assert.equals("23h ago", session.format_relative(now - (86400 - 1), now))
  end)

  it("returns Nd ago in [1d, 30d)", function()
    assert.equals("1d ago", session.format_relative(now - 86400, now))
    assert.equals("3d ago", session.format_relative(now - (3 * 86400), now))
    assert.equals("29d ago", session.format_relative(now - (29 * 86400), now))
  end)

  it("returns YYYY-MM-DD for >= 30d", function()
    local epoch = now - (30 * 86400)
    local expected = os.date("%Y-%m-%d", epoch)
    assert.equals(expected, session.format_relative(epoch, now))
    local older = now - (365 * 86400)
    assert.equals(os.date("%Y-%m-%d", older), session.format_relative(older, now))
  end)

  it("clamps negative diffs to 'just now'", function()
    assert.equals("just now", session.format_relative(now + 100, now))
  end)

  it("uses os.time() default when now omitted", function()
    -- Should not error and should return a string.
    local s = session.format_relative(os.time())
    assert.equals("string", type(s))
  end)
end)
