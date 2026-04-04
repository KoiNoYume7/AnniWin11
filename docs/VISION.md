# Vision

Long-term architecture and design vision for AnniWin11.
This document describes where the project is heading -- not where it is today.
For current status, see [ROADMAP.md](../ROADMAP.md).

---

## Core Promise

> Scan your system once. Back up everything. Restore everything on a fresh install.

AnniWin11 is a general-purpose Windows 11 post-install automation suite designed to work
for anyone. It detects what you have installed, finds where your configs live, backs
everything up, and restores it all after a clean Windows reinstall -- with minimal
manual steps.

---

## Design Principles

- **Nothing hardcoded.** Everything driven by config files or detected at runtime.
- **User confirms destructive operations.** Never assume, always ask.
- **Security-first.** Never store credentials, tokens, or DPAPI-encrypted data.
- **Broad compatibility.** Works for gamers, developers, and general users alike.
- **Community-extensible.** The config lookup table grows with contributions over time.

---

## Setup Flow

### Phase 1: First-Time Setup

```
setup.bat
  -> UAC elevation
  -> PS7 bootstrap
  -> Main.ps1

Main menu -> [1] First-time setup:
  Step 1: DriveSetup.ps1        -- select backup destination
  Step 2: GenerateConfigs.ps1   -- detect apps, discover configs, build all config files
  Step 3: WinSettings.ps1       -- apply OS settings (includes taskbar pinning)
```

`GenerateConfigs.ps1` is the orchestrator. It calls `ScanApps.ps1` and `ScanConfigs.ps1`
internally to detect installed applications and discover their config file locations.

### Phase 2: Ongoing Use

```
[1] First-time setup
[2] Backup
[3] Restore
[4] Backup, wipe & restore  (future -- placeholder)
[5] Settings
[6] Drive setup
[7] Regenerate configs
[0] Exit
```

---

## Planned Components

### ScanApps.ps1

Detects every app installed on the system using two scan sources:

**Source 1: winget list** -- produces app name, ID, and source (winget/msstore/manual).

**Source 2: Start Menu scan** -- resolves `.lnk` shortcut targets from:
- `%APPDATA%\Microsoft\Windows\Start Menu\Programs`
- `%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs`

Apps found in both sources are deduplicated (winget entry preferred for its reinstall ID).
Apps found only in Start Menu are tagged as `source: manual`.

**Filtering:** Windows system components, uninstall shortcuts, and web URLs are excluded.

### ScanConfigs.ps1

For each detected app, discovers its config file locations using a three-tier approach:

**Tier 1: Community lookup table** -- checks `app_configs_example.jsonc` for a known
mapping. This is the fast path for common apps.

**Tier 2: Fuzzy AppData scan** -- scans `%APPDATA%`, `%LOCALAPPDATA%`, and `%PROGRAMDATA%`
for folders matching the app name. Candidates are filtered by size (configurable limit)
and an exclusion list (Temp, Cache, node_modules, etc.). Fuzzy matches are presented to
the user for confirmation.

**Tier 3: Install directory scan** -- checks the app's install directory for config files
(`*.json`, `*.ini`, `*.cfg`, `*.xml`, `*.db`), excluding `bin/` and `lib/` subdirectories.

### GenerateConfigs.ps1

Orchestrates the full detection pipeline:

1. Check prerequisites (backup destination configured)
2. Run ScanApps -- detect all installed apps
3. User categorises each app: MainApps / AdditionalApps / Tools / Ignore
4. Write `apps.json`
5. Run ScanConfigs -- discover config paths for confirmed apps
6. User confirms or rejects fuzzy-matched candidates
7. Write `app_configs.json`
8. Summary of what was detected, confirmed, and skipped

App detection and config discovery can also be run independently from the main menu.
Progress is saved incrementally so the script can resume after interruption.

### DriveSetup.ps1

Improved backup destination selector:

