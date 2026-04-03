# AnniWin11

A PowerShell-based Windows 11 post-install automation suite. Install apps, apply OS settings, and restore all your app configurations to exactly how you had them -- with minimal manual steps.

---

## Status

**Alpha (v0.1.1)** -- this project is under active development.
See [ROADMAP.md](ROADMAP.md) for progress and [CHANGELOG.md](CHANGELOG.md) for version history.

> **Known issues:** The Widgets taskbar button setting may fail on some Windows 11 builds.
> See [CHANGELOG.md](CHANGELOG.md) for details.

---

## Features

- **One-click setup** -- run `setup.bat` and follow the interactive menu
- **App installation** -- install apps via winget, direct download, local installer, or terminal command
- **Config backup and restore** -- snapshot and restore app configuration files across Windows reinstalls
- **Windows settings** -- apply your preferred OS settings (theme, taskbar, Explorer, dev mode, etc.) from a config file
- **Taskbar pinning** -- pin apps to the taskbar from config
- **App detection** -- scan installed apps and add missing ones to your config
- **Drive setup** -- choose or create a backup partition interactively
- **Fully configurable** -- no hardcoded values; everything driven by JSON config files

---

## Requirements

- **Windows 11**
- **PowerShell 7+** (automatically installed by `setup.bat` if missing)

---

## Quick Start

1. Clone the repository:
   ```
   git clone https://github.com/KoiNoYume7/AnniWin11.git
   ```

2. Generate your config files:
   ```
   pwsh -File src\GenerateConfigs.ps1
   ```
   This walks you through creating your `apps.json`, `settings.json`, and `app_configs.json`
   interactively. Alternatively, copy the example configs manually and edit them
   (remove the `//` comments before use, as plain JSON does not support them).

3. Run the setup:
   ```
   setup.bat
   ```
   This handles UAC elevation, installs PowerShell 7 if needed, and launches the interactive menu.

---

## Project Structure

```
AnniWin11/
  setup.bat                  Entry point (UAC elevation, PS7 bootstrap)
  .gitignore
  .gitattributes
  LICENSE
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  ROADMAP.md
  src/
    Main.ps1                 Interactive menu orchestrator
    InstallApps.ps1          App installer (winget/internet/local/terminal)
    WinSettings.ps1          Windows settings applier (from config)
    Pin-TaskbarApp.ps1       Taskbar pinner (from config)
    BackupConfigs.ps1        Snapshot app configs to backup store
    RestoreConfigs.ps1       Restore configs after reinstall
    DetectApps.ps1           Scan and add untracked apps
    DriveSetup.ps1           Backup drive/partition selector
    GenerateConfigs.ps1      Interactive config file generator
    BootstrapPwsh7.ps1       PowerShell 7 installer/relauncher
  lib/
    AnniLog.psm1 / .psd1    Reusable logging module
    AnniLogo.psm1 / .psd1   Reusable ASCII art renderer
    Config.ps1               Centralised path resolution and JSON/JSONC reader
  config/
    apps_example.jsonc       Example app list template
    settings_example.jsonc   Example OS settings template
    app_configs_example.jsonc Example app config paths template
    installers/              Local installer files (gitignored)
  docs/
    ARCHITECTURE.md          Technical architecture overview
  logs/                      Runtime log files (gitignored)
```

## Config Files

AnniWin11 uses two types of config files:

- **Example configs** (`*_example.jsonc`) -- committed to the repo, include comments explaining every field. These are templates.
- **Generated configs** (`*.json`) -- gitignored, no comments. Created by `GenerateConfigs.ps1` or by manually copying and editing the examples.

| Config | Purpose |
|--------|---------|
| `apps.json` | List of apps to install, grouped by category |
| `settings.json` | OS settings (device name, theme, taskbar, Explorer, etc.) and taskbar pin list |
| `app_configs.json` | Maps each app to its config file locations for backup/restore |
| `backup_store.json` | Persists the user-chosen backup drive path |

---

## Backup and Restore

AnniWin11 uses a two-phase approach per app:

1. **Install** the app (via winget, download, local installer, or terminal command)
2. **Restore** the app's config files from the backup store

Before reinstalling Windows, run **Backup configs** to snapshot your current config files.

### DPAPI Limitation

Browser saved passwords and session cookies are encrypted with machine-specific keys (Windows DPAPI). They **cannot** be restored across Windows reinstalls. This is a Windows security feature, not a bug.

**What can be restored**: bookmarks, extensions, browser preferences, themes, wallpapers.
**What cannot**: saved passwords, website login sessions.

**Recommendation**: use a password manager (e.g. Bitwarden) instead of browser-saved passwords.

---

## Licence

MIT -- see [LICENSE](LICENSE).

The author is **not** responsible for data loss, system breakage, or any damage resulting from the use of this software. Use at your own risk.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
