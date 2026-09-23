# Omarchy Switcher

A focused visual window switcher for Omarchy.

Hold `Super`, press `Tab` to move through recent windows, then release
`Super` to switch. Windows are presented as a single horizontal strip of
previews in the center of the focused monitor.

![Omarchy Switcher](assets/switcher.png)

## Features

- `Super+Tab` opens the switcher and selects the previous window.
- Keep holding `Super` and press `Tab` to move forward.
- `Super+Shift+Tab` moves backward.
- Release `Super` to activate the selected window.
- Press `Esc` to cancel without changing focus.
- Windows follow Hyprland's MRU order via `focusHistoryID`.
- The preview strip stays on one row and scrolls horizontally when needed.
- Works across normal workspaces and monitors.
- Uses Quickshell `ScreencopyView` for one-frame window previews.
- No background daemon, persistent screenshot cache, or extra window database.

Omarchy Switcher intentionally stays small. It is a window switcher, not a
workspace overview, launcher, task manager, or window-management suite.

## Install

```bash
omarchy plugin add https://github.com/lsongdev/omarchy-switcher.git --enable
```

Plugin ID:

```text
org.lsong.window-switcher
```

The plugin takes over Omarchy's default `Super+Tab` and
`Super+Shift+Tab` workspace shortcuts while enabled.

## Usage

```text
hold Super
  ↓
press Tab
  ↓
select a window preview
  ↓
press Tab / Shift+Tab to move
  ↓
release Super
  ↓
focus selected window
```

The first forward switch selects the previously focused window, matching the
usual Alt+Tab-style MRU interaction.

## Remove

```bash
omarchy plugin remove org.lsong.window-switcher
```

Disabling or removing the plugin restores Omarchy's default
`Super+Tab` / `Super+Shift+Tab` workspace navigation.

## Shortcut conflicts

While enabled, the plugin manages these runtime Hyprland bindings:

```text
Super+Tab
Super+Shift+Tab
Super_L release
Super_R release
```

Hyprland's runtime binding API does not provide plugin ownership metadata for a
key chord. Custom user bindings using the same shortcuts therefore conflict
with Omarchy Switcher.

The plugin does not edit `~/.config/hypr/bindings.lua` or other user
configuration files. Bindings are installed at runtime and restored when the
plugin unloads.

## Requirements

- Omarchy Quattro with shell plugin support
- Hyprland
- Quickshell with `ScreencopyView`

There are no additional packages or background services to install.

## How it works

Each switching session takes one fresh snapshot of Hyprland's client list:

```text
hyprctl clients -j
        ↓
sort by focusHistoryID
        ↓
match Quickshell toplevels
        ↓
horizontal preview strip
        ↓
focus selected Hyprland address
```

Window previews are captured in memory and are not written to disk.

See [docs/DESIGN.md](docs/DESIGN.md) for the architecture, state machine,
window-selection rules, and implementation constraints.

## Development

Validate the plugin:

```bash
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" Switcher.qml
```

Plugin files under `~/.config/omarchy/plugins/` hot-reload. Because the
service also owns runtime keybindings, restart Omarchy Shell after changing
binding logic:

```bash
omarchy restart shell
```

Useful diagnostics:

```bash
hyprctl binds -j | jq '.[] | select(.description | test("Switcher"))'
journalctl --user -u omarchy-shell.service -n 100 --no-pager
```

## License

MIT