- Detects Fixed, Removable (USB/flash), and Network drives
- USB/flash drives shown and selectable (common backup target)
- **C: drive warning:** prominent warning if user selects the system disk
- **Reinstall warning:** reminder after any selection to verify the drive survives reinstall
- Partition creation carried over from v0.1.x

### project_config.json

Project-level settings separate from Windows settings:

```jsonc
{
  "max_config_folder_mb": 100,     // Size limit for fuzzy scan candidates
  "auto_confirm_fuzzy": false,     // Auto-confirm fuzzy matches (risky)
  "log_level": "INFO",             // Console log level
  "check_updates_on_backup": true, // Check for new apps before backup
  "suppress_c_drive_warning": false // Skip C: drive warning (not recommended)
}
```

---

## Backup Flow

1. Verify backup destination exists and is writable
2. Warn if destination is on C: drive or same physical disk
3. Check for new apps since last backup; offer to update configs
4. Run BackupConfigs (app config files)
5. Run winget export
6. Copy AnniWin11 config files (apps.json, settings.json, app_configs.json) to backup
7. Write `backup_manifest.json` with SHA256 checksums
8. Summary with warnings about skipped items

**Config file backup** (step 6) is critical: on a fresh install, the user needs their
config files available before AnniWin11 can run properly.

## Restore Flow

1. Prompt for backup location (may differ from backup_store.json on a new machine)
2. Validate `backup_manifest.json`
3. Show backup summary and prominent warnings:
   - "Browser passwords cannot be restored (DPAPI)"
   - "Some apps must be installed BEFORE restoring their configs"
4. Verify SHA256 checksums, warn on mismatch
5. Restore config files via RestoreConfigs.ps1
6. Offer to run InstallApps if apps.json present in backup
7. Offer to run WinSettings if settings.json present in backup
8. Summary of what was restored and what needs manual attention

---

## Security Requirements

These apply across all scripts:

1. **No credentials.** Never store passwords, tokens, API keys, or session cookies.
2. **No symlink following.** Check `(Get-Item $path).LinkType` before operating on any path.
3. **Private key detection.** During config scanning, warn (do not include) files matching
   `*.key`, `*.pem`, `*.pfx`, `*.p12`, `id_rsa*`, `id_ed25519*`, `*.ppk`.
4. **Path traversal prevention.** Validate all user-provided paths with `Resolve-Path`.
5. **No execution of discovered files.** ScanApps and ScanConfigs read metadata only.
6. **Audit logging.** All skipped items during scanning logged at DEBUG level.
7. **Size limits.** Check available space before backup; warn if < 20% free remains.
8. **Backup integrity.** SHA256 checksum per file in `backup_manifest.json`; verify on restore.

---

## Community Lookup Table

The `config/app_configs_example.jsonc` file serves as a community-maintained lookup table
of verified config paths. Contributors can add entries for apps they use -- see
[CONTRIBUTING.md](../CONTRIBUTING.md) for the format and requirements.

The lookup table is the fastest path in config discovery (Tier 1). The more apps it covers,
the fewer fuzzy matches users need to confirm manually.

---

## Build Phases

The vision is implemented incrementally across milestones. See [ROADMAP.md](../ROADMAP.md)
for the full timeline. In summary:

| Phase | Milestone | What ships |
|-------|-----------|------------|
| Foundation | v0.2.0 | Bug fixes, project_config infrastructure |
| DriveSetup | v0.3.0 | USB support, safety warnings |
| Detection | v0.4.0 | ScanApps (dual-scan engine) |
| Discovery | v0.5.0 | ScanConfigs (three-tier engine) |
| Orchestration | v0.6.0 | GenerateConfigs rewrite |
| Backup/Restore | v0.7.0 | Checksums, config backup, new restore flow |
| UX | v0.8.0 | New menu, smart backup, WinSettings improvements |
| Security | v0.9.0 | Full security hardening |
| Stable | v1.0.0 | First public stable release |
