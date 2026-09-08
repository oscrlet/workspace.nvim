-- nvim --headless -u NONE -i NONE -l test/windows_regression.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
local temp = vim.fn.tempname() .. '-workspace-regression'
local cfg = require('workspace.config').merge({ data_dir = temp,
  session = { confirm_before_load = false }, persistent_state = { enabled = false } })
local session = require('workspace.session.store')
local template = require('workspace.template.store')
local project = require('workspace.project.store')
local persist = require('workspace.state.persist')
local function overwrite(store, name)
  local function write(data)
    if name then return store.write(name, data) end
    return store.write(data)
  end
  assert(write({ version = 1, tabs = {}, projects = {}, revision = 1 }))
  assert(write({ version = 1, tabs = {}, projects = {}, revision = 2 }))
  assert(store.read(name).revision == 2, 'overwrite must persist the latest revision')
end
overwrite(session, 'probe.with.dots')
overwrite(template, 'probe.with.dots')
overwrite(project)
overwrite(persist)
for _, slash in ipairs({ false, true }) do
  if vim.fn.has('win32') == 1 then vim.o.shellslash = slash end
  assert(session.list()[1].name == 'probe.with.dots', 'session name must exclude directories')
  assert(template.list()[1].name == 'probe.with.dots', 'template name must exclude directories')
  assert(session.read(session.list()[1].name).revision == 2)
end
if vim.fn.has('win32') == 1 then vim.o.shellslash = false end
local locks = require('workspace.session.state')
assert(locks.acquire_lock('probe'))
assert(not locks.acquire_lock('probe'), 'live process lock must be respected on Windows')
locks.release_lock('probe')
vim.fn.writefile({ 'invalid-stale-pid' }, temp .. '/sessions/.locks/probe.lock')
assert(locks.acquire_lock('probe'), 'invalid stale lock must be recoverable')
locks.release_lock('probe')

-- Full save -> overwrite -> list -> load: verify real files, splits and cursor.
require('workspace.project').setup(cfg)
local tab = require('workspace.tab.state').ensure(vim.api.nvim_get_current_tabpage())
tab.cwd = temp
local one, two = temp .. '/one.lua', temp .. '/two.lua'
vim.fn.writefile({ 'local one = 1', 'return one' }, one)
vim.fn.writefile({ 'local two = 2', 'return two' }, two)
vim.cmd.edit(vim.fn.fnameescape(one))
vim.cmd.vsplit(vim.fn.fnameescape(two))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local api = require('workspace.session.api')
assert(api.save('roundtrip'))
vim.api.nvim_win_set_cursor(0, { 1, 0 })
assert(api.save('roundtrip'))
vim.cmd.only()
vim.cmd.enew()
assert(api.load('roundtrip', { force = true }))
assert(#vim.api.nvim_tabpage_list_wins(0) == 2, 'session must restore both splits')
local found = {}
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local name = vim.fs.basename(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))
  found[name] = vim.api.nvim_win_get_cursor(win)[1]
end
assert(found['one.lua'] == 1 and found['two.lua'] == 1, 'must restore overwritten cursor state')
assert(api.current() == 'roundtrip')
print('Workspace Windows regression: overwrite x4, names, locks, session roundtrip passed')
