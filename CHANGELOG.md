# Changelog

All notable changes to AnniWin11 are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
This project is in alpha -- all v0.x.0 releases are pre-release.

---

## [v0.4.0] - 2026-04-14

Smart App Detection. New dual-source app scanner replacing the winget-only
approach in `DetectApps.ps1`.

### Added

- **`src/ScanApps.ps1`** -- New dual-source system app scanner.
  - **Source 1: winget list** -- regex parser carried over from
    `DetectApps.ps1` (v0.1.1). Extracts Name, Id, Source, and Version.
  - **Source 2: Start Menu shortcut scan** -- resolves `.lnk` files in
    per-user and system-wide Start Menu Programs folders via WScript.Shell
    COM object. Extracts executable path, install directory, and publisher
    from file version info.
  - **Merge & deduplication** -- three-strategy fuzzy name matching
    (exact normalised, substring containment, executable-to-ID) merges
    winget and Start Menu results. Winget entry is preferred when both
    match; executable path from Start Menu is added to enrich it.
  - **Filtering** -- excludes Windows system components (`System32`,
    `SysWOW64`), Windows SDK/Kit tools (`Windows Kits\`), uninstaller
    shortcuts, web URL shortcuts, broken shortcuts, non-executable
    targets, and system shortcut groups (`Windows Tools`, `Accessories`,
    etc.). Multi-arch duplicates (e.g. WinDbg arm/x64/x86) collapsed
    to a single entry.
  - **Unified output format** per app: `Name`, `Id`, `Source`, `Version`,
    `Executable`, `InstallDir`, `Notes`.
  - **Standalone mode** -- when run directly, prints a colour-coded
    summary table and writes `config/scan_results.json` for inspection.
  - **Dot-source mode** -- exports `Invoke-AppScan` function for use
    by `GenerateConfigs.ps1` and other orchestrators.

---

## [v0.3.0] - 2026-04-14

DriveSetup rewrite. All drive types now detected, safety warnings added.

### Changed

- **`src/DriveSetup.ps1`** -- Full rewrite of `Get-DriveList`. Now uses
  `Get-Partition` + `Get-Volume` together instead of `Get-Volume` alone.
  Discovers all drive types: Fixed (internal), Removable (USB/flash via
  `Get-Disk` BusType check), and Network (mapped drives via `Get-PSDrive`
  DisplayRoot detection). Each drive entry now carries a `DiskNumber` for
  system-disk comparison and a `DriveType` for display.
- **`src/DriveSetup.ps1`** -- `Show-DriveTable` now includes a **Type**
  column showing Fixed, Removable, Network, or (unknown) for each drive.
  Long labels (e.g. network UNC paths) are truncated to fit the table.
- **`src/DriveSetup.ps1`** -- Partition creation flow now validates the
  requested shrink size against `Get-PartitionSupportedSize` before
  attempting the resize, preventing failures from over-shrinking.
- **`src/DriveSetup.ps1`** -- `Get-PSDrive` fallback for Windows Sandbox
  preserved and updated to emit the new object shape (DriveType, DiskNumber
  fields) so all downstream code works uniformly.

### Added

- **`src/DriveSetup.ps1`** -- New `Get-SystemDiskNumber` helper. Resolves
  the physical disk number hosting the C: partition, used to detect whether
  a user-selected drive shares the same physical disk as Windows.
- **`src/DriveSetup.ps1`** -- New `Test-IsSystemDisk` helper. Compares a
  selected drive's DiskNumber against the system disk. Falls back to a
  simple `C:` letter check when partition metadata is unavailable.
- **`src/DriveSetup.ps1`** -- **C: drive / system disk warning.** When the
  user selects any drive on the same physical disk as C:, a prominent red
  warning is displayed explaining the backup will likely be lost during a
  Windows reinstall. The user must confirm with `yes` to proceed. This
  warning is also shown after partition creation (since the new partition
  is necessarily on the same disk as C:). Suppressible via
  `project_config.json` -> `suppress_c_drive_warning`.
- **`src/DriveSetup.ps1`** -- **General reinstall reminder.** After every
  drive selection (including non-system drives), a yellow reminder is
  shown: "Make sure your backup destination is on a drive that will NOT
  be wiped during reinstall."

---

## [v0.2.0] - 2026-04-10

Stability & Foundation milestone. Project-level config infrastructure,
fixes for both known issues from v0.1.1, and a `-Force` override for restore.
Final manual clean-install verification in Windows Sandbox is tracked in the
local `TESTING.md` checklist.

### Added

- **`lib/Config.ps1`** -- New `Get-ProjectConfig` and `Get-ProjectConfigDefaults`
  functions. Loads `config/project_config.json` layered over built-in defaults
  and caches the result for the session (pass `-Reload` to refresh). Supported
  keys: `max_config_folder_mb`, `auto_confirm_fuzzy`, `log_level`,
  `check_updates_on_backup`, `suppress_c_drive_warning`.
- **`config/project_config_example.jsonc`** -- New commented template for the
  project-level config. Copy to `config/project_config.json` and edit.
  (`config/*.json` is already covered by the existing `.gitignore` rule.)
- **`src/RestoreConfigs.ps1`** -- New `-Force` switch. Bypasses the
  "destination newer than backup" safety check and overwrites unconditionally.
  Skip messages now mention the flag. A warning is logged at startup when
  `-Force` is active.
- **`src/BackupConfigs.ps1`** -- Pre-backup DetectApps pass when
  `project_config.check_updates_on_backup` is true (default). Lets users
  categorise apps installed since the last backup before snapshotting.
  Failures in the detect pass are logged as warnings and do not block
  backup.
- **`src/BackupConfigs.ps1`** -- Directory pre-flight size check honouring
  `project_config.max_config_folder_mb` (default 500). Oversized folders
  are skipped with a WARNING and appear in the failed summary as
  `<app>/<path> (oversize)`. Single-file backup paths are not subject to
  the limit.

### Changed

- **All scripts** (`Main.ps1`, `WinSettings.ps1`, `DriveSetup.ps1`,
  `BackupConfigs.ps1`, `RestoreConfigs.ps1`, `InstallApps.ps1`,
  `DetectApps.ps1`, `GenerateConfigs.ps1`, `Pin-TaskbarApp.ps1`) --
  `Initialize-AnniLog` now reads the log level from
  `project_config.log_level` instead of hardcoded `"INFO"`.

### Fixed

- **`src/WinSettings.ps1`** -- Widgets button (`TaskbarDa`) now uses a
  three-tier approach: `reg.exe add` first (most reliable against the
  "unauthorized operation" error seen on some Win11 builds), then the
  PowerShell registry provider with `New-ItemProperty`/`Set-ItemProperty`,
  then the older `ShellFeedsTaskbarViewMode` key as a last-resort fallback.
  Only logs a warning if all three methods fail.
- **`src/DriveSetup.ps1`** -- `Get-DriveList` now falls back to `Get-PSDrive`
  when `Get-Volume` returns nothing or throws. Fixes drive detection in
  Windows Sandbox, where the virtualised volume does not always report as
  `DriveType = Fixed`. Result is wrapped in `@()` so `.Count` is always
  safe even with a single-drive result. (Full DriveSetup rewrite is still
  scoped for v0.3.0.)

---

## [v0.1.2] - 2026-04-04

Documentation overhaul and public-audience config cleanup. No functional code changes.

### Changed

- **`config/apps_example.jsonc`** -- Rebuilt for a broad public audience. Removed
  personal and niche apps, added widely useful defaults, cleaned up categories.
- **`config/app_configs_example.jsonc`** -- Expanded into a community lookup table
  covering 30+ common apps with verified config paths for backup and restore.
- **`README.md`** -- Full rewrite as a public-facing landing page. Added features
  list, quick start, project structure, config reference, backup/restore notes,
  DPAPI limitation, and security section.
- **`ROADMAP.md`** -- Full rewrite with incremental milestones from v0.2.0 through
  v1.0.0 and a v2.0+ future-vision section.
- **`docs/ARCHITECTURE.md`** -- Updated to describe planned components
  (`ScanApps.ps1`, `ScanConfigs.ps1`) and the security model.
- **`CONTRIBUTING.md`** -- Added sections on the community lookup table workflow
  and security requirements for config path contributions.

### Added

- **`docs/VISION.md`** -- New public-facing long-term architecture and design
  spec. Covers the dual-scan engine, three-tier config discovery, community
  lookup table, and security requirements.

---

## [v0.1.1] - 2026-04-04

Patch release. Post-test bug fixes, new DetectApps features, and documentation updates.

### Fixed

- **`lib/Config.ps1`** -- `Resolve-BackupPath` now expands environment variables in
  `absolute` paths (e.g. `%USERPROFILE%`) before returning. Previously these were stored
  and restored as literal strings.
- **`src/BackupConfigs.ps1`** -- Robocopy calls now quote source and destination paths,
  fixing silent failures for any app config path containing spaces (e.g. Brave's
  `User Data\Default\Extensions`).
- **`src/BackupConfigs.ps1`** -- Winget export no longer floods the console with
  "not available from any source" noise. Count is logged at DEBUG level only.
- **`src/WinSettings.ps1`** -- Widgets button now uses a two-method approach with
  fallback. Note: this fix is partially working -- see Known Issues.
- **`src/DetectApps.ps1`** -- Winget output parser rewritten with regex-based approach.
  Previous column-position parser failed entirely on real winget output.
- **`src/DetectApps.ps1`** -- App ID comparison is now case-insensitive.

### Added

- **`src/DetectApps.ps1`** -- Permanent ignore list. Apps ignored via `[I]` during
  detection are saved to `config/ignored_apps.json` and never shown again.
- **`src/DetectApps.ps1`** -- Source auto-tagging. Detected apps are tagged `winget`,
  `msstore`, or `manual` based on the Source column in `winget list` output. Manual
  installs receive a descriptive note (e.g. "Installed via Steam").

### Known Issues

- **`src/WinSettings.ps1`** -- Widgets button (`TaskbarDa`) may still throw an
  "unauthorized operation" error on some Windows 11 builds. Deferred to v0.2.0.
- **`src/DriveSetup.ps1`** -- Drive detection fails in Windows Sandbox due to volume
  filter restrictions. Deferred to v0.2.0.

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

### Known Issues (resolved in v0.1.1)

- Robocopy fails for paths containing spaces
- Winget export floods console with noise output
- DetectApps parser fails entirely on real winget output
- `%USERPROFILE%` not expanded in absolute backup paths
