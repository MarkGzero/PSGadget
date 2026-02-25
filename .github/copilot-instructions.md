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