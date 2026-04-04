# Contributing to AnniWin11

Thank you for your interest in contributing. The easiest way to help is by adding
app config paths to the community lookup table -- see below.

---

## Requirements

- **PowerShell 7+** -- all scripts must run under `pwsh`
- **Windows 11** -- this project targets Windows 11 only

## Getting Started

1. Fork and clone the repository.
2. Open the workspace file `AnniWin11.code-workspace` in VS Code.
3. Copy example config files from `config/*_example.jsonc` to `config/*.json` (or run `src/GenerateConfigs.ps1`).
4. Test your changes locally before submitting.

---

## Community Lookup Table

The file `config/app_configs_example.jsonc` is a community-maintained lookup table mapping
apps to their config file locations. This is the single most impactful contribution you
can make -- every app added means fewer fuzzy matches users need to confirm manually.

### How to add an app

1. Find the app's config files on your system (check `%APPDATA%`, `%LOCALAPPDATA%`,
   `%PROGRAMDATA%`, or the app's install directory).
2. Add an entry to `config/app_configs_example.jsonc` under the appropriate category section.
3. Use the correct path type (`appdata`, `localappdata`, `programdata`, or `absolute`).
4. Include a `notes` field explaining what is and isn't backed up.

### Entry format

```jsonc
{
  "name": "App Name",
  "backup_paths": [
    { "type": "appdata", "path": "Publisher\\AppName\\settings.json" }
  ],
  "notes": "What this backs up. Any warnings or prerequisites."
}
```

### Requirements for lookup table entries

- **Verified paths** -- you must have tested that the path exists and contains meaningful
  config data on a real Windows 11 installation.
- **Notes field required** -- explain what is backed up, what is not, and any caveats.
- **DPAPI warning** -- if the app is a Chromium-based browser, include a DPAPI warning
  in the notes (passwords and sessions cannot be restored across reinstalls).
- **Reinstall-first note** -- if the app must be reinstalled before config restore works
  (e.g. peripheral software with kernel drivers), say so in the notes.
- **No credentials** -- never include paths to files containing passwords, tokens, API keys,
  or private keys. If the app stores credentials alongside config, note which specific
  files to back up and which to skip.

---

## App List Contributions

To propose adding an app to `config/apps_example.jsonc`:

- The app must be **publicly available** (not internal/enterprise-only).
- Include the **winget ID** (run `winget search "app name"` to find it).
- Place it in the correct category: MainApps, AdditionalApps, or Tools.
- If the app is not available via winget, specify the source type (`internet`, `local`, or `terminal`).

---

## Security Requirements

All contributions must follow the project's security model:

- **No credentials** in any committed file -- no passwords, tokens, API keys, or session cookies.
- **No private key paths** -- never include paths to `*.key`, `*.pem`, `*.pfx`, `id_rsa`, etc.
- **No symlink targets** -- config paths must resolve to real directories, not symlinks.
- **No System32/SysWOW64 paths** -- never suggest paths under the Windows directory.
- **DPAPI awareness** -- browser entries must warn about non-restorable passwords/sessions.

See [docs/VISION.md](docs/VISION.md) for the full security requirements.

---

## Code Style

- **No emojis** in code, comments, or documentation.
- **British/neutral English** in all user-facing strings.
- Use `$PSScriptRoot` for path resolution; never hardcode absolute paths.
- Use the `AnniLog` module for all logging (never bare `Write-Host` for status messages).
- Follow the existing formatting: 4-space indentation, `PascalCase` for functions, `camelCase` or `PascalCase` for variables as per PowerShell conventions.
- Keep functions focused and files clean -- prefer multiple small files over one large file.

## Config Files

- **Example configs** (`*_example.jsonc`): committed to the repository, include comments explaining every field.
- **Generated configs** (`*.json`): gitignored, no comments, created by `GenerateConfigs.ps1` or manually by the user.
- Never commit user-specific config files.

## Line Endings

Line endings are enforced via `.gitattributes`:
- `.ps1`, `.psm1`, `.psd1`, `.bat` -- CRLF (required for Windows script execution)
- `.md`, `.json`, `.jsonc` -- LF

Ensure your editor respects these settings.

## Pull Requests

1. Create a feature branch from `main`.
2. Keep changes focused -- one feature or fix per PR.
3. Update `CHANGELOG.md` with your changes under an `[Unreleased]` section.
4. Test that all affected scripts still run correctly.
5. Describe what you changed and why in the PR description.

## Reporting Issues

Open an issue on GitHub with:
- Steps to reproduce
- Expected vs actual behaviour
- PowerShell version (`$PSVersionTable`)
- Windows 11 build number

## Licence

By contributing, you agree that your contributions are licensed under the MIT licence.
