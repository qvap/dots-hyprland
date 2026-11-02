# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The "illogical-impulse" (ii) Quickshell config: a full desktop shell (bars, sidebars, overview, lock screen, OSDs, etc.) written in QML for Hyprland (with partial Niri support). It lives inside a fork of `end-4/dots-hyprland` (remote `upstream`; this fork is `origin` = `qvap/dots-hyprland`). Repo root is `../../../../` — install/setup scripts live there (`setup`, `sdata/`), not here.

## Running / testing

There is no build, lint, or test suite. Run the shell directly and watch its log:

```bash
qs -c ii
```

Quickshell hot-reloads on file save; QML errors appear in the terminal output. Other entry points are standalone windows launched the same way with `-p`, e.g. `qs -p settings.qml` (settings app), `welcome.qml`, `killDialog.qml`, `vpnDetails.qml`, `steamLogin.qml`.

Most panels are toggled via IPC: `qs -c ii ipc call <target> <function>` (look for `IpcHandler { target: ... }` in the code); `GlobalShortcut` entries are bound from Hyprland as `global, quickshell:<name>`.

## Architecture

- **`shell.qml`** — root. Boots singletons (theme, wallpapers, etc.) and lazily loads exactly one *panel family* based on `Config.options.panelFamily`: `ii` (default Material look), `waffle` (Windows-11-like), `hefty`.
- **`panelFamilies/*Family.qml`** — list the panels in a family, each wrapped in `PanelLoader` (a `LazyLoader` gated on `Config.ready` + an `extraCondition`). New top-level panels must be registered here.
- **`modules/<family>/<panel>/`** — UI per family. `modules/settings/` holds settings pages for `settings.qml`.
- **`modules/common/`** — shared foundation, imported as `qs.modules.common`:
  - `Config.qml` — singleton wrapping a `JsonAdapter` with the whole option schema (defaults live in the QML property declarations); persisted to the user config JSON (`Directories.shellConfigPath`). Family-specific options are in `config/WaffleConfig.qml`, `config/HeftyConfig.qml`. Adding an option = adding a property in the right `JsonObject`; set from code with `Config.options.x.y = v` or `Config.setNestedValue("x.y", v)`.
  - `Persistent.qml` — persisted runtime state (not user config). `Directories.qml` — all file paths (state under `~/.local/state/quickshell/user/...`).
  - `Appearance.qml` — design tokens (Material 3 colors, fonts, rounding, animation curves); colors come from the generated Material theme (`services/MaterialThemeLoader.qml`, `scripts/colors/`).
  - `widgets/` — reusable styled components (prefer these over raw QtQuick controls). `functions/` — JS helper singletons (`StringUtils`, `FileUtils`, `ColorUtils`, ...).
- **`services/`** — `pragma Singleton` QML singletons (imported as `qs.services`) wrapping system state: audio (Pipewire), network, bluetooth, Hyprland data/keybinds/config, notifications, AI chat (`Ai.qml` + `ai/`), weather, todo, wallpapers, etc. UI binds to their properties; logic belongs here, not in panels. `WM.qml` abstracts Hyprland vs Niri backends.
- **`GlobalStates.qml`** — singleton of cross-panel UI state (e.g. which sidebar/overview is open).
- **`scripts/`** — shell/Python helpers invoked via `Process` (color generation, thumbnails, AI, music recognition, etc.).

## Conventions

- Imports use the `qs.*` module paths (`qs.modules.common`, `qs.services`, `qs.modules.common.widgets`).
- All user-visible strings go through `Translation.tr("...")`. Translations are JSON in `translations/<locale>.json`, keyed by the English string; manage with `translations/tools/manage-translations.sh` (`status`, `extract`, `update`, see `translations/tools/README.md`).
- Changes from upstream are merged periodically (`Merge upstream end-4/dots-hyprland main into dev`); keep diffs against upstream files minimal where possible to ease merges.
