# Roadmap

High-level milestone plan for AnniWin11.

**Versioning:** [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
All v0.x releases are alpha (unstable, API may change).
v1.0.0 is the first stable public release.

For the full long-term vision, see [docs/VISION.md](docs/VISION.md).

---

## v0.1.0 -- Initial Alpha (completed 2026-04-03)

All planned phases delivered in a single release:

- [x] Expanded `.gitignore` and created `.gitattributes`
- [x] Reusable logging module (`lib/AnniLog.psm1`)
- [x] Reusable ASCII logo renderer (`lib/AnniLogo.psm1`)
- [x] Centralised config helper (`lib/Config.ps1`)
- [x] Documentation (README, CHANGELOG, ROADMAP, CONTRIBUTING, ARCHITECTURE)
- [x] Refactored `InstallApps.ps1` (AnniLog, Config.ps1, bug fixes)
- [x] Refactored `WinSettings.ps1` (reads `config/settings.json`)
- [x] Refactored `Pin-TaskbarApp.ps1` (reads `taskbar_apps` from config)
- [x] Updated `BootstrapPwsh7.ps1`
- [x] Removed `lib/LogoASCII.ps1`
- [x] Created `config/settings_example.jsonc`
- [x] Created `config/app_configs_example.jsonc`
- [x] Updated `config/apps_example.jsonc` (typo fix, path updates)
- [x] Built `src/GenerateConfigs.ps1` (interactive config generator)
- [x] Built `src/DriveSetup.ps1` (backup drive selector)
- [x] Built `src/BackupConfigs.ps1` (config snapshot)
- [x] Built `src/RestoreConfigs.ps1` (config restore)
- [x] Built `src/DetectApps.ps1` (app detection and categorisation)
- [x] Built `setup.bat` (UAC elevation, PS7 bootstrap)
- [x] Built `src/Main.ps1` (interactive menu orchestrator)

---

## v0.1.1 -- Patch Release (completed 2026-04-04)

Post-test bug fixes and DetectApps improvements.

- [x] Fixed robocopy space-in-path bug (`BackupConfigs.ps1`, `RestoreConfigs.ps1`)
- [x] Suppressed winget export console noise (`BackupConfigs.ps1`)
- [x] Rewrote winget output parser with regex approach (`DetectApps.ps1`)
- [x] Fixed case-insensitive app ID comparison (`DetectApps.ps1`)
- [x] Added permanent ignore list to `DetectApps.ps1` (`config/ignored_apps.json`)
- [x] Added source auto-tagging to `DetectApps.ps1` (winget / msstore / manual)
- [x] Fixed `%USERPROFILE%` expansion in `Config.ps1` absolute paths
- [x] Updated documentation (CHANGELOG, ROADMAP)

---

## v0.1.2 -- Docs & Public Configs (completed 2026-04-04)

Documentation overhaul and example config cleanup for public audience.

- [x] Rebuilt `config/apps_example.jsonc` -- removed personal/niche apps, added broadly useful apps
- [x] Expanded `config/app_configs_example.jsonc` as community lookup table (30+ apps)
- [x] Full rewrite of `README.md` as public-facing landing page
- [x] Full rewrite of `ROADMAP.md` with incremental milestones through v1.0.0
- [x] Created `docs/VISION.md` -- public-facing long-term architecture spec
- [x] Updated `docs/ARCHITECTURE.md` with planned components and security model
- [x] Updated `CONTRIBUTING.md` with community lookup table and security sections

---

## v0.2.0 -- Stability & Foundation (completed 2026-04-10)

Focus: fix all known bugs, add project-level config infrastructure, validate on clean install.

- [x] Fix Widgets button registry key (`WinSettings.ps1`) -- three-tier approach
      with `reg.exe` primary, PS provider fallback, Feeds key last-resort
- [x] Fix `DriveSetup.ps1` drive detection in Windows Sandbox -- `Get-PSDrive`
      fallback when `Get-Volume` returns nothing
- [x] Add `config/project_config.json` infrastructure to `Config.ps1`
  - `Get-ProjectConfig` / `Get-ProjectConfigDefaults` with session caching
  - keys: `max_config_folder_mb`, `auto_confirm_fuzzy`, `log_level`,
    `check_updates_on_backup`, `suppress_c_drive_warning`
- [x] Create `config/project_config_example.jsonc` template
- [x] Update `.gitignore` to include `config/project_config.json`
      (already covered by existing `config/*.json` rule)
- [x] Add `-Force` override flag to `RestoreConfigs.ps1`
- [x] Wire `project_config.json` values into consuming scripts
      (`log_level` -> all scripts; `max_config_folder_mb` and
      `check_updates_on_backup` -> `BackupConfigs.ps1`).
      `suppress_c_drive_warning` remains plumbed but unused until the
      DriveSetup rewrite in v0.3.0. `auto_confirm_fuzzy` is reserved for
      the ScanConfigs engine in v0.5.0.
- [~] Full clean-install test in Windows Sandbox -- deferred to manual
      verification, tracked in local `TESTING.md` checklist

---

## v0.3.0 -- DriveSetup Rewrite (completed 2026-04-14)

Focus: fix drive detection bugs, add USB/flash support, improve safety warnings.

- [x] Detect all drive types: Fixed, Removable (USB/flash), and Network
- [x] Fix partition detection (use `Get-Partition` + `Get-Volume` together)
- [x] Show and allow selection of USB/flash drives
- [x] C: drive warning when user selects a path on the system disk
- [x] General reinstall warning after any drive selection
- [x] Carry over partition creation (shrink C:) with detection fix

---

## v0.4.0 -- Smart App Detection (completed 2026-04-14)

Focus: new dual-scan app detection engine replacing `DetectApps.ps1`.

- [x] Build `src/ScanApps.ps1` with two scan sources:
  - Source 1: `winget list` (carry over regex parser from DetectApps)
  - Source 2: Start Menu shortcut scan (`.lnk` resolution via COM)
- [x] Cross-reference and deduplicate results (prefer winget entry when both match)
- [x] Filter out Windows system components, uninstallers, web shortcuts
- [x] Unified output format: name, source, executable path, install directory, notes

---

## v0.5.0 -- Config Discovery (completed 2026-04-14)

Focus: automated config path discovery engine.

- [x] Build `src/ScanConfigs.ps1` with three-tier approach:
  - Tier 1: Community lookup table (`app_configs_example.jsonc`)
  - Tier 2: Fuzzy AppData scan (name matching with size/exclusion filters)
  - Tier 3: Install directory scan (config file patterns)
- [x] Interactive confirmation flow for fuzzy matches
- [x] Security rules: never suggest private keys, browser profile roots, System32,
  or symlink targets
- [x] Audit logging of all skipped candidates at DEBUG level

---

## v0.6.0 -- GenerateConfigs Rewrite (planned)

Focus: orchestrate the full detection pipeline to produce all config files.

- [ ] Rewrite `src/GenerateConfigs.ps1` to orchestrate ScanApps + ScanConfigs
- [ ] Flow: detect apps -> categorise -> scan configs -> confirm -> write
- [ ] App categorisation: MainApps / AdditionalApps / Tools / Ignore
- [ ] Incremental progress saving (resume after interruption)
- [ ] Never silently overwrite existing configs -- always ask first
- [ ] Steps 2-4 (apps) and 5-7 (configs) runnable independently from main menu

---

## v0.7.0 -- Backup & Restore v2 (planned)

Focus: improved backup/restore flows with integrity checks and config file backup.

- [ ] Back up config files (apps.json, settings.json, app_configs.json) alongside app data
- [ ] Check available space before backup, warn if < 20% free
- [ ] SHA256 checksum for each backed-up file in `backup_manifest.json`
- [ ] Verify checksums on restore, warn on mismatch
- [ ] New restore flow: validate manifest, show summary, prominent warnings, confirm
- [ ] Offer to run InstallApps and WinSettings from backup if configs present
- [ ] Warn if backup destination is on C: or same physical disk

---

## v0.8.0 -- Menu & UX Polish (planned)

Focus: updated menu structure, smarter backup flow, WinSettings improvements.

- [ ] Update `src/Main.ps1` menu:
  ```
  [1] First-time setup
  [2] Backup
  [3] Restore
  [4] Backup, wipe & restore  (coming soon)
  [5] Settings
  [6] Drive setup
  [7] Regenerate configs
  [0] Exit
  ```
- [ ] Backup flow checks for new apps since last backup before running
- [ ] `WinSettings.ps1` absorbs taskbar pinning (calls Pin-TaskbarApp internally)
- [ ] WinSettings idempotency: skip settings that already match desired value (if feasible)
- [ ] Option 4 placeholder with informational message

---

## v0.9.0 -- Security & Hardening (planned)

Focus: security audit and hardening across all scripts.

- [ ] Never follow symlinks -- check `(Get-Item $path).LinkType` before operations
- [ ] Path traversal prevention -- validate all user-provided paths with `Resolve-Path`
- [ ] Private key detection during ScanConfigs (`.key`, `.pem`, `.pfx`, `id_rsa`, etc.)
- [ ] Never execute discovered files -- read metadata only
- [ ] Backup integrity verification (checksums from v0.7.0 fully integrated)
- [ ] Size limits on all backup operations
- [ ] Full security audit of all scripts

---

## v1.0.0 -- Stable Release (planned)

The first stable public release. All features from v0.2.0-v0.9.0 must be complete and tested.

**Release criteria:**
- [ ] All v0.x features stable and regression-tested
- [ ] Full end-to-end test on a clean Windows 11 install
- [ ] All documentation up to date (README, ARCHITECTURE, VISION, CONTRIBUTING, CHANGELOG)
- [ ] No known critical or high-severity bugs
- [ ] Community lookup table covers 30+ common apps with verified paths
- [ ] Security requirements fully implemented and audited

---

## v2.0+ -- Future Vision

Long-term ideas. Not scoped or committed.

- GUI interface
- Plugin system for custom post-install steps
- Cross-session backup verification (differential checksums)
- Community contribution workflow (automated path verification)
- Backup + wipe + restore automation (programmatic Windows reinstall)
