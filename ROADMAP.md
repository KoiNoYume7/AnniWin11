# Roadmap

High-level milestone plan for AnniWin11.
All v0.x.0 releases are alpha / pre-release.

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

## v0.2.0 -- Stability & UX (planned)

Focus: fix remaining known issues, improve first-run experience, full clean-install test.

- [ ] Fix Widgets button registry key (`WinSettings.ps1`) -- unauthorized error on some builds
- [ ] Fix `DriveSetup.ps1` drive detection in Windows Sandbox
- [ ] Improve `GenerateConfigs.ps1` -- walk user through apps and app_configs interactively
  instead of just copying the example files
- [ ] Populate `app_configs_example.jsonc` with verified paths for remaining apps
  (SteelSeries Sonar, Loupedeck, HWiNFO, Windhawk, TranslucentTB)
- [ ] Full clean-install test in Windows Sandbox
- [ ] Add `--force` override flag to `RestoreConfigs.ps1`
- [ ] VSCode extension backup/restore support

---

## Future

- GUI interface (planned but not yet scoped)
- Additional app config mappings contributed by community
- Potential plugin system for custom post-install steps
- Cross-session backup verification (checksum comparison)
