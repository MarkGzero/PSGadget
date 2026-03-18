# PSGadget Architecture

This document describes how PSGadget is structured internally. It is intended
for contributors, engineers integrating at a low level, and anyone who wants to
understand why the code is organised the way it is.

---

## Table of Contents

- [Pick your path](#pick-your-path)
- [High-level overview](#high-level-overview)
- [Layer breakdown](#layer-breakdown)
  - [Transport layer](#transport-layer)
  - [Protocol layer](#protocol-layer)
  - [Device layer](#device-layer)
  - [API layer](#api-layer)
- [File map](#file-map)
- [Module load order](#module-load-order)
- [Backend selection logic](#backend-selection-logic)
- [Stub mode](#stub-mode)
- [Design rules](#design-rules)

---

## Pick your path

- [High-level overview (everyone)](#high-level-overview)
- [Layer breakdown (Engineer / contributor)](#layer-breakdown)
- [File map (Pro / contributor)](#file-map)
- [Module load order (contributor)](#module-load-order)
- [Backend selection logic (Engineer)](#backend-selection-logic)
- [Stub mode (all platforms)](#stub-mode)

---

## High-level overview

PSGadget has four layers. Each layer talks only to the layer below it:

```
+-------------------------------------------------------+
|  API Layer        Public/*.ps1                        |
|  Thin cmdlet wrappers, parameter validation, output   |
+-------------------------------------------------------+
|  Device Layer     Classes/PsGadgetFtdi.ps1            |
|                   Classes/PsGadgetSsd1306.ps1         |
|  Chip logic, register maps, mode and state management |
+-------------------------------------------------------+
|  Protocol Layer   Private/Ftdi.Mpsse.ps1              |
|                   Private/Ftdi.Cbus.ps1               |
|  MPSSE byte sequences, I2C/SPI primitives,            |
|  GPIO direction + value state, ACK validation         |
+-------------------------------------------------------+
|  Transport Layer  Private/Ftdi.Windows.ps1            |
|                   Private/Ftdi.Unix.ps1               |
|                   Private/Ftdi.Backend.ps1            |
|                   lib/ (managed + native DLLs)        |
|  USB open/close, raw read/write, device enumeration   |
+-------------------------------------------------------+
```

Code in a higher layer calls functions from the layer directly beneath it.
Public cmdlets do not call MPSSE functions directly; they call device-layer
methods which in turn call protocol functions.

---

## Layer breakdown

### Transport layer

**Purpose**: open and close the USB device, send and receive raw bytes,
enumerate connected devices.

**Files**:
- `Private/Initialize-FtdiAssembly.ps1` -- loads the correct managed DLL for
  the current runtime (see Backend selection logic below)
- `Private/Ftdi.Windows.ps1` -- D2XX operations on Windows:
  - `Invoke-FtdiWindowsEnumerate` -- list connected FTDI devices
  - `Invoke-FtdiWindowsEnumerateVcp` -- enumerate VCP-mode devices
  - `Invoke-FtdiWindowsOpen` -- open device via FTD2XX_NET
  - `Invoke-FtdiWindowsOpenSharp` -- open device via FtdiSharp
  - `Invoke-FtdiWindowsClose` -- close device and release handle
- `Private/Ftdi.Unix.ps1` -- platform operations on Linux/macOS:
  - `Invoke-FtdiUnixEnumerate` -- list connected FTDI devices
  - `Invoke-FtdiUnixStubs` -- return simulated stub devices
  - `Invoke-FtdiUnixOpen` -- open device via IoT or stub
  - `Invoke-FtdiUnixClose` -- close device
- `Private/Ftdi.Backend.ps1` -- platform-agnostic dispatch:
  - `Get-FtdiChipCapabilities` -- single source of truth for chip GPIO method,
    pin count, MPSSE capability, notes
  - `Get-FtdiDeviceList` -- calls Windows or Unix enumerate based on runtime
- `Private/Ftdi.IoT.ps1` -- .NET IoT (Iot.Device.Bindings) operations,
  used on PS 7.4+ / .NET 8+

**Does not**:
- Know about I2C, SPI, or MPSSE.
- Know about register maps or device protocols.

---

### Protocol layer

**Purpose**: build MPSSE command byte sequences, implement I2C/SPI/GPIO
primitives, manage GPIO direction and value state.

**Files**:
- `Private/Ftdi.Mpsse.ps1`:
  - `Set-FtdiGpioPins` -- set ACBUS direction and value via MPSSE command 0x82;
    uses read-modify-write to preserve unrelated pin state
  - `Get-FtdiGpioPins` -- read current ACBUS direction and value bytes
  - `Send-MpsseAcbusCommand` -- send raw MPSSE ACBUS command bytes
  - `Initialize-MpsseI2C` -- configure MPSSE for I2C: disable clock÷5, set
    60 MHz base, program clock divisor, set SDA/SCL pins idle
  - `Send-MpsseI2CWrite` -- I2C write with start/address/data/stop; validates
    ACK after each byte and throws on NACK
  - `Invoke-FtdiI2CScan` -- scan all 7-bit I2C addresses and return responders
- `Private/Ftdi.Cbus.ps1` -- FT232R CBUS bit-bang operations:
  - SetBitMode(0x20) with 8-bit mask (4 direction + 4 value)
  - EEPROM programming for CBUS pin function
- `Private/Mpy.Backend.ps1` -- MicroPython serial REPL operations via mpremote

**Does not**:
- Know about SSD1306 registers or other device protocols.
- Call transport functions directly; it receives an already-open device handle.

---

### Device layer

**Purpose**: chip-specific and device-specific logic -- register maps, init
sequences, mode management, connection lifecycle.

**Files**:
- `Classes/PsGadgetFtdi.ps1` -- `PsGadgetFtdi` class:
  - Wraps a transport handle
  - Owns connect/close lifecycle
  - Exposes `SetPin`, `SetPins`, `PulsePin`, `Scan`, `Display`
  - Determines GPIO method from chip capabilities and routes to MPSSE or CBUS
- `Classes/PsGadgetSsd1306.ps1` -- `PsGadgetSsd1306` class:
  - SSD1306 init sequence (contrast, display on, memory mode)
  - Page-based text rendering
  - Cursor positioning
  - Calls `Send-MpsseI2CWrite` with correct register addresses (0x00 = command,
    0x40 = data)
- `Classes/PsGadgetMpy.ps1` -- `PsGadgetMpy` class:
  - Serial REPL connection state
  - `Invoke` method wraps `Invoke-NativeProcess` with mpremote
- `Classes/PsGadgetLogger.ps1` -- `PsGadgetLogger` class:
  - Required member of every other class
  - Always writes to `~/.psgadget/logs/psgadget.log`
  - Verbose console output is separate and optional

**Does not**:
- Contain raw MPSSE opcodes unless explicitly documented with the opcode value
  and its source in the FTDI Application Note.

---

### API layer

**Purpose**: expose public cmdlets. Thin wrappers only. No hardware logic here.

**Files**: `Public/*.ps1` -- one file per exported function.

Each cmdlet:
- Validates and coerces parameters
- Calls one or more device-layer methods or class constructors
- Returns pipeline-friendly output (`PSCustomObject` or typed objects)
- Follows PowerShell naming conventions (`Verb-PsGadget*`)

---

## File map

```
PSGadget/
  PSGadget.psd1                  Module manifest
  PSGadget.psm1                  Loader (dot-sources files in strict order)
  Classes/
    PsGadgetLogger.ps1           Logging class (loaded first -- all classes depend on it)
    PsGadgetFtdi.ps1             FTDI device class (Device layer)
    PsGadgetMpy.ps1              MicroPython class (Device layer)
    PsGadgetSsd1306.ps1          SSD1306 class (Device layer)
  Private/
    Initialize-FtdiAssembly.ps1  DLL selection and loading (Transport)
    Initialize-PsGadgetConfig.ps1  Config file setup
    Initialize-PsGadgetEnvironment.ps1  ~/.psgadget/ directory creation
    Ftdi.Backend.ps1             Device enumeration dispatch (Transport)
    Ftdi.Windows.ps1             Windows D2XX operations (Transport)
    Ftdi.Unix.ps1                Linux/macOS operations (Transport)
    Ftdi.IoT.ps1                 .NET IoT operations (Transport, PS 7.4+)
    Ftdi.Mpsse.ps1               MPSSE I2C/GPIO primitives (Protocol)
    Ftdi.Cbus.ps1                FT232R CBUS operations (Protocol)
    Invoke-NativeProcess.ps1     External process runner (timeout, encoding)
    Mpy.Backend.ps1              mpremote operations (Protocol)
  Public/
    Test-PsGadgetEnvironment.ps1
    Get-FTDevice.ps1
    Connect-PsGadgetFtdi.ps1
    New-PsGadgetFtdi.ps1
    Set-PsGadgetGpio.ps1
    Set-PsGadgetFtdiMode.ps1
    Set-PsGadgetFt232rCbusMode.ps1
    Get-PsGadgetFtdiEeprom.ps1
    Invoke-PsGadgetI2C.ps1
    Get-PsGadgetMpy.ps1
    Connect-PsGadgetMpy.ps1
    Get-PsGadgetConfig.ps1
    Set-PsGadgetConfig.ps1
  lib/
    net48/FTD2XX_NET.dll         PS 5.1 / .NET Framework 4.8
    netstandard20/FTD2XX_NET.dll PS 7.0-7.3 / .NET 6-7; FT232R fallback on PS 7.4+
    net8/                        PS 7.4+ / .NET 8+ IoT DLLs
    native/FTD2XX.DLL            Windows x64 native D2XX (included for reference)
    ftdisharp/FtdiSharp.dll      Optional FtdiSharp managed wrapper
  Tests/
    PsGadget.Tests.ps1           Pester unit + integration tests (CI-safe, stub mode)
    Test-PsGadgetWindows.ps1     Manual Windows hardware validation
```

---

## Module load order

`PSGadget.psm1` dot-sources files in this exact order. Do not change it:

1. `Classes/PsGadgetLogger.ps1`   -- must be first; all classes depend on it
2. `Classes/PsGadgetFtdi.ps1`
3. `Classes/PsGadgetMpy.ps1`
4. `Classes/PsGadgetSsd1306.ps1`
5. All `Private/*.ps1` files (glob, alphabetical)
6. All `Public/*.ps1` files (glob, alphabetical)
7. `Initialize-FtdiAssembly` call -- sets `$script:FtdiInitialized`,
   `$script:D2xxLoaded`, `$script:IotBackendAvailable`
8. `Initialize-PsGadgetEnvironment` call -- creates `~/.psgadget/logs/`

---

## Backend selection logic

`Initialize-FtdiAssembly` selects the managed DLL at module import time based
on the PowerShell and .NET version:

```
PS version   .NET version   Backend chosen
----------   ------------   --------------
5.1          4.8 (netfx)    lib/net48/FTD2XX_NET.dll
7.0-7.3      6 or 7         lib/netstandard20/FTD2XX_NET.dll
7.4+         8+             lib/net8/Iot.Device.Bindings.dll  (primary)
                            lib/netstandard20/FTD2XX_NET.dll  (FT232R CBUS,
                                                               Windows only)
```

On Linux and macOS, the managed DLLs load successfully but all hardware calls
require `libftd2xx.so` / `libftd2xx.dylib` to be installed separately.
If the native library is not found, the module emits a warning at import and
hardware functions fall back to stub mode.

Script-scope flags set after loading:

| Flag | Type | Meaning |
|------|------|---------|
| `$script:IotBackendAvailable` | bool | .NET IoT DLLs loaded and verified |
| `$script:D2xxLoaded` | bool | FTD2XX_NET.dll loaded and FT_OK constant accessible |
| `$script:FtdiInitialized` | bool | Any backend loaded successfully |

---

## Stub mode

When no backend loads (missing native library, unsupported platform, or
development machine with no hardware), all device operations run in stub mode:

- `Get-FTDevice` returns two simulated devices (FT232H + FT232R).
- `Connect-PsGadgetFtdi` returns a stub handle.
- GPIO and I2C calls log to the method but do not send bytes.
- `Test-PsGadgetEnvironment` reports `Backend: Stub (no hardware access)`.

Stub mode is implemented via `try/catch [System.NotImplementedException]`
blocks in platform-specific backend functions. Real hardware errors are caught
separately and re-thrown.

---

## Design rules

1. **No hardware logic in Public/*.ps1.** Cmdlets call class methods or
   private functions. They do not contain byte arrays or protocol constants.

2. **No MPSSE opcodes in Classes/*.ps1** unless the opcode is explicitly
   referenced with its FTDI Application Note source.

3. **Logging is always on.** `PsGadgetLogger` writes to the log file on every
   significant operation. Verbose console output is separate.

4. **Read-modify-write for GPIO.** `Set-FtdiGpioPins` reads the current pin
   state before applying changes. Callers may not assume all other pins are
   in a known state.

5. **ACK must be validated.** `Send-MpsseI2CWrite` reads the ACK bit after
   every byte and throws a terminating error on NACK.

6. **PS 5.1 compatible.** No ternary `?:`, no `?.`, no `??`, no pipeline
   chaining operators. Verified on .NET Framework 4.8.

7. **ASCII only.** No Unicode characters in any file in this repository.
## Maintaining bundled libraries

PSGadget bundles NuGet-sourced .NET assemblies in `lib/`. This section
explains how to audit them for vulnerabilities and keep them up to date.
This is a contributor / maintainer task -- end users do not need to do this.

### Prerequisites

- [.NET SDK 8+](https://dotnet.microsoft.com/download) on PATH
- PowerShell 7+ (for the update script)

### Which DLLs are covered

| DLL | Source | Auditable? |
|-----|--------|------------|
| `lib/net8/System.Device.Gpio.dll` | NuGet | Yes |
| `lib/net8/Iot.Device.Bindings.dll` | NuGet | Yes |
| `lib/net8/UnitsNet.dll` | NuGet | Yes |
| `lib/net8/Microsoft.Extensions.Logging.Abstractions.dll` | NuGet | Yes |
| `lib/ftdisharp/FtdiSharp.dll` | NuGet | Yes |
| `lib/native/FTD2XX.dll` | FTDI vendor zip | Manual only |
| `lib/net48/FTD2XX_NET.dll` | FTDI vendor zip | Manual only |
| `lib/netstandard20/FTD2XX_NET.dll` | FTDI vendor zip | Manual only |

NuGet versions are declared in `lib/nuget-deps.csproj`.

### Audit for vulnerabilities

```powershell
# Shows CVE report and outdated package list; does not change any files
pwsh ./Tools/Update-PsGadgetLibs.ps1 -Audit
```

Expected clean output:
```
Running vulnerability scan...
The given project `nuget-deps` has no vulnerable packages given the current sources.

Running outdated check...
The given project `nuget-deps` has no updates given the current sources.
```

If outdated packages are listed, see [Updating NuGet DLLs](#updating-nuget-dlls) below.

### Checking for changes without writing (dry run)

```powershell
# Compares SHA-256 of bundled DLLs against what NuGet restore would give.
# Reports [OK] or [CHANGED] per package. Does not copy anything.
pwsh ./Tools/Update-PsGadgetLibs.ps1
```

### Updating NuGet DLLs

1. Bump the version number(s) in `lib/nuget-deps.csproj`.
2. Update the matching version strings in `lib/README.md`.
3. Run the apply step:

```powershell
pwsh ./Tools/Update-PsGadgetLibs.ps1 -Apply
```

The script:
- Restores packages to a temp directory using `dotnet restore`
- Compares SHA-256 hashes of each DLL against the bundled copy
- Copies only those that differ, reporting `[UPDATED]` per file
- Leaves all other files untouched

Verify afterwards:
```powershell
# Should report [OK] for every package
pwsh ./Tools/Update-PsGadgetLibs.ps1
```

Then bump `ModuleVersion` in `PSGadget.psd1` and commit.

### Updating FTDI vendor DLLs (manual)

The three FTDI DLLs are not on NuGet and must be updated manually:

1. Download the latest D2XX driver package from https://ftdichip.com/drivers/d2xx-drivers/
2. Extract `FTD2XX_NET.dll` from both the `net48/` and `netstandard2.0/` subdirectories
3. Replace `lib/net48/FTD2XX_NET.dll` and `lib/netstandard20/FTD2XX_NET.dll`
4. Replace `lib/native/FTD2XX.dll` with the native DLL from the same package
5. Update the version comment in `lib/README.md` and `lib/nuget-deps.csproj`

### Automated CI scanning

A GitHub Actions workflow (`.github/workflows/lib-audit.yml`) runs the
vulnerability scan weekly (Mondays at 08:00 UTC) and on every PR that
changes `lib/nuget-deps.csproj`. It will fail the build if any CVE is
found and upload a full report as an artifact.

### Troubleshooting the update script

| Error | Cause | Fix |
|-------|-------|-----|
| `dotnet SDK not found on PATH` | dotnet not installed | Install from https://dotnet.microsoft.com/download |
| `Package cache not found for X` | Package ID mismatch or restore failed | Check package ID spelling in `nuget-deps.csproj`; run `dotnet restore lib/nuget-deps.csproj` manually and inspect output |
| `DLL not found in package cache for X` | Package does not contain the expected DLL filename for any TFM | Run `dotnet restore lib/nuget-deps.csproj --packages /tmp/pkgcache` and inspect the package directory to find the actual DLL path; update `$LibMap` in the script |
| Hash mismatch reported but `-Apply` reports `[OK]` | DLL was already up to date (different build but same bytes) | Ignore if `-Audit` shows no vulnerabilities |
| `NU1701` warning on FtdiSharp | FtdiSharp targets net4x, not netstandard2.0 | Expected and harmless -- FtdiSharp is loaded via `LoadFrom()`, not as a build reference |

---

