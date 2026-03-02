# PsGadget PowerShell Module - AI Agent Guidelines

## Project Scope

**IMPORTANT: Focus on PSGadget Repository Only**: When working in this workspace, only modify files within the `psgadget/` directory. Other folders (`psgadget_reference/`, `summitpiserver/`, etc.) are for reference only and should NOT be modified. If you need examples or patterns from reference folders, you may read them but never edit them.

## Formatting and Communication Style

**CRITICAL: No Unicode Characters in Code**: NEVER use Unicode characters (✓✗➜→←↑↓○●◆■♠♦♥♣★☆♪♫♬※⚡⚠⬜⬛✅❌⭐🔴🟢🟡🔵⟨⟩⟪⟫❓❗💡🎯🎮🎲📝📊📈📉📋📌📍📎🔗🔒🔓🔑⭕❎🚫🛑) in PowerShell code, comments, or strings. These characters cause PowerShell parsing errors on Windows platforms, resulting in "Try statement is missing its Catch or Finally block" and similar cryptic errors. Instead use:
- `[OK]` or `PASS` instead of ✓
- `[FAIL]` or `ERROR` instead of ✗  
- `->` instead of →
- ASCII text and punctuation only

**No Emojis or Decorative Symbols**: Do not use emojis, unicode icons, or decorative symbols in code, comments, documentation, or responses unless explicitly requested by the user. Keep all text clean and professional using standard ASCII characters only.

**Plain Text Formatting**: Use standard markdown formatting (headers, lists, code blocks) without decorative elements. Focus on clarity and readability over visual appeal.

**Markdown Table of Contents**: Every markdown document (`.md`) longer than one screen must include a Table of Contents immediately after the opening description block, before the first `##` section. Use standard GitHub anchor links (lowercase, spaces to hyphens, punctuation removed). Maintain the ToC any time sections are added, removed, or renamed.

## Code Style

**PowerShell Compatibility**: All code must work in PowerShell 5.1+ (use `#Requires -Version 5.1`). Avoid PS7-only features like ternary operators (`?:`), null-conditional operators (`?.`), and null-coalescing operators (`??`). Use `[System.Environment]::OSVersion.Platform -eq 'Win32NT'` or `$PSVersionTable.PSVersion.Major -le 5` for platform detection (not `$IsWindows`).

**Function Naming**: Public functions use `Verb-PsGadge*` pattern. Private helpers use descriptive names like `Initialize-*` or `Invoke-[Technology][Platform][Action]`. See [Public/](Public/) for examples.

**Class Pattern**: Every class must include `[PsGadgetLogger]$Logger` and instantiate it in constructor with creation log entry. See [Classes/PsGadgetLogger.ps1](Classes/PsGadgetLogger.ps1) for the logging class template.

## Architecture

**Module Load Order**: [PsGadget.psm1](PsGadget.psm1) loads in this strict order - never change it:
1. Classes (dependency order): `PsGadgetLogger.ps1`, `PsGadgetFtdi.ps1`, `PsGadgetMpy.ps1`
2. All Private functions (glob)
3. All Public functions (glob)
4. FTDI assembly initialization via `Initialize-FtdiAssembly` (sets `$script:FtdiInitialized`)
5. Environment setup via `Initialize-PsGadgetEnvironment`

**Assembly Layout** (`lib/`):
- `lib/native/FTD2XX.dll` - native Windows D2XX driver
- `lib/net48/FTD2XX_NET.dll` - managed wrapper for PowerShell 5.1 (net48)
- `lib/netstandard20/FTD2XX_NET.dll` - managed wrapper for PowerShell 7+ (netstandard2.0)

[Initialize-FtdiAssembly.ps1](Private/Initialize-FtdiAssembly.ps1) selects the correct DLL based on `$PSVersionTable.PSVersion.Major` (5 -> net48, 7+ -> netstandard20) and loads it via `[Reflection.Assembly]::LoadFrom()`. On Unix it returns `$false` and the module operates in stub mode.

**Platform Abstraction**: Hardware backends in [Private/](Private/) follow the pattern: `Technology.Backend.ps1` (common interface), `Technology.Windows.ps1` / `Technology.Unix.ps1` (platform-specific). Use [Ftdi.Backend.ps1](Private/Ftdi.Backend.ps1) as the template.

**MPSSE Support**: [Ftdi.Mpsse.ps1](Private/Ftdi.Mpsse.ps1) provides FTDI MPSSE (Multi-Protocol Synchronous Serial Engine) helpers for SPI/I2C/JTAG bit-bang operations on top of the D2XX layer.

**Stub-First Development**: Use this exact pattern for unimplemented hardware logic:
```powershell
try {
    throw [System.NotImplementedException]::new("Feature not yet implemented")
} catch [System.NotImplementedException] {
    # Return stub data for development
} catch {
    # Handle real errors
}
```

## Build and Test

