# AGENTS.md

Operating manual for AnniWin11. Read this before changing anything.

## What this is

A PowerShell-based Windows 11 post-install automation suite. Two generations
coexist in the repo:

- **v1 (stable, v0.8.0 on `main`)** — interactive menu suite:
  `setup.bat` -> `src/Main.ps1` -> per-feature scripts in `src/`, driven by
  `config/*.json` (generated; `*_example.jsonc` templates are committed).
  Shared helpers in `lib/` (`AnniLog.psm1`, `AnniLogo.psm1`, `Config.ps1`).
- **v2 (in development on `dev`)** — declarative phase orchestrator:
  `setup-v2.bat` -> `bootstrap.ps1` (PS 5.1) -> `Invoke-Setup.ps1` (pwsh 7)
  -> `modules/Phase.*.ps1`, driven by committed `profile/*.psd1` manifests.
  v2 libs in `lib/{Log,State,Preflight,Elevation,Winget}.ps1` (dot-sourced,
  PS 5.1 + 7 compatible). Idempotent phases, preflight risk table + one
  confirmation, `state.json` resume, scheduled-task reboot-resume.

Default branch of work: `dev`. Versioning: SemVer in docs; v0.x = alpha.

## Run / verify

```powershell
# v1 stable path
setup.bat                          # elevated; interactive menu
pwsh -File test_suite.ps1          # validation suite (run before reinstall)

# v2 path
setup-v2.bat                       # elevated; real run (prompts once)
setup-v2.bat -DryRun               # or: preview only, auto-confirms, no writes
pwsh -File Invoke-Setup.ps1 -DryRun

# Syntax-check everything (test_suite already does this recursively)
pwsh -Command "Get-ChildItem -Recurse -Include *.ps1,*.psm1 | ForEach-Object { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null) }"
```

`test_suite.ps1` validates: PS syntax for all `*.ps1`/`*.psm1` (recursively,
so v2 files included), committed config JSON validity, `apps.json` content
integrity, module imports, `Config.ps1` path resolution, and backup manifest +
SHA256 integrity.

## Conventions

- **Entry scripts** start with `#Requires -Version` (7.0 for `src/`, 5.1 for
  `bootstrap.ps1` — keep it 5.1-compatible: no ternary, no `??`).
- **v1 configs**: `config/*_example.jsonc` committed; generated `config/*.json`
  gitignored. JSONC comments are allowed in examples only.
- **v2 manifests**: `profile/*.psd1` ARE committed — they are the declarative
  source of truth (Phase.Backup snapshots them into each backup).
- **Phase contract**: `Get-<Name>Plan -Manifest` returns
  `@{ Title; Items[]; Risk }`; `Invoke-<Name>Phase -Manifest [-DryRun]` throws
  on hard failure. Every phase must be idempotent and honor `-DryRun`.
- **Gitignored locals**: `logs/`, `state.json`, `.local/` (working notes/plans),
  `PROMPT.md`, `TESTING.md`, `TODO.md`, `check_backup.ps1`.
- **Commit style**: `feat:` / `fix:` / `docs:` / `chore:` prefixes with the
  Co-Authored-By trailer; work on `dev`, merge to `main` at releases.
- **Destructive ops** require explicit confirmation at runtime (v1 menus) or a
  `Risk = $true` flag in the v2 preflight table.

## Gotchas

- `setup.bat` still launches **v1** (`src\Main.ps1`) — v2 runs via
  `setup-v2.bat` or `Invoke-Setup.ps1` directly.
- `bootstrap.ps1` must stay Windows PowerShell **5.1**-compatible (it runs
  before pwsh 7 is guaranteed to exist).
- `state.json` is written by real v2 runs at the repo root — gitignored; delete
  it to force a full re-run.
- Repo may warn "dubious ownership" when the Windows account differs from the
  repo owner — per-command `-c safe.directory=...` flag, don't edit git config.
- `lib/` now holds two generations: v1 modules (`*.psm1`, `Config.ps1`) and v2
  dot-sourced libs (`Log/State/Preflight/Elevation/Winget.ps1`). Don't confuse
  `Log.ps1` (v2) with `AnniLog.psm1` (v1) — they are different APIs.

## Docs

`docs/ARCHITECTURE.md` — technical architecture (both generations).
`docs/VISION.md` — long-term design vision. `ROADMAP.md` — milestones.
`TESTING.md` — local manual test checklist (gitignored).
`.local/cleanup-plan.md` — workspace cleanup tracker (gitignored).
