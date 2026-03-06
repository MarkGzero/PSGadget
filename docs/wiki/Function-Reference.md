# PSGadget Function Reference

Complete reference for every function exported by PSGadget. Functions are grouped
by category. Use `Get-Help <FunctionName>` for inline PowerShell help.

---

## Contents

- [Discovery](#discovery)
  - [List-PsGadgetFtdi](#list-psgadgetftdi)
  - [List-PsGadgetMpy](#list-psgadgetmpy)
- [Connection](#connection)
  - [New-PsGadgetFtdi](#new-psgadgetftdi)
  - [Connect-PsGadgetFtdi](#connect-psgadgetftdi)
  - [Connect-PsGadgetMpy](#connect-psgadgetmpy)
  - [Connect-PsGadgetSsd1306](#connect-psgadgetssd1306)
- [GPIO](#gpio)
  - [Set-PsGadgetGpio](#set-psgadgetgpio)
  - [Set-PsGadgetFtdiMode](#set-psgadgetftdimode)
  - [Set-PsGadgetFt232rCbusMode](#set-psgadgetft232rcbusmode)
- [EEPROM](#eeprom)
  - [Get-PsGadgetFtdiEeprom](#get-psgadgetftdieeprom)
- [SSD1306 Display](#ssd1306-display)
  - [Write-PsGadgetSsd1306](#write-psgadgetssd1306)
  - [Clear-PsGadgetSsd1306](#clear-psgadgetssd1306)
  - [Set-PsGadgetSsd1306Cursor](#set-psgadgetssd1306cursor)
- [Configuration](#configuration)
  - [Get-PsGadgetConfig](#get-psgadgetconfig)
  - [Set-PsGadgetConfig](#set-psgadgetconfig)
- [Diagnostics](#diagnostics)
  - [Test-PsGadgetEnvironment](#test-psgadgetenvironment)

---

## Discovery

### List-PsGadgetFtdi

Enumerates all FTDI devices visible to the D2XX driver.

**Parameters**: none

**Returns**: array of device objects

| Output property | Type | Description |
|-----------------|------|-------------|
| Index | int | Zero-based device index |
| Description | string | USB device description string |
| SerialNumber | string | FTDI serial number |
| LocationId | int | USB hub+port address (stable per physical port) |
| Type | string | Chip type: FT232H, FT232R, etc. |
| GpioMethod | string | MPSSE or CBUS |
| HasMpsse | bool | True if MPSSE engine is present |
| Driver | string | ftd2xx.dll (D2XX) or ftdibus.sys (VCP) |
| IsOpen | bool | True if another process has the device open |

**Notes**:  
On Windows with both VCP and D2XX drivers installed, each physical device appears
twice -- once with `Driver = ftd2xx.dll` (use for PSGadget) and once as
`ftdibus.sys` (VCP / COM port). The D2XX entry has the base serial number; the VCP
entry appends "A".

```powershell
List-PsGadgetFtdi | Format-Table

# Find only D2XX-accessible devices
List-PsGadgetFtdi | Where-Object Driver -eq "ftd2xx.dll" | Format-Table Index, SerialNumber, LocationId
```

---

### List-PsGadgetMpy

Enumerates serial ports likely connected to MicroPython devices.

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Detailed` | switch | No | Include port metadata (baud, parity, etc.) |

**Returns**: array of port name strings, or objects when `-Detailed`

```powershell
List-PsGadgetMpy

# With port metadata
List-PsGadgetMpy -Detailed | Format-Table
```

---

## Connection

### New-PsGadgetFtdi

Creates and connects a `PsGadgetFtdi` object in one step. Use this instead of
`[PsGadgetFtdi]::new()` because module classes are not visible in the caller's
type scope. The returned object is already open -- no `.Connect()` call needed.

**Parameter sets**: BySerial (default) | ByIndex | ByLocation

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-SerialNumber` | string | BySerial | FTDI serial number (e.g. "BG01X3GX") |
| `-Index` | int (0-127) | ByIndex | Zero-based device index |
| `-LocationId` | string | ByLocation | USB hub+port address from `List-PsGadgetFtdi` |

**Returns**: `PsGadgetFtdi` object

**`PsGadgetFtdi` methods**:

| Method | Description |
|--------|-------------|
| `.Connect()` | Open the hardware connection (idempotent; not needed after `New-PsGadgetFtdi`) |
| `.Close()` | Close the connection |
| `.SetPin(int pin, string state)` | Set one pin: state = HIGH / LOW / H / L / 1 / 0 |
| `.SetPin(int pin, bool high)` | Set one pin via boolean |
| `.SetPins(int[] pins, string state)` | Set multiple pins simultaneously |
| `.SetPins(int[] pins, bool high)` | Set multiple pins via boolean |
| `.PulsePin(int pin, string state, int ms)` | Hold state for ms, then invert |
| `.Write(byte[] data)` | Write raw bytes to the device |
| `.Read(int count)` | Read raw bytes from the device |

**`PsGadgetFtdi` properties**: `Type`, `GpioMethod`, `SerialNumber`, `LocationId`, `IsOpen`

```powershell
# Preferred: stable regardless of USB port
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"   # connected immediately
$dev.SetPin(0, "HIGH")
$dev.SetPins(@(0, 1), "LOW")
$dev.PulsePin(0, "HIGH", 500)   # 500 ms pulse
$dev.Close()

# By index
$dev = New-PsGadgetFtdi -Index 0

# By USB port location (stable for fixed-wiring rigs)
$dev = New-PsGadgetFtdi -LocationId 197634
```

---

### Connect-PsGadgetFtdi

Opens a raw device connection and returns a low-level connection object.
Use `New-PsGadgetFtdi` instead for scripted GPIO work.
`Connect-PsGadgetFtdi` is useful when you need the raw connection for
`Set-PsGadgetGpio -Connection` or `Connect-PsGadgetSsd1306 -FtdiDevice`.

**Parameter sets**: ByIndex (default) | BySerial | ByLocation

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Index` | int | ByIndex | Zero-based device index |
| `-SerialNumber` | string | BySerial | FTDI serial number |
| `-LocationId` | string | ByLocation | USB hub+port address |

**Returns**: platform-specific connection object (`System.Object`)

```powershell
$conn = Connect-PsGadgetFtdi -Index 0
Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH
$conn.Close()

# Feed directly into SSD1306 init
$ftdi    = Connect-PsGadgetFtdi -Index 0
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi
```

---

### Connect-PsGadgetMpy

Creates a `PsGadgetMpy` object for a MicroPython serial port.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-SerialPort` | string | Yes | Serial port name: `/dev/ttyUSB0`, `COM3`, etc. |

**Returns**: `PsGadgetMpy` object

**`PsGadgetMpy` methods**:

| Method | Description |
|--------|-------------|
| `.Invoke(string code)` | Execute a Python expression; returns stdout |
| `.GetInfo()` | Return MicroPython version and platform info |

```powershell
$mpy = Connect-PsGadgetMpy -SerialPort "/dev/ttyUSB0"
$mpy.Invoke("import sys; print(sys.version)")
$mpy.GetInfo()
```

---

### Connect-PsGadgetSsd1306

Initializes an SSD1306 OLED display connected to an FT232H via I2C.

**Parameter sets**: ByConnection (default) | PsGadget

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-FtdiDevice` | System.Object | ByConnection | Connection object from `Connect-PsGadgetFtdi` |
| `-PsGadget` | PsGadgetFtdi | PsGadget | Object from `New-PsGadgetFtdi` |
| `-Address` | byte (0x08-0x77) | No | I2C address. Default: `0x3C` |
| `-Force` | switch | No | Re-initialize even if already connected |

**Returns**: `PsGadgetSsd1306` object, or `$null` on failure

```powershell
$ftdi    = Connect-PsGadgetFtdi -Index 0
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi

# Module with ADDR pin pulled high
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi -Address 0x3D
```

---

## GPIO

### Set-PsGadgetGpio

Sets one or more GPIO pins HIGH or LOW. Automatically dispatches to the correct
backend based on the device's `GpioMethod` (MPSSE or CBUS).

**Parameter sets**: ByIndex (default) | BySerial | ByConnection

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Index` | int | ByIndex | Zero-based device index |
| `-SerialNumber` | string | BySerial | FTDI serial number |
| `-Connection` | object | ByConnection | Open connection from `Connect-PsGadgetFtdi` |
| `-Pins` | int[] | Yes (all sets) | Pin numbers. FT232H: 0-7 (ACBUS). FT232R: 0-3 (CBUS) |
| `-State` | string | Yes (all sets) | HIGH / H / 1 or LOW / L / 0 |
| `-DurationMs` | int | No | Hold the state for this many milliseconds, then release |

**Pin numbering**:

| `Pins` value | FT232H signal | FT232R signal |
|--------------|---------------|---------------|
| 0 | ACBUS0 | CBUS0 |
| 1 | ACBUS1 | CBUS1 |
| 2 | ACBUS2 | CBUS2 |
| 3 | ACBUS3 | CBUS3 |
| 4-7 | ACBUS4-7 (FT232H only) | Error on FT232R |

```powershell
# Set two pins HIGH by index
Set-PsGadgetGpio -Index 0 -Pins @(0, 1) -State HIGH

# Pulse LOW for 200 ms
Set-PsGadgetGpio -SerialNumber "FT4ABCDE" -Pins @(2) -State LOW -DurationMs 200

# Reuse a connection across multiple calls
$conn = Connect-PsGadgetFtdi -SerialNumber "BG01X3GX"
Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH
Set-PsGadgetGpio -Connection $conn -Pins @(1) -State HIGH
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW
$conn.Close()
```

> **FT232R note**: CBUS pins must be in FT_CBUS_IOMODE before this function
> will work. Run `Set-PsGadgetFt232rCbusMode` once per device first.

---

### Set-PsGadgetFtdiMode

Switches an FTDI device between operating modes. Dispatches to the correct
backend automatically based on the device type.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-PsGadget` | PsGadgetFtdi | Yes | Object from `New-PsGadgetFtdi` |
| `-Mode` | string | Yes | MPSSE, CBUS, AsyncBitBang, SyncBitBang, or UART |
| `-Mask` | byte | No | Direction mask for bit-bang modes (1=output). Default: `0xFF` |
| `-Pins` | int[] | No | CBUS pins to configure when Mode=CBUS. Default: `@(0,1,2,3)` |

**Mode summary**:

| Mode | Applies to | Effect |
|------|-----------|--------|
| MPSSE | FT232H, FT2232H, FT4232H | Enable MPSSE for SPI/I2C/JTAG/ACBUS GPIO |
| CBUS | FT232R | Write EEPROM for CBUS GPIO (requires USB replug) |
| AsyncBitBang | Most FTDI chips | Async bit-bang on ADBUS pins, no EEPROM needed |
| SyncBitBang | FT2232C, FT232R, FT245R | Sync bit-bang on ADBUS pins |
| UART | All | Reset to default serial/UART mode |

```powershell
$dev = New-PsGadgetFtdi -Index 0

# Set MPSSE mode (FT232H)
Set-PsGadgetFtdiMode -PsGadget $dev -Mode MPSSE

# Enable CBUS GPIO on FT232R (writes EEPROM, then prompt to replug)
Set-PsGadgetFtdiMode -PsGadget $dev -Mode CBUS

# Async bit-bang on ADBUS with custom direction mask
$r = New-PsGadgetFtdi -Index 1   # connected immediately
Set-PsGadgetFtdiMode -PsGadget $r -Mode AsyncBitBang -Mask 0x0F  # lower nibble = output

# Return to UART / serial mode
Set-PsGadgetFtdiMode -PsGadget $dev -Mode UART
```

---

### Set-PsGadgetFt232rCbusMode

Programs the FT232R EEPROM to assign CBUS pins to GPIO mode (or any other
`FT_CBUS_OPTIONS` function). **One-time per physical device.**

After writing, the function prompts to cycle the USB port automatically.
Accepting is equivalent to physically unplugging and replugging.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Index` | int | ByIndex | Zero-based device index (D2XX entry only) |
| `-SerialNumber` | string | BySerial | FTDI serial number |
| `-PsGadget` | PsGadgetFtdi | PsGadget | Object from `New-PsGadgetFtdi` |
| `-Pins` | int[] | No | CBUS pins to reconfigure. Default: `@(0,1,2,3)` |
| `-Mode` | string | No | CBUS function. Default: `FT_CBUS_IOMODE` |
| `-WhatIf` | switch | No | Preview the EEPROM change without writing |
| `-HighDriveIOs` | bool | No | Override config `ftdi.highDriveIOs` for this call |
| `-PullDownEnable` | bool | No | Override config `ftdi.pullDownEnable` for this call |
| `-RIsD2XX` | bool | No | Override config `ftdi.rIsD2XX` for this call |

**Available `-Mode` values**:

| Mode | Function |
|------|----------|
| `FT_CBUS_IOMODE` | GPIO / bit-bang **(default)** |
| `FT_CBUS_TXLED` | Pulses on Tx data |
| `FT_CBUS_RXLED` | Pulses on Rx data |
| `FT_CBUS_TXRXLED` | Pulses on Tx or Rx data |
| `FT_CBUS_PWREN` | Power-on signal (PWREN#, active low) |
| `FT_CBUS_SLEEP` | Sleep indicator |
| `FT_CBUS_CLK48` | 48 MHz clock output |
| `FT_CBUS_CLK24` | 24 MHz clock output |
| `FT_CBUS_CLK12` | 12 MHz clock output |
| `FT_CBUS_CLK6` | 6 MHz clock output |
| `FT_CBUS_TXDEN` | Tx Data Enable |
| `FT_CBUS_BITBANG_WR` | Bit-bang write strobe |
| `FT_CBUS_BITBANG_RD` | Bit-bang read strobe |

```powershell
# Configure all four pins as GPIO (most common)
Set-PsGadgetFt232rCbusMode -Index 0

# Preview without writing
Set-PsGadgetFt232rCbusMode -Index 0 -WhatIf

# Configure only CBUS0 and CBUS1
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0, 1)

# Set CBUS0 to Rx LED indicator
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0) -Mode FT_CBUS_RXLED

# Enable 8 mA drive for this write only
Set-PsGadgetFt232rCbusMode -Index 0 -HighDriveIOs $true

# Use serial number
Set-PsGadgetFt232rCbusMode -SerialNumber "BG01X3GX"
```

> **CBUS4 note**: CBUS4 can be assigned an EEPROM function but cannot be driven
> at runtime via `Set-PsGadgetGpio`. Only CBUS0-3 support bit-bang.

---

## EEPROM

### Get-PsGadgetFtdiEeprom

Reads and returns the EEPROM contents of an FT232R or compatible FTDI device.
Useful for inspecting current CBUS mode assignments before or after programming.

**Parameter sets**: ByIndex (default) | BySerial | PsGadget

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Index` | int | ByIndex | Zero-based device index |
| `-SerialNumber` | string | BySerial | FTDI serial number |
| `-PsGadget` | PsGadgetFtdi | PsGadget | Object from `New-PsGadgetFtdi` |

**Returns**: EEPROM data object with properties including `Cbus0`, `Cbus1`, `Cbus2`,
`Cbus3`, `Cbus4`, `HighDriveIOs`, `PullDownEnable`, `RIsD2XX`, and more.

```powershell
# Check CBUS mode after programming
Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# Full dump
Get-PsGadgetFtdiEeprom -Index 0 | Format-List

# Using serial number
Get-PsGadgetFtdiEeprom -SerialNumber "BG01X3GX" | Select-Object Cbus0, Cbus1, Cbus2, Cbus3
```

Expected output after `Set-PsGadgetFt232rCbusMode` with defaults:

```
Cbus0          Cbus1          Cbus2          Cbus3
-----          -----          -----          -----
FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE
```

---

## SSD1306 Display

The SSD1306 is a 128x64 monochrome OLED. PSGadget drives it over I2C using the
FT232H MPSSE engine. No third-party display library is required.

**Display layout**: 8 pages (rows), each 8 pixels tall. The built-in 6x8 font
gives approximately 21 characters per page at normal size.

**Hardware wiring**:

| FT232H pin | SSD1306 pin |
|------------|-------------|
| ADBUS0 (TCK/SCK) | SCL |
| ADBUS1 (TDI/DO) | SDA |
| 3.3V | VCC |
| GND | GND |

---

### Write-PsGadgetSsd1306

Writes text to a specific page of the SSD1306 display.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Display` | System.Object | Yes | Display object from `Connect-PsGadgetSsd1306` |
| `-Text` | string | Yes | Text to display |
| `-Page` | int (0-7) | Yes | Target page (row) |
| `-Align` | string | No | left (default), center, or right |
| `-FontSize` | int | No | 1 (default, 6x8) or 2 (doubled width) |
| `-Invert` | switch | No | Dark text on white background instead of white on dark |

**Returns**: `[bool]` - `$true` on success

```powershell
Write-PsGadgetSsd1306 -Display $display -Text "Hello World" -Page 0
Write-PsGadgetSsd1306 -Display $display -Text "Centered"   -Page 2 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "Right"      -Page 4 -Align right
Write-PsGadgetSsd1306 -Display $display -Text "BIG"        -Page 0 -FontSize 2 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "ALARM"      -Page 6 -Invert
```

---

### Clear-PsGadgetSsd1306

Clears the entire display or a single page.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Display` | System.Object | Yes | Display object from `Connect-PsGadgetSsd1306` |
| `-Page` | int (0-7) | No | Clear only this page. Omit to clear all 8 pages. |

**Returns**: `[bool]` - `$true` on success

```powershell
# Clear full display
Clear-PsGadgetSsd1306 -Display $display

# Clear page 3 only
Clear-PsGadgetSsd1306 -Display $display -Page 3
```

---

### Set-PsGadgetSsd1306Cursor

Moves the internal cursor to an exact column and page position for raw byte
writes or precise text placement.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Display` | System.Object | Yes | Display object from `Connect-PsGadgetSsd1306` |
| `-Column` | int (0-127) | Yes | Pixel column |
| `-Page` | int (0-7) | Yes | Page (row) number |

```powershell
Set-PsGadgetSsd1306Cursor -Display $display -Column 32 -Page 3
```

---

## Configuration

### Get-PsGadgetConfig

Returns the current in-memory PSGadget configuration loaded from
`~/.psgadget/config.json`. Always fully populated from built-in defaults even
if the file only contains a subset of keys.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Section` | string | No | Return only this section: ftdi or logging |

**Returns**: `PSCustomObject`

```powershell
# Full config
Get-PsGadgetConfig

# Readable output
Get-PsGadgetConfig | Format-List

# FTDI section only
Get-PsGadgetConfig -Section ftdi

# Single value
(Get-PsGadgetConfig).ftdi.highDriveIOs
```

---

### Set-PsGadgetConfig

Updates a single configuration key and persists the change to
`~/.psgadget/config.json`. Takes effect immediately in the current session.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Key` | string | Yes | Dot-path key: `ftdi.highDriveIOs`, `logging.level`, etc. |
| `-Value` | object | Yes | New value. PowerShell type-coerces bool and int automatically. |

**Valid keys**:

| Key | Type | Description |
|-----|------|-------------|
| `ftdi.highDriveIOs` | bool | 8 mA drive strength (default: false = 4 mA) |
| `ftdi.pullDownEnable` | bool | Weak pull-downs during USB suspend (default: false) |
| `ftdi.rIsD2XX` | bool | D2XX-only enumeration, no VCP duplicate (default: false) |
| `logging.level` | string | INFO, DEBUG, TRACE, or ERROR (default: INFO) |
| `logging.maxFileSizeMb` | int | Log file rotation threshold in MB (default: 10) |
| `logging.retainDays` | int | Log files older than this are deleted (default: 30) |

```powershell
Set-PsGadgetConfig -Key ftdi.highDriveIOs  -Value $true
Set-PsGadgetConfig -Key ftdi.rIsD2XX       -Value $true
Set-PsGadgetConfig -Key logging.level      -Value DEBUG
Set-PsGadgetConfig -Key logging.retainDays -Value 7
```

See [Configuration](Configuration.md) for a full description of each key's
effects and when to change them.

---

## Diagnostics

### Test-PsGadgetEnvironment

Verifies whether the current environment is ready for PSGadget hardware use.
Checks PowerShell version, backend selection, native library presence, device
enumeration, and configuration file. Returns a structured object.

**Alias**: `Test-PsGadgetSetup`

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Verbose` | switch | No | Emit detailed per-item check output |

**Returns**: `[PSCustomObject]`

| Property | Type | Description |
|----------|------|-------------|
| Status | string | `OK` or `NOT READY` |
| Reason | string | First failing check, or `All checks passed` |
| NextStep | string | Actionable guidance if not ready; empty when OK |
| Platform | string | OS / PS version / .NET version |
| Backend | string | IoT, D2XX, or Stub |
| BackendReady | bool | True if the selected backend loaded successfully |
| NativeLibOk | bool | True if the platform native library is present |
| NativeLibPath | string | Full path checked |
| Devices | string[] | Formatted device list from List-PsGadgetFtdi |
| DeviceCount | int | Number of enumerated devices |
| ConfigPresent | bool | True if ~/.psgadget/config.json exists |
| IsReady | bool | True if all checks passed |

```powershell
# Quick check
Test-PsGadgetEnvironment

# Verbose -- shows each check result inline
Test-PsGadgetEnvironment -Verbose

# Scripted use — stop pipeline on failure
$env = Test-PsGadgetEnvironment
if (-not $env.IsReady) {
    Write-Warning $env.Reason
    Write-Warning $env.NextStep
    return
}

# Old name still works (backward-compat alias)
Test-PsGadgetSetup
```

---

## Quick Reference Table

| Function | Short Description |
|----------|-------------------|
| `List-PsGadgetFtdi` | Enumerate FTDI devices |
| `List-PsGadgetMpy` | Enumerate MicroPython serial ports |
| `New-PsGadgetFtdi` | Create PsGadgetFtdi object (OOP entry point) |
| `Connect-PsGadgetFtdi` | Open raw FTDI connection |
| `Connect-PsGadgetMpy` | Open MicroPython REPL connection |
| `Connect-PsGadgetSsd1306` | Initialize SSD1306 OLED over I2C |
| `Set-PsGadgetGpio` | Set GPIO pins HIGH or LOW |
| `Set-PsGadgetFtdiMode` | Switch device operating mode |
| `Set-PsGadgetFt232rCbusMode` | Program FT232R CBUS pins (one-time EEPROM) |
| `Get-PsGadgetFtdiEeprom` | Read FTDI device EEPROM |
| `Write-PsGadgetSsd1306` | Write text to OLED display |
| `Clear-PsGadgetSsd1306` | Clear display or single page |
| `Set-PsGadgetSsd1306Cursor` | Set OLED cursor position |
| `Get-PsGadgetConfig` | Read user configuration |
| `Set-PsGadgetConfig` | Write user configuration |
| `Test-PsGadgetEnvironment` | Verify environment readiness; returns Status/Reason/NextStep |
