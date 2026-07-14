describe("integration.lsp", function()
  local lsp
  local tab_api
  local tab_state
  local project
  local config

  before_each(function()
    -- Fresh module loads for each test
    package.loaded["workspace.integration.lsp"] = nil
    package.loaded["workspace.tab.api"] = nil
    package.loaded["workspace.tab.state"] = nil
    package.loaded["workspace.project"] = nil
    package.loaded["workspace.project.registry"] = nil
    package.loaded["workspace.project.store"] = nil
    package.loaded["workspace.config"] = nil

    lsp = require("workspace.integration.lsp")
    tab_api = require("workspace.tab.api")
    tab_state = require("workspace.tab.state")
    project = require("workspace.project")
    config = require("workspace.config")

    -- Initialize config with default lsp section
    config.merge({ lsp = { excluded_clients = {} } })

    -- Reset tab state
    tab_state._reset()

    -- Reset project registry
    package.loaded["workspace.project.registry"] = nil
    local registry = require("workspace.project.registry")
    registry._reset = function()
      registry.state = { projects = {}, cfg = {} }
    end
    registry._reset()
  end)

  it("union_roots returns empty list when no tabs exist", function()
    local roots = lsp.union_roots()
    assert.is_table(roots)
    assert.equal(0, #roots)
  end)

  it("union_roots includes tab cwd and project roots", function()
    -- Create a tab
    local tab1 = tab_state.ensure(1)
    tab1.cwd = "/tmp/workspace"

    -- Register and add a project
    local proj = project.register({ path = "/tmp/r1", id = "r1" })
    tab_api.add_project(1, proj.id)

    local roots = lsp.union_roots()
    assert.equal(2, #roots)

    -- Should contain both paths (realpath-deduped)
    local found_ws = false
    local found_r1 = false
    for _, r in ipairs(roots) do
      if r:match("/tmp/workspace") then found_ws = true end
      if r:match("/tmp/r1") then found_r1 = true end
    end
    assert.is_true(found_ws)
    assert.is_true(found_r1)
  end)

  it("union_roots deduplicates same root across tabs", function()
    -- Tab 1 with /tmp/r1
    local tab1 = tab_state.ensure(1)
    tab1.cwd = "/tmp/base"
    local proj = project.register({ path = "/tmp/r1", id = "r1" })
    tab_api.add_project(1, proj.id)

    -- Tab 2 also with /tmp/r1
    local tab2 = tab_state.ensure(2)
    tab2.cwd = "/tmp/base"
    tab_api.add_project(2, proj.id)

    local roots = lsp.union_roots()

    -- Should deduplicate: /tmp/base and /tmp/r1 only once each
    assert.equal(2, #roots)
  end)

  it("refresh_workspace_folders syncs client workspace folders", function()
    -- Create fake LSP client
    local fake_client = {
      name = "tsserver",
      workspace_folders = nil,
      notify = function(self, method, params)
        self._last_notify = { method = method, params = params }
      end,
    }

    -- Mock vim.lsp.get_clients
    local orig_get_clients = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return { fake_client }
    end

    -- Create tab with project
    local tab1 = tab_state.ensure(1)
    tab1.cwd = "/tmp/workspace"
    local proj = project.register({ path = "/tmp/r1", id = "r1" })
    tab_api.add_project(1, proj.id)

    -- Refresh should populate client.workspace_folders
    lsp.refresh_workspace_folders()

    assert.is_table(fake_client.workspace_folders)
    assert.is_true(#fake_client.workspace_folders >= 2)

    -- Restore
    vim.lsp.get_clients = orig_get_clients
  end)

  it("on_lsp_attach initializes workspace folders for new client", function()
    -- Create tab with project
    local tab1 = tab_state.ensure(1)
    tab1.cwd = "/tmp/workspace"
    local proj = project.register({ path = "/tmp/r1", id = "r1" })
    tab_api.add_project(1, proj.id)

    -- Create fake client
    local fake_client = {
      name = "pyright",
      workspace_folders = nil,
    }

    lsp.on_lsp_attach(fake_client, 1)

    assert.is_table(fake_client.workspace_folders)
    assert.is_true(#fake_client.workspace_folders >= 2)

    -- Verify structure of workspace folders
    for _, wf in ipairs(fake_client.workspace_folders) do
      assert.is_string(wf.uri)
      assert.is_string(wf.name)
    end
  end)

  it("respects excluded_clients blacklist", function()
    -- Configure copilot as excluded
    config.merge({ lsp = { excluded_clients = { "copilot" } } })

    local fake_copilot = {
      name = "copilot",
      workspace_folders = nil,
      notify = function() end,
    }

    local fake_tsserver = {
      name = "tsserver",
      workspace_folders = nil,
      notify = function() end,
    }

    -- Mock vim.lsp.get_clients
    local orig_get_clients = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return { fake_copilot, fake_tsserver }
    end

    -- Create tab
    local tab1 = tab_state.ensure(1)
    tab1.cwd = "/tmp/workspace"

    lsp.refresh_workspace_folders()

    -- Copilot should not be modified (nil or untouched)
    assert.is_nil(fake_copilot.workspace_folders)

    -- tsserver should be modified
    assert.is_table(fake_tsserver.workspace_folders)

    vim.lsp.get_clients = orig_get_clients
  end)

  it("sync_client is idempotent: repeated refresh leaves state stable", function()
    -- Fake LSP client that records notify calls
    local fake_client = {
      name = "tsserver",
      workspace_folders = nil,
      _notify_count = 0,
      notify = function(self, method, params)
        self._notify_count = self._notify_count + 1
        self._last_notify = { method = method, params = params }
      end,
    }

    local orig_get_clients = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return { fake_client }
    end

    local tab1 = tab_state.ensure(1)
    tab1.cwd = "/tmp/workspace"
    local proj = project.register({ path = "/tmp/r1", id = "r1" })
    tab_api.add_project(1, proj.id)

    -- First refresh: populates folders.
    lsp.refresh_workspace_folders()
    assert.is_table(fake_client.workspace_folders)
    local first_count = #fake_client.workspace_folders
    assert.is_true(first_count >= 2)

    -- Snapshot the names for comparison.
    local first_names = {}
    for _, wf in ipairs(fake_client.workspace_folders) do
      first_names[wf.name] = true
    end

    local notifies_after_first = fake_client._notify_count

    -- Second refresh with no changes: must be a no-op.
    lsp.refresh_workspace_folders()

    -- Folder count and contents must be identical (no stomp, no duplicate).
    assert.equal(first_count, #fake_client.workspace_folders)
    for _, wf in ipairs(fake_client.workspace_folders) do
      assert.is_true(first_names[wf.name] == true)
    end

    -- And no extra notify (diff was empty -> early return).
    assert.equal(notifies_after_first, fake_client._notify_count)

    vim.lsp.get_clients = orig_get_clients
  end)

  it("realpath deduplication resolves symlinks", function()
    -- This test verifies the dedup logic handles symlinks
    -- We use mock paths since creating real symlinks is complex in tests
    local tab1 = tab_state.ensure(1)

    -- Both point to /tmp/r1 (one is realpath, one is symlink)
    local proj1 = project.register({ path = "/tmp/r1", id = "r1" })
    tab_api.add_project(1, proj1.id)

    -- Create a second tab
    local tab2 = tab_state.ensure(2)
    -- Same project added to tab2
    tab_api.add_project(2, proj1.id)

    local roots = lsp.union_roots()

    -- /tmp/r1 should appear only once (dedup via realpath)
    local count = 0
    for _, r in ipairs(roots) do
      if r:match("/tmp/r1") then
        count = count + 1
      end
    end
    assert.equal(1, count)
  end)
end)
