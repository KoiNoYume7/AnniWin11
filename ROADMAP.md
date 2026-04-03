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

## Next Steps

- [ ] End-to-end testing on a clean Windows 11 install
- [ ] Expand `app_configs_example.jsonc` with more app config paths
- [ ] Improve `DetectApps.ps1` winget output parsing robustness
- [ ] Add `--force` / override flag to `RestoreConfigs.ps1`
- [ ] Add VSCode extension backup/restore support to config mapping

---

## Future

- GUI interface (planned but not yet scoped)
- Additional app config mappings contributed by community
- Potential plugin system for custom post-install steps
- Cross-session backup verification (checksum comparison)
