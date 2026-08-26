# Tableau

Tableau saves complete Omarchy desktops.

A tableau can open:

- workspaces
- terminal sessions
- applications
- background services

Choose a tableau from the bar. Tableau closes the current desktop, then opens
the new one. Nothing starts at login.

## The bar menu

- **Empty desktop** closes all windows and stops services started by Tableau.
- **Saved tableaus** load a desktop layout.
- **Save current state** saves the windows that are open now.
- **Rename**, **Duplicate**, and **Delete** manage saved tableaus.
- **Edit** opens the configuration file.

Keyboard controls:

- `j` / `k` or Up / Down: move
- Enter or Space: activate
- `r`: refresh
- `x`: delete the selected tableau
- Escape: close the menu

## Configuration

The file is:

```text
~/.config/omarchy/tableau.toml
```

It is read each time the menu opens.

```toml
[options]
grace = 8

[[setups]]
name = "Work"
icon = ""
services = []

  [[setups.workspaces]]
  number = 1
  columns = [
    { width = 2, windows = [{ term = "" }] },
    { width = 1, windows = [{ term = "btop" }] },
  ]

  [[setups.workspaces]]
  number = 2
  columns = [
    { width = 1, windows = [{ app = "omarchy-launch-browser" }] },
    { width = 1, windows = [{ app = "nautilus" }] },
  ]
```

### Windows

| Key | Meaning |
| --- | --- |
| `term` | Run a command in the configured terminal. Use `""` for a shell. |
| `app` | Run an application with its arguments. |
| `dir` | Working directory. |
| `class` | Window class, when it differs from the command. |
| `height` | Relative height inside a column. |
| `width` | Relative width of a column. |
| `float` | Keep the window floating. |
| `wait` | Seconds to wait for the window. Default: 20. |

Use the default Omarchy helpers when possible:

```toml
{ term = "" }
{ term = "btop" }
{ app = "omarchy-launch-browser" }
{ app = "nautilus" }
```

The built-in starter configuration uses these defaults, so it also works on a
fresh Omarchy install without optional developer applications.

### Monitors

Add `monitor` to a workspace to request a display:

```toml
  [[setups.workspaces]]
  number = 3
  monitor = "DP-2"
  columns = [{ width = 1, windows = [{ term = "" }] }]
```

If the display is not connected, Tableau uses the focused monitor.

### Services

Services can be systemd user units or background commands:

```toml
services = [
  "docker-desktop",
  { run = "python -m http.server 8000", dir = "~/Work/project" },
]
```

Only services started by Tableau are stopped later. System services are not
supported. Review commands before loading a file from another source.

## Screens and layout

Tableau adapts layouts to the connected displays. It limits columns on narrow
screens and remembers an arrangement for each display setup.

Forget the remembered arrangement with:

```bash
omarchy-tableau forget
```

Tableau opens windows one at a time. A missing application is reported in the
menu. If a window refuses to close, Tableau pauses and asks what to do.

## CLI

```bash
omarchy-tableau status [--json]
omarchy-tableau load Work [--force]
omarchy-tableau save "New tableau"
omarchy-tableau rename "New tableau" "Renamed tableau"
omarchy-tableau duplicate Work "Work copy"
omarchy-tableau delete "Work copy"
omarchy-tableau init [--force]
omarchy-tableau edit
omarchy-tableau retry [--force]
omarchy-tableau clear
```

## Install

```bash
omarchy plugin add https://github.com/novuon/omarchy_tableau.git --enable --yes
omarchy bar move novuon.tableau --section left
```

To remove Tableau safely:

```bash
omarchy plugin remove novuon.tableau --yes
```

Removing the plugin does not delete your `~/.config/omarchy/tableau.toml` file
or saved Tableau state. Reinstalling the plugin can therefore restore your
previous setup selection without changing your desktop automatically.

For local development:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/novuon.tableau
omarchy-shell shell rescanPlugins
```

Run the checks with:

```bash
test/validate.sh
```
