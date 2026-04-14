# AnniWin11

Scan your system once. Back up everything. Restore everything on a fresh install.

A PowerShell-based Windows 11 post-install automation suite. Install apps, apply OS
settings, and restore all your app configurations to exactly how you had them -- with
minimal manual steps.

---

## Status

**Alpha (v0.3.0)** -- this project is under active development.
See [ROADMAP.md](ROADMAP.md) for milestones and [CHANGELOG.md](CHANGELOG.md) for version history.

> **v0.3.0 highlights:** DriveSetup rewrite -- detects Fixed, Removable
> (USB/flash), and Network drives, C: drive / system-disk safety warning,
> general reinstall reminder, improved partition creation with size
> validation. See [CHANGELOG.md](CHANGELOG.md) for details.

---

## Features

### Current (v0.1.x)

- **One-click setup** -- run `setup.bat` and follow the interactive menu
- **App installation** -- install apps via winget, direct download, local installer, or terminal command
- **Config backup and restore** -- snapshot and restore app configuration files across Windows reinstalls
- **Windows settings** -- apply OS settings (theme, taskbar, Explorer, dev mode, etc.) from a config file
- **Taskbar pinning** -- pin apps to the taskbar from config
- **App detection** -- scan installed apps via `winget list`, add missing ones to your config
- **Drive setup** -- choose or create a backup partition interactively
- **Fully configurable** -- no hardcoded values; everything driven by JSON config files

### Planned (see [ROADMAP.md](ROADMAP.md))

- **Smart app detection** -- dual-scan engine (winget + Start Menu shortcuts)
- **Automatic config discovery** -- three-tier system finds where your apps store their settings
- **Community lookup table** -- pre-verified config paths for 30+ common apps
- **Backup integrity** -- SHA256 checksums for every backed-up file
- **Improved restore flow** -- manifest validation, warnings, and guided recovery

For the full long-term architecture, see [docs/VISION.md](docs/VISION.md).

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

2. Run the setup:
   ```
   setup.bat
   ```
   This handles UAC elevation, installs PowerShell 7 if needed, and launches the
   interactive menu. First-time setup walks you through everything.

3. Or generate config files manually:
   ```
   pwsh -File src\GenerateConfigs.ps1
   ```
   Alternatively, copy the example configs from `config/*_example.jsonc` to
   `config/*.json` and edit them (remove `//` comments -- plain JSON does not support them).

---

## Project Structure

```
AnniWin11/
  setup.bat                    Entry point (UAC elevation, PS7 bootstrap)
  .gitignore
  .gitattributes
  LICENSE
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  ROADMAP.md
  src/
    Main.ps1                   Interactive menu orchestrator
    InstallApps.ps1            App installer (winget/internet/local/terminal)
    WinSettings.ps1            Windows settings applier (from config)
    Pin-TaskbarApp.ps1         Taskbar pinner (from config)
    BackupConfigs.ps1          Snapshot app configs to backup store
    RestoreConfigs.ps1         Restore configs after reinstall
    DetectApps.ps1             Scan and add untracked apps
    DriveSetup.ps1             Backup drive/partition selector
    GenerateConfigs.ps1        Interactive config file generator
    BootstrapPwsh7.ps1         PowerShell 7 installer/relauncher
    ScanApps.ps1               System app scanner (planned -- v0.4.0)
    ScanConfigs.ps1            Config path discovery (planned -- v0.5.0)
  lib/
    AnniLog.psm1 / .psd1      Reusable logging module
    AnniLogo.psm1 / .psd1     Reusable ASCII art renderer
    Config.ps1                 Centralised path resolution and JSON/JSONC reader
  config/
    apps_example.jsonc         Example app list template
    settings_example.jsonc     Example OS settings template
    app_configs_example.jsonc  Community lookup table -- app config paths for backup/restore
    installers/                Local installer files (gitignored)
  docs/
    ARCHITECTURE.md            Technical architecture overview
    VISION.md                  Long-term design vision and planned components
  logs/                        Runtime log files (gitignored)
```

---

## Config Files

AnniWin11 uses two types of config files:

- **Example configs** (`*_example.jsonc`) -- committed to the repo, include comments explaining every field. These are templates and the community lookup table.
- **Generated configs** (`*.json`) -- gitignored, no comments. Created by `GenerateConfigs.ps1` or by manually copying and editing the examples.

| Config | Purpose |
|--------|---------|
| `apps.json` | List of apps to install, grouped by category |
| `settings.json` | OS settings (device name, theme, taskbar, Explorer, etc.) and taskbar pin list |
| `app_configs.json` | Maps each app to its config file locations for backup/restore |
| `backup_store.json` | Persists the user-chosen backup drive path |
| `ignored_apps.json` | Apps permanently ignored during detection |
| `project_config.json` | Project-level settings (log level, size limits, backup flags) |

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

## Security

AnniWin11 follows a security-first approach:

- **No credential storage** -- never stores passwords, tokens, API keys, or session cookies
- **No symlink following** -- all paths checked before read/write operations
- **Private key detection** -- warns if config scanning encounters private key files
- **Audit logging** -- all skipped items during scanning logged at DEBUG level
- **DPAPI warnings** -- runtime warnings for browser data that cannot survive reinstalls

See [docs/VISION.md](docs/VISION.md) for the full security requirements.

---

## Licence

MIT -- see [LICENSE](LICENSE).

The author is **not** responsible for data loss, system breakage, or any damage resulting from the use of this software. Use at your own risk.

---

## Contributing

Contributions welcome -- especially app config path additions to the community lookup table.
See [CONTRIBUTING.md](CONTRIBUTING.md).