```bash
# Load module for development
pwsh -c "Import-Module ./PSGadget.psd1 -Force"

# Run Pester test suite
pwsh -c "Import-Module Pester; Invoke-Pester ./Tests/PsGadget.Tests.ps1 -Output Detailed"

# Run Windows-specific hardware tests (requires physical FTDI device)
pwsh -c ". ./Tests/Test-PsGadgetWindows.ps1"

# Smoke-test cross-platform functions
List-PsGadgetFtdi | Format-Table
Connect-PsGadgetFtdi -Index 0
```

**Test Files**:
- [Tests/PsGadget.Tests.ps1](Tests/PsGadget.Tests.ps1) - Pester unit/integration tests (CI-safe, stub mode)
- [Tests/Test-PsGadgetWindows.ps1](Tests/Test-PsGadgetWindows.ps1) - manual Windows hardware validation (requires physical FTDI device)

## Project Conventions

**Automatic Logging**: Every class method must log operations via `$this.Logger.WriteInfo()`. Use levels: INFO (operations), DEBUG (parameters), TRACE (detailed flow), ERROR (failures).

**Environment Setup**: Module automatically creates `~/.psgadget/logs/` on import via [Initialize-PsGadgetEnvironment.ps1](Private/Initialize-PsGadgetEnvironment.ps1). Use `[Environment]::GetFolderPath("UserProfile")` not `~`.

**Error Handling**: Environment setup failures use `Write-Warning`, don't throw. Hardware operations throw on real errors but gracefully degrade on `NotImplementedException`.

**Cross-Platform Paths**: Always use `Join-Path`. Use .NET methods like `[System.IO.Ports.SerialPort]::GetPortNames()` for cross-platform compatibility.

**Module Version**: Current version is `0.1.0` (see [PSGadget.psd1](PSGadget.psd1)). Bump `ModuleVersion` when adding or changing exported functions.

## Integration Points

**FTDI Hardware**: Assembly loaded by [Initialize-FtdiAssembly.ps1](Private/Initialize-FtdiAssembly.ps1). Real D2XX device logic goes in [Ftdi.Windows.ps1](Private/Ftdi.Windows.ps1) and [Ftdi.Unix.ps1](Private/Ftdi.Unix.ps1). MPSSE helpers in [Ftdi.Mpsse.ps1](Private/Ftdi.Mpsse.ps1). Device class in [Classes/PsGadgetFtdi.ps1](Classes/PsGadgetFtdi.ps1).

**MicroPython**: `mpremote` integration via [Mpy.Backend.ps1](Private/Mpy.Backend.ps1) using [Invoke-NativeProcess.ps1](Private/Invoke-NativeProcess.ps1) helper. Pattern: `mpremote connect {port} exec {code}`.

**Process Execution**: Use [Invoke-NativeProcess.ps1](Private/Invoke-NativeProcess.ps1) for all external commands. Includes timeout control, UTF-8 encoding, and proper stream handling.

**Exported Public Functions** (defined in [PSGadget.psd1](PSGadget.psd1)):
- `List-PsGadgetFtdi` - enumerate connected FTDI devices
- `Connect-PsGadgetFtdi` - open a connection to an FTDI device by index
- `List-PsGadgetMpy` - enumerate MicroPython serial ports
- `Connect-PsGadgetMpy` - open a MicroPython REPL connection
- `Set-PsGadgetGpio` - set GPIO pin state on a connected device

Never modify exports in [PSGadget.psd1](PSGadget.psd1) without updating the corresponding Public function file. All hardware logic should be stubbed first, then incrementally implemented.

## Examples and Workflow Documentation

### Four Audience Personas

All documentation and walkthroughs in `examples/` are written with four readers in mind.
When adding or updating example files, include content that serves each persona, using
clearly labeled callout blocks (`> **Beginner**:`, `> **Scripter**:`, `> **Engineer**:`, optional
`> **Pro**:` for advanced notes). Tailor the depth as follows:

- **Beginner (Nikola)** - Complete beginner. No assumed knowledge of USB, drivers, microcontrollers,
  or PowerShell beyond "open a terminal". Needs every concept explained, every command
  justified. Use plain language, avoid jargon without definition.

- **Scripter (Jordan)** - PowerShell amateur with limited hardware integration knowledge.
  Comfortable writing scripts, knows module import, pipelines, objects. Does not know
  about GPIO, I2C, FTDI drivers, EEPROM, or how USB hardware enumeration works. Explain
  hardware concepts; assume PowerShell syntax is already understood.

- **Engineer (Izzy)** - Freshman college background in basic mechanical and electrical engineering.
  Understands circuits, voltage levels, digital I/O, I2C/SPI protocols, datasheets, and
  pin-level hardware concepts. Less familiar with the Windows driver stack, PowerShell
  module system, and D2XX API. Explain software and tooling; assume basic hardware knowledge.

- **Pro (Scott)** - Savvy with both PowerShell and hardware/electronics. Reads reference tables
  and command lists; does not need step-by-step instructions. Include a Quick Reference
  section at the bottom of each walkthrough.

### Example File Format

Examples in `examples/` are **Markdown walkthroughs** (`.md`), not executable `.ps1` scripts.
Each walkthrough follows this structure:

