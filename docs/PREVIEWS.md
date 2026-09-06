# Preview provenance

Generated on 2026-09-06 from a fresh Neovim 0.12.2 process with `-u NONE -i NONE`.
These PNGs render actual RGB `ext_linegrid` events, not invented UI mockups.
They do not include the desktop frame, OS font rasterizer, or animated transitions.

- Size: 132 columns × 40 rows, rendered at 1584 × 1080 pixels.
- Themes: Workbench built-in dark and light. This is an integration demonstration,
  not the default appearance of every independently installed plugin.
- Data: temporary example.lua and isolated Workspace storage; no user session data.
- Runtime: Workbench `103ef37`, Router `a625221`, Volt Picker `79c3bb2`,
  Workspace `540f9fd`, Volt `620de13`, Snacks `882c996`.
- Font rendering: Menlo / Apple Symbols with CodeNewRoman Nerd Font for PUA glyphs.
  Font files are not redistributed.
- Generator: host configuration `tests/readme_capture.py`; it uses the existing
  UI-test MessagePack codec and Pillow. No desktop or screen-recording permission.

Reproduce from the host configuration checkout on macOS:

```sh
python3 tests/readme_capture.py /path/to/plugins /path/to/lazy /path/to/CodeNewRomanNerdFontMono-Regular.otf
```

The first directory contains the four sibling plugin checkouts. The second contains
Volt and Snacks. The script replaces only its generated `docs/*-dark.png` and
`docs/*-light.png` outputs. Install Pillow in the selected Python environment.

The old `demo.png` is retained for historical links; the README now uses the explicitly named dark/light captures.
