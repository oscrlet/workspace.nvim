# Scheme B — Multi-root Explorer: Design Investigation

## 1. Snacks custom picker source registration (runtime)

Snacks supports custom sources via `Snacks.picker.sources` (= `snacks.picker.config.sources`),
which is a plain table indexed by source name. Reading `lua/snacks/picker/init.lua`:

- `M.pick(source, opts)` ultimately calls `require("snacks.picker.core.picker").new(opts)`.
- Inside core picker, `opts.source` is used to look up a base config from
  `Snacks.picker.sources[source]` and then merged with the call-site opts.
- `M.sources` is exposed via `__index` (`sources = "config.sources"`).

Therefore at runtime we can do:

```lua
Snacks.picker.sources.workspace_explorer = {
  finder = function(opts, ctx) ... end,
  format = "file",
  layout = { preset = "sidebar", preview = false },
  -- … additional config …
}

-- Open it with:
Snacks.picker.pick("workspace_explorer", { ... })
-- or:
Snacks.picker.pick({ source = "workspace_explorer" })
```

The `finder` field accepts a function `(opts, ctx) -> async-finder` (returns a function that
takes a `cb` callback to yield items), matching the pattern used by the explorer source itself
in `lua/snacks/picker/source/explorer.lua`.

**Conclusion:** runtime registration is a supported, first-class extension point. No
upstream patches needed.

## 2. Tree singleton and multiple roots

`lua/snacks/explorer/tree.lua` exposes a module-level singleton:

```lua
local Tree = ... -- single instance with one .root and one flat .nodes map
```

It is keyed by `norm(path)` and supports many roots in principle (any path can be inserted),
but the **explorer source** (`source/explorer.lua`) treats it as if it had one cwd:
`Tree:refresh(picker:cwd())` then `Tree:get(ctx.filter.cwd, ...)` walks descendants of one
cwd. There is no machinery to render multiple "top-level" nodes side by side under one
virtual super-root; the `Tree:get` walker is rooted at one node.

Reusing the singleton for true multi-root would mean either:
- inserting a synthetic super-root that points at each project (Tree.lua does not natively
  support this — `find()` parses one filesystem path per call), or
- patching Tree internals.

Both options leak workspace.nvim concerns deep into Snacks internals and break on Snacks
updates. We therefore ship our **own minimal item state** for v1 and leave Snacks's Tree
untouched.

## 3. Approach trade-offs

### A. Synthesized super-root via Tree node injection

- **How:** create a virtual Tree node whose children are real project root nodes; reuse
  the explorer source `M.explorer` finder by overriding `Tree:find(cwd)` to return the
  synthetic super-root for a sentinel cwd value.
- **Pros:** maximally reuses Snacks rendering, expand/collapse, git status, diagnostics.
- **Cons:**
  - Tree singleton is shared across explorer instances → mutating it for multi-root would
    break any concurrent single-root explorer.
  - `Tree:find` uses `vim.split(path, "/")` over a real fs path, so a sentinel cwd is
    impossible without monkey-patching.
  - Highly coupled to Snacks internals; breaks on Snacks upgrades.
- **Verdict:** rejected — fragility outweighs visual fidelity.

### B. Custom picker source `workspace_explorer`

- **How:** register `Snacks.picker.sources.workspace_explorer` whose finder yields one
  `{ file = root, dir = true, ... }` item per project on the current tab. Confirm action
  opens a regular single-root `Snacks.picker.explorer({ cwd = root })`. Refresh hook calls
  `Snacks.picker.get({ source = "workspace_explorer" })[1]:find()` on the 8 reactive events.
- **Pros:**
  - Zero coupling to Snacks Tree/explorer internals.
  - Top-level multi-root list is exactly the IDE "workspace folders" UX users expect.
  - Drill-down delegates back to Snacks's full-fidelity single-root explorer, so users
    keep git/diagnostics/file-ops inside each project.
  - Easy to extend later: in-place expansion can be added by yielding child nodes too.
- **Cons:**
  - v1 does not show file children inline at the top level — clicking opens a new
    single-root explorer rather than expanding in place.
  - No git_status / diagnostics overlay on the project rows themselves (deferred).
- **Verdict:** chosen.

### C. Multi-window tile (N parallel single-root explorers stacked vertically)

- **How:** open `#projects` Snacks.explorer instances tiled vertically in the sidebar.
- **Pros:** trivial; reuses Snacks unchanged.
- **Cons:**
  - Visually noisy; vertical real-estate is the limiting factor in a sidebar.
  - Each explorer keeps its own state/keymaps; cross-root nav is awkward.
  - No clean refresh path — managing N pickers' lifecycles on tab change is brittle.
- **Verdict:** kept as graceful-degrade fallback if B is BLOCKED, otherwise unused.

## 4. Chosen approach

**B. Custom picker source `workspace_explorer`.**

Rationale (one sentence): registering a custom source is a supported, stable Snacks
extension point; it gives clean top-level multi-root listing and delegates per-project
drill-down to the existing, full-fidelity Snacks.explorer — minimal coupling, predictable
lifecycle, easy to extend in v2.

## 5. v1 acceptance contract

### Must do (v1)

1. Top-level item list is the projects on the current tab (one row per project).
2. Each row is shaped `{ file = root, dir = true, text = name, type = "directory" }` so
   Snacks's stock `format = "file"` formatter renders them as folder icons + project name.
3. Selecting a row opens a single-root `Snacks.picker.explorer({ cwd = root })`.
4. Refresh on all 8 reactive events:
   `WorkspaceProjectRegistered`, `WorkspaceProjectUnregistered`, `WorkspaceProjectUpdated`,
   `WorkspaceSessionSaved`, `WorkspaceSessionDeleted`, `WorkspaceSessionRenamed`,
   `WorkspaceTabProjectAdded`, `WorkspaceTabProjectRemoved`. (Plus
   `WorkspaceTabActiveChanged` for tab-context reload, but it MUST NOT relocate the picker
   cwd — multi-root preserves all roots regardless of which is active.)
5. Default off: `cfg.ui.explorer_multiroot.enabled = false`. Existing single-root setup
   unaffected.
6. Empty tab (no projects) → `_items()` returns `{}` and emits a WARN notification; no
   raise.
7. `M.open()` calls `Snacks.picker.pick({ source = "workspace_explorer" })` exactly once
   per invocation.

### Deferred (out of scope for v1)

- Inline expansion of project subtrees in the same picker (would re-implement Tree).
- Diagnostics overlay on project rows.
- File-op actions (add/del/rename/copy/move) across roots from the multi-root view.
- Full `git_status` per project root.
- File-watch debouncing across multiple roots.
- Lazy/on-demand subtree loading.

These are tracked in a new "Future Work" entry in README.md (R4).