1. Title and one-sentence purpose
2. Persona audience block (list all four personas)
3. What You Need (hardware + software prerequisites)
4. Hardware Background (with Izzy and Nikola callouts where relevant)
5. Step-by-step instructions with persona callouts embedded inline
6. Complete copy-paste script block at the end (runnable code)
7. Troubleshooting section
8. Quick Reference section for Scott (Pro)

Name example files `Example-<Feature>.md`. When a `.ps1` example is needed as a companion
runnable file (e.g. for automation or CI), name it `Example-<Feature>.ps1` and cross-reference
it from the markdown.

### Workflow Reference

**Maintain [examples/psgadget_workflow.md](../examples/psgadget_workflow.md) as a living reference document.**

Rules for keeping it current:
- When a new device type gains GPIO or other public-API support, add an H2 section for it following the existing FT232H / FT232R pattern (enumerate -> setup steps -> commands -> pin map).
- When a public function is added, renamed, or its parameters change, update both the inline code examples for the affected device section AND the Public Function Quick Reference table at the bottom of the file.
- When a device's capability changes (e.g., async bit-bang for FT232R is implemented), update the Device Capability Comparison table and remove any "not yet implemented" notes.
- After every session that changes public behavior, verify the workflow file is still accurate by re-reading it alongside the current public function signatures.

---

## External Context: PSGadget CTF Server (Separate Project - Read Only)

The CTF scoring backend is a **separate Flask project** running on a Raspberry Pi 4B+ in an
isolated VLAN. **The server is live at `https://psgadget.ltdl.familyds.com:56826`.**
Do NOT add server code to this repository. This section exists so agents
understand how PsGadget hardware-side work fits into the overall CTF architecture.

### Architecture Overview

```
[FTDI Device / GPIO] --triggers--> [ESP32] --generates flag--> [OLED display]
                                                                     |
                                                              [Contestant reads flag]
                                                                     |
                                                      POST /api/submit {gadget_id, flag}
                                                                     |
                                                    [CTF Server - Flask / Raspberry Pi]
```

**Critical design principle**: The ESP32 NEVER communicates with the server during a
challenge. It is an autonomous flag generator; the server only validates submitted flags
using HMAC-SHA256.

### Cryptographic Flag Protocol

The ESP32 generates flags as follows:
1. Generate a random 4-byte nonce (e.g. `0xDEADBEEF`)
2. Compute `TAG = LSB32(HMAC-SHA256(gadget_key_bytes, nonce_bytes))` (last 4 bytes of digest)
3. Display on OLED: `DEADBEEF-9F22E10B` (uppercase hex, 8+8 chars separated by `-`)
4. Contestant submits that string as the `flag` field via the API

**PSGadget implication**: MicroPython scripts on ESP32 must implement this exact HMAC
derivation using `uhashlib.sha256` and `hmac` or manual HMAC over `uhashlib`. The
`gadget_key` is provisioned per-device via the CTF server admin API and must be flashed
onto the device (e.g. in `ctf_config.json` as `flag_secret` in base64 or hex).

### CTF Server API - PSGadget-Relevant Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | /api/register | Register contestant; returns plaintext apiKey (shown once) |
| POST | /api/submit | Submit flag: body `{gadget_id, flag}`, header `X-API-Key: <key>` |
| GET | /api/gadgets | List active gadgets with IDs, names, point values |
| GET | /api/board | Leaderboard: `[{rank, username, score}]` |
| GET | /api/activity-feed | Recent submission events |
| POST | /api/admin/gadgets | Admin: create gadget |
| PUT | /api/admin/gadgets/<id>/provision | Admin: set gadget HMAC key and optional FTDI serial |

### /api/submit Behavior (Important for Hardware-Side Design)

- Flag format MUST be `XXXXXXXX-YYYYYYYY` (8 uppercase hex + dash + 8 uppercase hex).
- A nonce can only be redeemed once globally (prevents flag sharing between contestants).
- A contestant can only complete each gadget once (no repeat scoring).
- Returns `409` if the same user tries to reuse their own flag -- the ESP32 must generate
  a fresh nonce each time the physical challenge is completed.
- Returns `{success, gadget_id, points_awarded, total_score, rank}` on success.

### Configuration Integration

When building CTF firmware for ESP32 via `Install-PsGadgetMpyScript`:
- `gadget_id` and `gadget_key` must match the values provisioned on the CTF server.
- `gadget_key` is provisioned via `PUT /api/admin/gadgets/<id>/provision` (returns base64 key).
- Store the key in `ctf_config.json` as `flag_secret` (hex or base64 -- MicroPython script
  must decode accordingly before calling HMAC).
- The `challenge_id` field in `ctf_config.json` maps directly to the server's `gadget_id`.

### PowerShell CTF Client Helper (Future)

A future `Submit-PsGadgetCtfFlag` public function may wrap `/api/submit` using
`Invoke-WebRequest` for in-terminal flag submission. It would accept `-ApiKey`, `-GadgetId`,
and `-Flag` parameters and return the parsed JSON response object. This is NOT yet
implemented -- note it here to avoid re-planning from scratch.