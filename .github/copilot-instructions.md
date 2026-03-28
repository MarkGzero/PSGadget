# PsGadget PowerShell Module - AI Agent Guidelines

Project-level instructions for agents working in this repository. Keep this file concise and link to docs for details.

Table of Contents
- [Project Scope](#project-scope)
- [High Priority Rules](#high-priority-rules)
- [Build and Test](#build-and-test)
- [Architecture and Boundaries](#architecture-and-boundaries)
- [Code Conventions](#code-conventions)
- [Docs to Link Instead of Duplicating](#docs-to-link-instead-of-duplicating)
- [Examples Conventions](#examples-conventions)
- [Change Safety Checklist](#change-safety-checklist)

## Project Scope

- Only modify files in this repository workspace.
- If similarly named sibling repositories appear on disk, treat them as read-only reference unless explicitly asked to edit them.

## High Priority Rules

- Use ASCII only in PowerShell code, comments, and strings.
  - Do not use Unicode symbols that can trigger parser issues on Windows PowerShell.
  - Prefer `[OK]`, `PASS`, `[FAIL]`, `ERROR`, and `->`.
- Keep compatibility with PowerShell 5.1+.
  - Include `#Requires -Version 5.1` in scripts where applicable.
  - Do not use PS7-only operators like `?:`, `?.`, or `??`.
  - Use `[System.Environment]::OSVersion.Platform -eq 'Win32NT'` or `$PSVersionTable.PSVersion.Major -le 5` for Windows checks.
- Do not change module load order in `PSGadget.psm1`.
- Do not change exports in `PSGadget.psd1` without matching Public function updates.
- For markdown files longer than one screen, include a Table of Contents immediately after the opening description block and before the first H2 section.

## Build and Test

Use these commands for routine validation:

- `pwsh -c "Import-Module ./PSGadget.psd1 -Force"`
- `pwsh -c "Import-Module Pester; Invoke-Pester ./Tests/PsGadget.Tests.ps1 -Output Detailed"`
- `pwsh -c ". ./Tests/Test-PsGadgetWindows.ps1"` (hardware required)
- `pwsh -c "Import-Module ./PSGadget.psd1 -Force; Test-PsGadgetEnvironment"`

Publishing utility:

- See `Tools/Publish-PsGadget.ps1` for dry-run and gallery publish flow.

## Architecture and Boundaries

Authoritative references:

- Module loader and order: `PSGadget.psm1`
- FTDI assembly/bootstrap: `Private/Initialize-FtdiAssembly.ps1`
- Backend abstraction baseline: `Private/Ftdi.Backend.ps1`
- Platform backends: `Private/Ftdi.Windows.ps1`, `Private/Ftdi.Unix.ps1`, `Private/Ftdi.IoT.ps1`, `Private/Ftdi.PInvoke.ps1`
- MPSSE and CBUS helpers: `Private/Ftdi.Mpsse.ps1`, `Private/Ftdi.Cbus.ps1`

Current loader order in `PSGadget.psm1`:

1. Classes in dependency order: `PsGadgetLogger.ps1`, `PsGadgetI2CDevice.ps1`, `PsGadgetSsd1306.ps1`, `PsGadgetFtdi.ps1`, `PsGadgetMpy.ps1`, `PsGadgetPca9685.ps1`
2. All files in `Private/`
3. All files in `Public/`
4. FTDI initialization
5. Environment initialization

## Code Conventions

- Public functions follow `Verb-PsGadget*` naming.
- Private helpers use descriptive names like `Initialize-*` or `Invoke-[Technology][Platform][Action]`.
- Every class includes `[PsGadgetLogger]$Logger`, initializes it in the constructor, and logs operations.
- Environment setup paths should use `[Environment]::GetFolderPath("UserProfile")` and `Join-Path`.
- For unimplemented hardware paths, use stub-first behavior by throwing and handling `NotImplementedException`, then returning safe stub data.

## Docs to Link Instead of Duplicating

Core project docs:

- Setup: `docs/INSTALL.md`, `docs/QUICKSTART.md`, `docs/PLATFORMS.md`
- Troubleshooting: `docs/TROUBLESHOOTING.md`
- Architecture: `docs/ARCHITECTURE.md`, `docs/wiki/Architecture.md`
- Function reference: `docs/wiki/Function-Reference.md`, `docs/REFERENCE/Cmdlets.md`
- Classes: `docs/REFERENCE/Classes.md`
- Personas and writing depth: `docs/PERSONAS.md`
- Hardware kit and FT232H notes: `docs/HARDWARE_KIT.md`, `docs/about_adafruit_ft232h.md`
- Workflow map: `examples/psgadget_workflow.md`

Rule: Link to these docs instead of copying large sections into instructions.

## Examples Conventions

- Example walkthroughs are markdown-first and live in `examples/`.
- Follow persona callouts from `docs/PERSONAS.md`.
- Keep `examples/psgadget_workflow.md` synchronized with any public API or capability changes.
- When changing function names, parameters, or capabilities, update both examples and workflow reference content.

## Change Safety Checklist

Before finishing a task:

1. Confirm no Unicode symbols were added to PowerShell code or comments.
2. Run module import and relevant tests.
3. If public API changed, update `PSGadget.psd1`, affected `Public/*.ps1`, and docs/examples.
4. If hardware-specific behavior changed, preserve stub-safe fallback paths.
5. If markdown files were edited and are long, verify ToC placement and links.
