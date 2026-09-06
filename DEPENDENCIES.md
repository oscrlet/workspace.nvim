# Dependencies and licensing

Audited against this local checkout on 2026-09-06. This is an engineering inventory,
not a legal opinion or a certification of every historical contribution.

## Runtime boundary

| Capability | Dependency | Scope |
| --- | --- | --- |
| Registry, tab model, built-in snapshots | Neovim | Core |
| Shipped picker/search UI | Snacks | Required for these commands |
| Hierarchical route UI | Router | Optional; explicit registration supported |
| Alternative snapshot | resession.nvim | Optional; falls back to winlayout |
| Application surfaces | Workbench + Volt chain | Optional, host-owned |
| Tabline compatibility | NvChad | Optional; set integration='none' to opt out |
| Picker language/tools | rg / fd / git; eza/tree previews | Source-specific |
| Plenary / Telescope | None | No runtime imports; Telescope adapter not implemented |

Each plugin is configured by the host. This repository does not vendor or install
its runtime dependencies. A require() integration is not permission to relicense
upstream code. Private Snacks module compatibility should be tested when updating
Snacks; pin known-working revisions in the host plugin-manager lockfile.

## Upstream licenses

| Upstream | License observed in installed checkout | Reference |
| --- | --- | --- |
| Snacks | Apache-2.0 | [LICENSE](https://github.com/folke/snacks.nvim/blob/main/LICENSE) |
| Volt | GPL-3.0 | [LICENSE](https://github.com/nvzone/volt/blob/main/LICENSE) |
| Base46 | MIT, including Base16 notices | [LICENSE](https://github.com/NvChad/base46/blob/master/LICENSE), [Base16 notice](https://github.com/NvChad/base46/blob/master/base16-LICENSE) |
| NvChad | GPL-3.0 | [LICENSE](https://github.com/NvChad/NvChad/blob/v2.5/LICENSE) |

The project license covers its own code only. Do not label a distribution that
includes Volt or NvChad as MIT-only. Distribution of a combined/derived work may
carry GPL obligations; separately downloading a dependency is not a blanket
exemption. Review the actual combination and preserve upstream source, licenses,
notices and corresponding-source obligations where applicable.

Snacks Apache notices also remain upstream-owned; preserve applicable LICENSE
and NOTICE files if redistributing its code. Optional tool plugins and fonts
retain their own licenses and are not bundled here. See the
[MIT text](https://opensource.org/license/mit) and
[GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html#GPLModuleLicense).

## Repository license and provenance

Repository-authored code and documentation are licensed under [MIT](LICENSE).
On 2026-09-06, the maintainer confirmed that the historical
`katharinakinniburgh81` author/email identity was their own misconfigured Git
identity, not a separate contributor. This confirmation resolves that identity
question; it does not change any third-party license.

The audit checked runtime imports, repository remotes, current license files and
explicit attribution markers. It does not rule out historical copying. Preserve
original notices for any third-party snippets rather than replacing them with
the repository author's name.
