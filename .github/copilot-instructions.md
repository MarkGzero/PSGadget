# PsGadget PowerShell Module - AI Agent Guidelines

## Formatting and Communication Style

**No Emojis or Unicode Icons**: Do not use emojis, unicode icons, or decorative symbols in code, comments, documentation, or responses unless explicitly requested by the user. Keep all text clean and professional using standard ASCII characters only.

**Plain Text Formatting**: Use standard markdown formatting (headers, lists, code blocks) without decorative elements. Focus on clarity and readability over visual appeal.

## Code Style

**PowerShell Compatibility**: All code must work in PowerShell 5.1+ (use `#Requires -Version 5.1`). Avoid PS7-only features like ternary operators (`?:`), null-conditional operators (`?.`), and null-coalescing operators (`??`). Use `[System.Environment]::OSVersion.Platform -eq 'Win32NT'` or `$PSVersionTable.PSVersion.Major -le 5` for platform detection (not `$IsWindows`).

**Function Naming**: Public functions use `Verb-PsGadge*` pattern. Private functions use `Invoke-[Technology][Platform][Action]` format. See [Public/](Public/) for examples.

**Class Pattern**: Every class must include `[PsGadgetLogger]$Logger` and instantiate it in constructor with creation log entry. See [Classes/PsGadgetLogger.ps1](Classes/PsGadgetLogger.ps1) for the logging class template.

## Architecture

**Module Structure**: [PsGadget.psm1](PsGadget.psm1) loads in strict order: Classes first (dependency order), then Private, then Public, then environment initialization. Never change this order.

**Platform Abstraction**: Hardware backends in [Private/](Private/) follow pattern: `Technology.Backend.ps1` (common interface), `Technology.Windows.ps1`/`Technology.Unix.ps1` (platform-specific). Use [Ftdi.Backend.ps1](Private/Ftdi.Backend.ps1) as template.

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
pwsh -c "Import-Module ./PsGadget.psd1 -Force"

# Run tests
pwsh -c "Import-Module Pester; Invoke-Pester ./Tests/"

# Test cross-platform functions
List-PsGadgetFtdi | Format-Table
Connect-PsGadgetFtdi -Index 0
```

## Project Conventions

**Automatic Logging**: Every class method must log operations via `$this.Logger.WriteInfo()`. Use levels: INFO (operations), DEBUG (parameters), TRACE (detailed flow), ERROR (failures).

**Environment Setup**: Module automatically creates `~/.psgadget/logs/` on import via [Initialize-PsGadgetEnvironment.ps1](Private/Initialize-PsGadgetEnvironment.ps1). Use `[Environment]::GetFolderPath("UserProfile")` not `~`.

**Error Handling**: Environment setup failures use `Write-Warning`, don't throw. Hardware operations throw on real errors but gracefully degrade on `NotImplementedException`.

**Cross-Platform Paths**: Always use `Join-Path` and forward slashes. Use .NET methods like `[System.IO.Ports.SerialPort]::GetPortNames()` for cross-platform compatibility.

## Integration Points

**FTDI Hardware**: Real D2XX integration goes in [Ftdi.Windows.ps1](Private/Ftdi.Windows.ps1) (ftd2xx.dll) and [Ftdi.Unix.ps1](Private/Ftdi.Unix.ps1) (libftdi). Device objects in [PsGadgetFtdi.ps1](Classes/PsGadgetFtdi.ps1).

**MicroPython**: `mpremote` integration via [Mpy.Backend.ps1](Private/Mpy.Backend.ps1) using [Invoke-NativeProcess.ps1](Private/Invoke-NativeProcess.ps1) helper. Pattern: `mpremote connect {port} exec {code}`.

**Process Execution**: Use [Invoke-NativeProcess.ps1](Private/Invoke-NativeProcess.ps1) for external commands. Includes timeout control, UTF-8 encoding, and proper stream handling.

Never modify exports in [PsGadget.psd1](PsGadget.psd1) without updating corresponding Public functions. All hardware logic should be stubbed first, then incrementally implemented.