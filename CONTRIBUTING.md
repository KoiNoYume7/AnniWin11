# Contributing to AnniWin11

Thank you for your interest in contributing.

---

## Requirements

- **PowerShell 7+** -- all scripts must run under `pwsh`
- **Windows 11** -- this project targets Windows 11 only

## Getting Started

1. Fork and clone the repository.
2. Open the workspace file `AnniWin11.code-workspace` in VS Code.
3. Copy example config files from `config/*_example.jsonc` to `config/*.json` (or run `src/GenerateConfigs.ps1`).
4. Test your changes locally before submitting.

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
