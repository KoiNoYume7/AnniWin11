# AnniWin11

Scan your system once. Back up everything. Restore everything on a fresh install.

A PowerShell-based Windows 11 post-install automation suite. Install apps, apply OS
settings, and restore all your app configurations to exactly how you had them -- with
minimal manual steps.

---

## Status

**Alpha (v0.8.0)** -- this project is under active development.
See [ROADMAP.md](ROADMAP.md) for milestones and [CHANGELOG.md](CHANGELOG.md) for version history.

> **v0.8.0 highlights:** Backup & Restore v2. Every backed-up file now gets
> a SHA256 checksum recorded in the backup manifest, and restore verifies
> them all before writing anything. The backup store also carries the
> project's own config files, so a fresh clone re-hydrates itself after a
> reinstall. New guided restore flow: manifest validation, restore plan
> summary, explicit confirmation, and post-restore offers to run
> InstallApps and WinSettings. See [CHANGELOG.md](CHANGELOG.md) for details.

---

## Features

### Current

- **One-click setup** -- run `setup.bat` and follow the interactive menu
- **App installation** -- install apps via winget, direct download, local installer, or terminal command
- **Config backup and restore** -- snapshot and restore app configuration files across Windows reinstalls
- **Windows settings** -- apply OS settings (theme, taskbar, Explorer, dev mode, etc.) from a config file
- **Taskbar pinning** -- pin apps to the taskbar from config
- **Smart app detection** -- dual-scan engine (`winget list` + Start Menu shortcuts) with fuzzy deduplication
- **Automatic config discovery** -- three-tier system finds where your apps store their settings
- **Community lookup table** -- pre-verified config paths for 30+ common apps
- **Drive setup** -- choose or create a backup partition interactively
- **Reset / wipe state** -- selectively delete generated configs, backup pointers, or all state
- **Pre-reinstall validation** -- `test_suite.ps1` checks syntax, config integrity, backup state, and checksums
- **Backup integrity** -- SHA256 checksum for every backed-up file, verified on restore
- **Guided restore flow** -- manifest validation, restore plan summary, explicit confirmation
- **Self-hydrating backups** -- the backup store carries the project's config files, so a fresh clone restores itself
- **Fully configurable** -- no hardcoded values; everything driven by JSON/JSONC config files

### Planned (see [ROADMAP.md](ROADMAP.md))

- **Menu & UX polish** -- restructured main menu, smarter backup flow
- **WinSettings idempotency** -- skip settings that already match desired value
- **Security hardening** -- symlink checks, path traversal prevention, full audit

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
   interactive menu.

3. First-time setup (option `[1]`):
   - **Step 1:** Select your backup destination drive.
   - **Step 2:** Detect installed apps, discover their config paths, and build
     `apps.json` + `app_configs.json`.
   - After setup, run `[3] Backup configs now` to snapshot your current configs.

4. Before reinstalling Windows, run the validation suite:
   ```
   pwsh -File test_suite.ps1
   ```
   This checks script syntax, config JSON validity, and backup integrity.

5. Or generate config files manually:
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
  test_suite.ps1               Pre-reinstall validation suite
  .gitignore
  .gitattributes
  LICENSE
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  ROADMAP.md
  src/
    Main.ps1                   Interactive menu orchestrator
    InstallApps.ps1            App installer (winget/internet/local/terminal/msstore)
    WinSettings.ps1            Windows settings applier (from config)
    Pin-TaskbarApp.ps1         Taskbar pinner (from config)
    BackupConfigs.ps1          Snapshot app configs to backup store
    RestoreConfigs.ps1         Restore configs after reinstall
    DetectApps.ps1             Scan and add untracked apps (delta detection: compares winget output against apps.json)
    DriveSetup.ps1             Backup drive/partition selector
    GenerateConfigs.ps1        Interactive config file generator (orchestrates ScanApps + ScanConfigs)
    ScanApps.ps1               Dual-source app scanner (winget + Start Menu)
    ScanConfigs.ps1            Three-tier config path discovery engine
    ResetState.ps1             Selective state wipe (configs, backups, nuclear reset)
    BootstrapPwsh7.ps1         PowerShell 7 installer/relauncher
  lib/
    AnniLog.psm1 / .psd1      Reusable logging module
    AnniLogo.psm1 / .psd1     Reusable ASCII art renderer
    Config.ps1                 Centralised path resolution and JSON/JSONC reader
  config/
    apps_example.jsonc         Example app list template
    settings_example.jsonc     Example OS settings template
    app_configs_example.jsonc  Community lookup table -- app config paths for backup/restore
    project_config_example.jsonc  Project-level settings template
    installers/                Local installer files (gitignored)
  tests/                       Validation and helper scripts
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
| `project_config.json` | Project-level settings (log level, size limits, auto-confirm, backup flags) |

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

## Testing

Before reinstalling Windows, run the built-in validation suite:

```
pwsh -File test_suite.ps1
```

Checks performed:
- All `.ps1` and `.psm1` files parse without syntax errors
- All committed config files are valid JSON
- `apps.json` content checks (MS Store source correctness, broken IDs, terminal commands)
- Backup manifest and directory integrity (if backup exists)
- SHA256 checksum verification of every file in the backup store (v0.8.0+ backups)
- Config path resolution functions work correctly

Warnings about missing backup files are expected if you have not run a backup yet.

---

## Licence

MIT -- see [LICENSE](LICENSE).

The author is **not** responsible for data loss, system breakage, or any damage resulting from the use of this software. Use at your own risk.

---

## Contributing

Contributions welcome -- especially app config path additions to the community lookup table.
See [CONTRIBUTING.md](CONTRIBUTING.md).
