# Changelog

All notable changes to AnniWin11 are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
This project is in alpha -- all v0.x.0 releases are pre-release.

---

## [v0.1.0] - 2026-04-03

Initial alpha release. Full project scaffolding, all planned scripts, config system, and orchestration.

### Added -- Foundation (Phase 0)

- **`.gitignore`** -- Expanded with rules for auto-generated configs, logs, installers, and TODO.md
- **`.gitattributes`** -- Enforces CRLF on `.ps1`/`.psm1`/`.psd1`/`.bat`, LF on text files, binary for images
- **`lib/AnniLog.psm1` + `lib/AnniLog.psd1`** -- Reusable logging module with levelled console + file output. Exported: `Initialize-AnniLog`, `Write-AnniLog`, `Close-AnniLog`
- **`lib/AnniLogo.psm1` + `lib/AnniLogo.psd1`** -- Reusable ASCII art renderer with horizontal colour gradient. Exported: `Show-AnniLogo`. Refactored from `LogoASCII.ps1`
- **`lib/Config.ps1`** -- Centralised config helper: JSONC/JSON reading, path resolution, backup path token expansion
- **`docs/ARCHITECTURE.md`** -- Technical architecture documentation
- **`CHANGELOG.md`** -- This file
- **`ROADMAP.md`** -- Project roadmap and milestone tracking
- **`CONTRIBUTING.md`** -- Contribution guidelines
- **`README.md`** -- Project overview, requirements, usage, and structure

### Changed -- Refactored Existing Scripts (Phase 1)

- **`src/InstallApps.ps1`** -- Replaced inline logging with AnniLog, inline JSONC parsing with Config.ps1, fixed `--source winget` space bug, fixed path resolution, reads `config/apps.json`
- **`src/WinSettings.ps1`** -- Now reads all values from `config/settings.json` instead of hardcoded values. Device name, theme, taskbar, explorer, developer settings all configurable
- **`src/Pin-TaskbarApp.ps1`** -- Reads `taskbar_apps` array from `config/settings.json`, uses AnniLog, supports standalone and dot-sourced execution
- **`src/BootstrapPwsh7.ps1`** -- Improved user prompts with colour, added explanatory header comment

### Added -- Config System (Phase 2)

- **`config/settings_example.jsonc`** -- Commented template for OS settings (device, theme, taskbar, explorer, developer, taskbar pins)
- **`config/app_configs_example.jsonc`** -- Commented template mapping apps to their config file locations for backup/restore
- **`src/GenerateConfigs.ps1`** -- Interactive config generator: walks user through creating apps.json, settings.json, and app_configs.json from example templates

### Changed -- Config Updates (Phase 2)

- **`config/apps_example.jsonc`** -- Fixed "Depricated" typo to "Deprecated", updated usage instructions, fixed trailing space in Rufus winget ID

### Added -- New Feature Scripts (Phase 3)

- **`src/DriveSetup.ps1`** -- Interactive drive/partition selector for backup store. Lists drives, supports creating new partition on C:, writes `config/backup_store.json`
- **`src/BackupConfigs.ps1`** -- Snapshots app config files to backup store using robocopy. Runs `winget export`, writes `backup_manifest.json`
- **`src/RestoreConfigs.ps1`** -- Restores config files from backup store post-reinstall. Non-destructive by default (skips if destination is newer). Prints DPAPI warning
- **`src/DetectApps.ps1`** -- Scans installed apps via `winget list`, compares against `apps.json`, prompts user to categorise untracked apps. Detects new installs since last backup

### Added -- Orchestration (Phase 4)

- **`setup.bat`** -- Entry point with UAC elevation, PowerShell 7 bootstrap, launches Main.ps1
- **`src/Main.ps1`** -- Interactive numbered menu orchestrating all scripts. Defines AnniWin11 ASCII art and passes to AnniLogo module. First-time setup flow runs all steps in sequence

### Removed

- **`lib/LogoASCII.ps1`** -- Superseded by `lib/AnniLogo.psm1`
