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
- [Performance tiers](#performance-tiers)
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

```text
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

```text
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
    Get-FtdiDevice.ps1
    Connect-PsGadgetFtdi.ps1
    New-PsGadgetFtdi.ps1
    Set-PsGadgetGpio.ps1
    Set-PsGadgetFtdiMode.ps1
    Set-PsGadgetFt232rCbusMode.ps1
    Get-PsGadgetFtdiEeprom.ps1
    Connect-PsGadgetSsd1306.ps1
    Clear-PsGadgetSsd1306.ps1
    Write-PsGadgetSsd1306.ps1
    Set-PsGadgetSsd1306Cursor.ps1
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

```text
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

- `Get-FtdiDevice` returns two simulated devices (FT232H + FT232R).
- `Connect-PsGadgetFtdi` returns a stub handle.
- GPIO and I2C calls log to the method but do not send bytes.
- `Test-PsGadgetEnvironment` reports `Backend: Stub (no hardware access)`.

Stub mode is implemented via `try/catch [System.NotImplementedException]`
blocks in platform-specific backend functions. Real hardware errors are caught
separately and re-thrown.

---

## Performance tiers

Every operation you send to an FTDI chip passes through some number of
PowerShell and .NET layers before reaching the USB driver. Each layer adds
overhead: parameter binding, object property resolution, function call setup,
and log writes. For low-frequency operations the overhead is invisible. For
timing-sensitive operations you need to know exactly which layers you are
traversing and whether any of them can be eliminated.

Use this table to pick the right tier for your use case. Tiers are ordered
slowest to fastest -- lower tier number means fewer layers traversed.
Tiers 3 and 4 are only accessible when working inside the module source
(contributor context). External scripts can only reach Tiers 0, 1, 2, 5, 6, 7.

| Tier | Entry point | Accessible from | Layers crossed | Use case |
|------|-------------|-----------------|----------------|----------|
| 7 | `Set-PsGadgetGpio -Index n` (public, opens per call) | scripts | 6+ (API + enumerate + open + function + .NET -> USB + close) | One-shot operations only |
| 6 | `Set-PsGadgetGpio -Connection $conn` (public, pre-opened) | scripts | 4 (API param binding + function + read-modify-write + .NET -> USB) | LEDs, relays, solenoids |
| 5 | `$dev.SetPin()` (class method) | scripts | 4 (class + logger + API + function + .NET -> USB) | OOP style, human-speed operations |
| 4 | `Set-FtdiGpioPins` (private) | module source only | 3 (function + read-modify-write USB read + write) | Moderate frequency with auto pin-preservation |
| 3 | `Send-MpsseAcbusCommand` (private) | module source only | 2 (function + .NET -> USB) | Hot loops where caller manages pin state |
| 2 | Batched MPSSE buffer -- single `$ftdi.Write()` with N commands | scripts (`$dev._connection.device`) | 1 (.NET -> USB, one transaction for N commands) | Step sequences, multi-pin state machines |
| 1 | Raw .NET -- `$ftdi.Write([byte[]](0x82, val, dir))` | scripts (`$dev._connection.device`) | 1 (.NET -> USB) | PWM bit-bang, fastest single-command toggle |
| 0 | MPSSE hardware clock (I2C, SPI, JTAG) | scripts (public functions) | 0 (timing done in FTDI chip silicon) | High-speed serial protocols; PS only sends the payload |

### Tier 7 -- Full open/close per call

```powershell
Set-PsGadgetGpio -Index 0 -Pins @(2) -State HIGH
```

What happens on every call:

1. `Set-PsGadgetGpio` binds parameters, resolves ParameterSetName
2. `Get-FtdiDeviceList` calls `GetNumberOfDevices` + `GetDeviceList` (two USB commands)
3. `Connect-PsGadgetFtdi` retry loop, opens D2XX handle, sends MPSSE init sequence (3 bytes)
4. `Set-FtdiGpioPins` reads current pin state (USB read), computes bitmask
5. `Send-MpsseAcbusCommand` writes 3-byte MPSSE command
6. `$connection.Close()` releases D2XX handle

The USB open/close alone costs ~10-50 ms on Windows. Use this tier only
for operations that happen once per script run (provisioning, relay set-and-forget).

### Tier 6 -- Public function, pre-opened connection

```powershell
$conn = Connect-PsGadgetFtdi -Index 0
Set-PsGadgetGpio -Connection $conn -Pins @(2) -State HIGH   # in a loop
$conn.Close()
```

Eliminates the enumeration and open/close cost. Still pays full PowerShell parameter binding on every call and does a USB read inside `Set-FtdiGpioPins` to preserve unrelated pins (read-modify-write).

Suitable for LED blink patterns, relay sequencing, motor enable/disable at human-visible speeds (< ~100 calls/second).

### Tier 5 -- Class method

```powershell
$dev = New-PsGadgetFtdi -Index 0
$dev.SetPin(2, "HIGH")   # in a loop
$dev.Close()
```

`SetPin()` calls `Set-PsGadgetGpio -Connection $this._connection` internally, so it is not faster than Tier 6 -- it adds a Logger.WriteTrace() call on top.

The benefit is clean OOP syntax and lifecycle management (IDisposable), not speed.  

### Tier 4 -- Direct private protocol function

> Note: `Set-FtdiGpioPins` is a private function. It is not accessible from
> user scripts. This tier is documented for contributors modifying module internals.

```powershell
$conn = Connect-PsGadgetFtdi -Index 0
# Inside module source only -- private function, not available in user scripts
Set-FtdiGpioPins -DeviceHandle $conn -Pins @(2) -Direction HIGH
$conn.Close()
```

Saves one PowerShell function call and its full parameter binding compared to
Tier 6. `Set-FtdiGpioPins` still does a read-modify-write (one USB read + one
USB write) to preserve unrelated pin states. If you own the full ACBUS byte
yourself, use Tier 3 instead.

### Tier 3 -- Direct MPSSE command, caller-managed state

> Note: `Send-MpsseAcbusCommand` is a private function. It is not accessible
> from user scripts. This tier is documented for contributors modifying module internals.

```powershell
$conn = Connect-PsGadgetFtdi -Index 0
[byte]$acbusState = 0x00   # track state yourself -- no USB read needed
[byte]$dirMask    = 0xFF   # all outputs

# Toggle pin 2 HIGH
$acbusState = $acbusState -bor 0x04
Send-MpsseAcbusCommand -DeviceHandle $conn -Value $acbusState -DirectionMask $dirMask

# Toggle pin 2 LOW
$acbusState = $acbusState -band 0xFB
Send-MpsseAcbusCommand -DeviceHandle $conn -Value $acbusState -DirectionMask $dirMask

$conn.Close()
```

Eliminates the USB read entirely. The ACBUS state is maintained in a PS variable. Each call is one PowerShell function call + one `rawFtdi.Write(3 bytes)`.

### Tier 2 -- Batched MPSSE buffer

```powershell
$ftdi = $dev._connection.Device   # raw FTD2XX_NET.FTDI object

# Build a byte array with N MPSSE ACBUS commands -- all sent in one USB transaction
# Each command is 3 bytes: 0x82, value, direction
[byte[]]$seq = @(
    0x82, 0x04, 0xFF,   # ACBUS2 HIGH  (step 1)
    0x82, 0x00, 0xFF,   # ACBUS2 LOW   (step 2)
    0x82, 0x04, 0xFF,   # ACBUS2 HIGH  (step 3)
    0x82, 0x00, 0xFF    # ACBUS2 LOW   (step 4)
)

[uint32]$w = 0
$ftdi.Write($seq, $seq.Length, [ref]$w) | Out-Null
```

The entire sequence is delivered to the FTDI chip in a single USB bulk transfer. The chip executes each ACBUS command back-to-back at its own internal rate. This is the highest throughput achievable for GPIO state changes from PowerShell because the USB transaction overhead is paid only once.

Pre-compute your sequences before the loop. Do not build the byte array inside the loop -- array allocation in PS is the bottleneck at that point.

### Tier 1 -- Raw .NET call, single command

```powershell
$ftdi = $dev._connection.Device   # FTD2XX_NET.FTDI
[uint32]$w = 0
$ftdi.Write([byte[]](0x82, 0x04, 0xFF), 3, [ref]$w) | Out-Null   # ACBUS2 HIGH
```

One direct .NET method call. No PowerShell function overhead. This is the
minimum achievable from a PS script for a single command. Combine with
pre-allocated buffers (Tier 2) to amortize USB round-trip latency across
multiple transitions.

### Tier 0 -- MPSSE hardware protocols (I2C, SPI, JTAG)

The FTDI MPSSE engine handles clock generation and bus timing autonomously in silicon. Once you configure the engine and send a payload, the chip clocks the bits out at hardware speed independent of PowerShell execution.

For I2C and SPI the bottleneck is the USB transfer of the payload, not PS call overhead. Use `Send-PsGadgetI2CWrite` or `Invoke-PsGadgetI2CScan` for standard I2C operations -- the protocol timing is handled entirely in chip silicon.

```powershell
$dev = New-PsGadgetFtdi -Index 0
Set-PsGadgetFtdiMode -PsGadget $dev -Mode MpsseI2c

# PS sends the payload byte array once via USB.
# The MPSSE engine generates START, address, ACK, data bytes, and STOP
# entirely in hardware at the configured SCL frequency.
# No PS loop is involved in the bus timing.
Send-PsGadgetI2CWrite -PsGadget $dev -Address 0x40 -Data @(0x00, 0x10)

$dev.Close()
```

The `Set-PsGadgetFtdiMode -Mode MpsseI2c` call sends the MPSSE initialisation sequence once (clock divisor, disable clock-divide-by-5, disable 3-phase clocking). After that, each `Send-PsGadgetI2CWrite` call transfers a single USB bulk packet; the chip handles every SCL edge autonomously. For a PCA9685 servo driver board this is the correct tier -- PS sends a 2-4 byte register write and the board handles PWM generation in its own silicon.

---

### Timing reality on Windows

These are approximate round-trip times measured on Windows 10 with an FT232H
via FTD2XX_NET. They represent the minimum achievable in each tier:

| Operation | Approximate latency |
|-|-|
| Single USB bulk write (ftd2xx.dll) | ~0.5-1 ms (Windows USB frame timing) |
| `Send-MpsseAcbusCommand` (Tier 3) | ~1-2 ms |
| `Set-FtdiGpioPins` with USB read (Tier 4) | ~2-4 ms first call (two USB transfers); ~1-2 ms subsequent calls (cached read) |
| `Set-PsGadgetGpio -Connection` (Tier 6) | ~3-6 ms |
| `Set-PsGadgetGpio -Index` (Tier 7) | ~15-60 ms (enumerate + open + close) |

**Windows USB frame timing (1 ms) is the floor for any single USB transaction.**

This means software PWM from PowerShell is limited to approximately 500 Hz maximum, and only if you use Tier 1/2 (raw .NET + batched buffers) and accept that the duty cycle will have jitter driven by Windows thread scheduling (~1-5 ms).

For servo control (50 Hz, 1-2 ms pulse): achievable with Tier 2 (batched buffer), but jitter will be visible on a scope. For precision servo positioning use a dedicated servo driver board (PCA9685 over I2C) -- the MPSSE engine handles I2C timing; PS only sends the register write.

For stepper motors at moderate speed (< 200 steps/second): Tier 3 or Tier 4 is sufficient. For microstepping at high speed, pre-compute the full step sequence as a batched byte array (Tier 2) and send in one `Write()` call.

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
