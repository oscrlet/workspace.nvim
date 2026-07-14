# workspace.nvim — map

Single entry point. Each section points at its authoritative doc.

## 现状（2026-05）

Multi-project workspace plugin for Neovim with a 4-layer model
(Project / Session / Workspace / Tab), persistent sessions, snacks
picker integration, LSP multi-root, and a router.nvim subtree.

| pillar | status | doc / source-of-truth |
|---|---|---|
| Hierarchical model (project / session / workspace / tab) | shipped | [`README.md`](../README.md) §Overview |
| Persistence (sessions, `projects.json`, snapshot) | shipped | [`README.md`](../README.md) §Persistence |
| Public commands (`:Tab*`, `:Session*`, `:Project*`, `:Workspace*`) | shipped | [`README.md`](../README.md) §Commands |
| snacks.picker integration | shipped | `lua/workspace/integration/snacks.lua` |
| router.nvim subtree (drop-in subtree under root → workspace) | shipped | `lua/workspace/router_subtree/` |
| Multi-root explorer (Scheme B custom picker source) | shipped | [`DESIGN_NOTES.md`](../DESIGN_NOTES.md) |
| LSP multi-root | shipped | `lua/workspace/integration/lsp.lua` |
| tabufline integration | shipped | `lua/workspace/integration/tabufline.lua` |
| Plenary unit suite + regression | **243 / 0 / 0** + 41 regression | `test/spec/` + `test/regression.lua` |

## Integrations with router.nvim (cross-plugin)

| concern | wiring | router-side doc |
|---|---|---|
| Premium chrome on `:Tab*` pickers | router's global `Snacks.picker.pick` hook covers ALL picker callers, including workspace.nvim's `S.picker.files(...)` / `grep(...)` / `grep_word(...)` calls in `commands.lua` | [`../router.nvim/docs/MAP.md`](../../router.nvim/docs/MAP.md) — Premium chrome global hook |
| Chip bar for tab-scoped pickers | router chrome layer humanizes `opts.source` and builds a default `<Source> + cwd` chip set; no workspace-side change | [`../router.nvim/docs/chip-strip-tier3.md`](../../router.nvim/docs/chip-strip-tier3.md) |
| Show-delay perf | router's `cfg.picker_show_delay = 50` injected globally via chrome hook → `:TabGrepWord` no longer waits 5s for first batch | [`../router.nvim/docs/MAP.md`](../../router.nvim/docs/MAP.md) — Picker responsiveness |
| Router subtree exposure | `lua/workspace/router_subtree/init.lua` registers the workspace subtree on `root → workspace`; uses the router subtree DSL | [`../router.nvim/README.md`](../../router.nvim/README.md) §Defining a subtree |

## TODO

Active items live in the design / phase docs in the user's nvim config
(`~/.config/nvim/phase-brief-P*.md`). workspace.nvim itself currently
has no in-repo TODO file; treat regression test failures + the design
backlog as the to-do queue.

## Future directions

Not in scope today; each becomes a real plan when picked up.

| direction | sketch |
|---|---|
| Tab-scoped chip badges in router chip bar | first-class chip showing current tab name / project count, alongside cwd |
| Cross-root snapshot diff | preview snapshot diffs in a snacks preview pane |
| Project metadata sync | refresh `projects.json` when a tab root moves on disk |
| Session import / export | YAML / JSON portable session bundles |
| Auto-restore on startup | optional opt-in to restore the most-recent session on `nvim` without `:SessionLoad` |

## Cross-repo entry points

- [`../router.nvim/docs/MAP.md`](../../router.nvim/docs/MAP.md) — picker / chrome / theme system
- [`~/.config/nvim/MAP.md`](file:///Users/bytedance/.config/nvim/MAP.md) — user-side config meta-map covering all integrations
