# PSGadget Workflow Reference

This file documents end-to-end usage workflows for each supported FTDI device type.
It is maintained alongside the codebase and updated whenever new device support or
public functions are added.

---

## Table of Contents

- [Module Setup](#module-setup)
- [FT232H Workflow (MPSSE - ACBUS0-7)](#ft232h-workflow-mpsse---acbus0-7)
- [FT232R Workflow (CBUS bit-bang - CBUS0-3)](#ft232r-workflow-cbus-bit-bang---cbus0-3)
- [Stepper Motor Workflow (Async Bit-Bang, FT232R or FT232H)](#stepper-motor-workflow-async-bit-bang-ft232r-or-ft232h)
- [SSD1306 OLED Display (FT232H via MPSSE I2C)](#ssd1306-oled-display-ft232h-via-mpsse-i2c)
- [SPI Workflow (FT232H via MPSSE)](#spi-workflow-ft232h-via-mpsse)
- [UART Workflow (FT232H and FT232R)](#uart-workflow-ft232h-and-ft232r)
- [ESP-NOW Wireless Telemetry (MicroPython + FT232H UART)](#esp-now-wireless-telemetry-micropython--ft232h-uart)
- [Device Capability Comparison](#device-capability-comparison)
- [Available CBUS Mode Options (FT232R)](#available-cbus-mode-options-ft232r)
- [OOP Class Interface](#oop-class-interface)
- [Public Function Quick Reference](#public-function-quick-reference)
- [Maintenance Notes](#maintenance-notes)

---

## Module Setup

```powershell
# Load module for the current session
Import-Module ./PSGadget.psd1 -Force

# Enumerate all connected FTDI devices
Get-FtdiDevice | Format-Table

# Example output (Windows):
# Index  Description          SerialNumber  LocationId  Type    GpioMethod  HasMpsse
# -----  -----------          ------------  ----------  ----    ----------  --------
#   0    USB Serial Converter FT4ABCDE      197634      FT232H  MPSSE       True
#   1    USB Serial Adapter   FT1XYZAB      197635      FT232R  CBUS        False

# Example output (Linux, after rmmod ftdi_sio):
# Index  Type    Description       SerialNumber  LocationId      IsVcp
# -----  ----    -----------       ------------  ----------      -----
#   0    FT232R  FT232R USB UART   BG01B0I1      usb-bus1-dev4   False
```

**Linux note**: On Linux, `ftdi_sio` (VCP kernel module) claims FTDI devices
automatically. Unload it before using GPIO:
```bash
sudo rmmod ftdi_sio
```
Devices claimed by `ftdi_sio` show as `IsVcp=True` and are hidden from
`Get-FtdiDevice` by default. Use `-ShowVCP` to see them, or unload the
driver to make them accessible. See [Getting Started - Linux Setup](../docs/wiki/Getting-Started.md#linux-setup)
for full setup including `libftd2xx.so` installation.

---

## FT232H Workflow (MPSSE - ACBUS0-7)

The FT232H has a built-in MPSSE engine. GPIO is available immediately on
ACBUS0-7 (physical pins 21-31). No EEPROM programming is required.

> **VCP driver conflict**: If `Get-FtdiDevice -ShowVCP` shows your FT232H device
> TWICE (once as D2XX and once as a COM port), the EEPROM `IsVCP` flag is set. This
> prevents MPSSE from gaining exclusive control and GPIO/servo operations will silently
> fail. Fix it with `Set-PsGadgetFtdiEeprom -Index 0 -DisableVcp` then replug the cable.
> Verify with `Get-PsGadgetFtdiEeprom -Index 0` and confirm `IsVCP : False`.

### Pin Map

| Param `Pins` value | ACBUS signal | Physical pin (FT232H) |
|--------------------|--------------|----------------------|
| 0                  | ACBUS0       | 21                   |
| 1                  | ACBUS1       | 25                   |
| 2                  | ACBUS2       | 26                   |
| 3                  | ACBUS3       | 27                   |
| 4                  | ACBUS4       | 28                   |
| 5                  | ACBUS5       | 29                   |
| 6                  | ACBUS6       | 30                   |
| 7                  | ACBUS7       | 31                   |

### Commands

```powershell
# Confirm FT232H is at index 0 with GpioMethod = MPSSE
Get-FtdiDevice | Format-Table

# Set ACBUS2 and ACBUS4 HIGH
Set-PsGadgetGpio -Index 0 -Pins @(2, 4) -State HIGH
# Pulse ACBUS0 LOW for 500 ms then restore
Set-PsGadgetGpio -Index 0 -Pins @(0) -State LOW -DurationMs 500

# Turn both off
Set-PsGadgetGpio -Index 0 -Pins @(2, 4) -State LOW

# Address by serial number instead of index
Set-PsGadgetGpio -SerialNumber "FT4ABCDE" -Pins @(2) -State HIGH
```

---

## FT232R Workflow (CBUS bit-bang - CBUS0-3)

The FT232R exposes four CBUS pins for GPIO. These pins default to LED / clock
functions in the factory EEPROM. They must be programmed to FT_CBUS_IOMODE
once per physical device before use (replaces the FTDI FT_PROG tool).

After EEPROM programming, runtime GPIO uses the same `Set-PsGadgetGpio` API
as the FT232H -- the dispatch is automatic based on the device's GpioMethod.

### Pin Map

| Param `Pins` value | CBUS signal | Notes                |
|--------------------|-------------|----------------------|
| 0                  | CBUS0       |                      |
| 1                  | CBUS1       |                      |
| 2                  | CBUS2       |                      |
| 3                  | CBUS3       |                      |
| 4                  | CBUS4       | EEPROM-configurable only (Set-PsGadgetFt232rCbusMode); cannot be driven at runtime via Set-PsGadgetGpio |
| 5-7                | (invalid)   | Error thrown         |

### Step 1 - Identify D2XX-Enabled Device

**How FTDI Dual Driver Enumeration Works:**
When both VCP and D2XX drivers are installed (standard Windows setup), Windows loads two drivers per physical FTDI device. `Get-FtdiDevice` shows only the D2XX-accessible entry by default:

```powershell
Get-FtdiDevice | Format-Table Index, Type, Driver, SerialNumber, LocationId

# Example output (one physical FT232R device):
# Index Type   Driver     SerialNumber LocationId
# ----- ----   ------     ------------ ----------
#   0   FT232R ftd2xx.dll BG01X3GX     197634
```

To see VCP entries as well (e.g. to find the COM port number for serial terminal use):
```powershell
Get-FtdiDevice -ShowVCP | Format-Table Index, Type, Driver, SerialNumber, LocationId, ComPort

# Example output with -ShowVCP:
# Index Type   Driver              SerialNumber LocationId ComPort
# ----- ----   ------              ------------ ---------- -------
#   0   FT232R ftd2xx.dll          BG01X3GX     197634            # <- Use this for PSGadget
#   1   FT232R ftdibus.sys (VCP)   BG01X3GXA    0          COM3    # <- Same device, VCP view
```

**Key observations:**
- **Same physical device** = D2XX entry (no "A" suffix) + VCP entry ("A" suffix)
- **D2XX entry**: Shown by default — use this index for PsGadget EEPROM/GPIO functions
- **VCP entry**: Hidden by default — shown with `-ShowVCP`; use for serial terminal applications
- **LocationId**: USB hub+port address — stable for a fixed physical port, even after re-plug
- **No driver switching needed** - Both modes coexist!

**Find your D2XX-enabled device:**
```powershell
# Default output already shows only D2XX devices
Get-FtdiDevice | Format-Table Index, SerialNumber, LocationId
```

### Step 2 - Inspect current EEPROM (optional, recommended first time)

**On Windows** (uses FTD2XX_NET):

```powershell
# Use the Index with ftd2xx.dll driver from Step 1
$ee = Get-PsGadgetFtdiEeprom -Index 0
$ee | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# Factory defaults will show something like:
# Cbus0          Cbus1          Cbus2         Cbus3
# -----          -----          -----         -----
# FT_CBUS_TXLED  FT_CBUS_RXLED  FT_CBUS_PWRON FT_CBUS_SLEEP
```

**On Linux/macOS** (uses native P/Invoke -- requires libftd2xx.so):

```powershell
# Call via module scope (Get-FtdiNativeCbusEepromInfo is a private function)
& (Get-Module PSGadget) { Get-FtdiNativeCbusEepromInfo -Index 0 }

# After EEPROM programming:
# Cbus0          Cbus1          Cbus2         Cbus3
# -----          -----          -----         -----
# FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE
```

### Step 3 - Program EEPROM for GPIO (one time per device)

```powershell
# Configure all four bit-bangable CBUS pins as GPIO (default and most common):
# Use the Index with ftd2xx.dll driver from Step 1
Set-PsGadgetFt232rCbusMode -Index 0

# Preview the change without writing:
Set-PsGadgetFt232rCbusMode -Index 0 -WhatIf

# Configure only CBUS0 and CBUS1; leave CBUS2/3 at factory function:
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0, 1)

# Set a pin to a specific non-GPIO CBUS function:
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0) -Mode FT_CBUS_RXLED

# Configure CBUS4 to an EEPROM function (note: CBUS4 cannot be bit-banged at runtime):
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(4) -Mode FT_CBUS_PWRON
```

> **CBUS4 note**: The FT232R has 5 CBUS pins (CBUS0-4). Only CBUS0-3 can be driven at
> runtime via `Set-PsGadgetGpio`. CBUS4 can be assigned an EEPROM function above but the
> D2XX CBUS bit-bang mask (8 bits: 4 direction + 4 value) does not encode a 5th pin.

**IMPORTANT**: Replug the USB device after writing EEPROM. The new settings do not
take effect until the device re-enumerates.

### Step 4 - Verify after replug

```powershell
Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# Expected result after Set-PsGadgetFt232rCbusMode with defaults:
# Cbus0          Cbus1          Cbus2          Cbus3
# -----          -----          -----          -----
# FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE
```

### Step 5 - Runtime GPIO

```powershell
# Set CBUS0 and CBUS1 HIGH (use your D2XX-enabled index from Step 1)
Set-PsGadgetGpio -Index 0 -Pins @(0, 1) -State HIGH

# Pulse CBUS0 LOW for 200 ms
Set-PsGadgetGpio -Index 0 -Pins @(0) -State LOW -DurationMs 200

# Restore
Set-PsGadgetGpio -Index 0 -Pins @(0, 1) -State LOW

# Pins 4-7 will throw a clear error (CBUS bit-bang supports 0-3 only):
# Set-PsGadgetGpio -Index 0 -Pins @(4) -State HIGH
# ERROR: Pin(s) [4] are out of range for CBUS bit-bang. FT232R CBUS GPIO supports CBUS0-3 only.
```

---

### Troubleshooting FT232R Issues

**Error: "Failed to open device via OpenByIndex and OpenBySerialNumber: FT_DEVICE_NOT_FOUND"**

This typically means you're trying to use an index that corresponds to a VCP-mode device.
VCP devices no longer appear in `Get-FtdiDevice` by default so this should be rare.
If it occurs, verify your index against current output:
```powershell
# Default output shows only D2XX-accessible devices
Get-FtdiDevice | Format-Table Index, SerialNumber

# Use one of those Index values
Set-PsGadgetFt232rCbusMode -Index <D2XX_INDEX>
```

**Understanding Dual Enumeration:**
- `Get-FtdiDevice` shows D2XX devices only by default (PsGadget-compatible)
- Use `Get-FtdiDevice -ShowVCP` to see VCP entries and their COM port assignments
- **ftd2xx.dll entry**: Use for PSGadget EEPROM/GPIO functions
- **ftdibus.sys (VCP) entry**: Use for serial terminal applications
- **Serial number pattern**: Same base number, VCP adds "A" suffix

**Driver Installation Reference:**
If you see no `ftd2xx.dll` devices at all:
1. Download [FTDI CDM driver package](https://ftdichip.com/drivers/) 
2. Install both VCP and D2XX drivers (this enables dual enumeration)
3. Unplug/replug devices to re-enumerate

**Logic Analyzer Use:**
For sigrok/Pulseview, use [Zadig](https://zadig.akeo.ie/) to install WinUSB driver. Note: WinUSB blocks both PSGadget and serial terminal access.

See: https://markgzero.github.io/2025/11/09/ft232rnl-sigrok-pulseview-windows.html

---

## Stepper Motor Workflow (Async Bit-Bang, FT232R or FT232H)

Drive a 28BYJ-48 (or similar 4-wire unipolar stepper) via a ULN2003 driver
board using ADBUS0-3 pins in async bit-bang mode. Supported on both FT232R
and FT232H - no EEPROM programming required.

**Wiring**: connect ADBUS0-3 (D0-D3 on the breakout) to ULN2003 IN1-IN4.
ADBUS corresponds to the UART data lines in normal use (not CBUS).

**Calibration**: 28BYJ-48 is NOT exactly 4096 half-steps per revolution.
Empirical value: ~4075.77 half-steps/rev. Always use `-StepsPerRevolution`
or `$dev.StepsPerRevolution` rather than hardcoding 2048/4096.

### Pin Map (ADBUS - async bit-bang)

| ADBUS pin | Signal | ULN2003 input | Coil |
|-----------|--------|---------------|------|
| ADBUS0    | D0     | IN1           | A    |
| ADBUS1    | D1     | IN2           | A'   |
| ADBUS2    | D2     | IN3           | B    |
| ADBUS3    | D3     | IN4           | B'   |

### Commands

```powershell
# Enumerate devices - FT232R or FT232H work equally
Get-FtdiDevice | Format-Table Index, Type, SerialNumber, GpioMethod

# Step count (one-shot - auto opens and closes device)
Invoke-PsGadgetStepper -Index 0 -Steps 4076             # ~1 revolution
Invoke-PsGadgetStepper -Index 0 -Steps 2000 -DelayMs 3  # slower / higher torque

# Angle-based - uses default calibration (~4075.77 half-steps/rev)
Invoke-PsGadgetStepper -Index 0 -Degrees 90
Invoke-PsGadgetStepper -Index 0 -Degrees 180 -Direction Reverse

# Full-step mode (higher torque, ~2037.89 steps/rev default)
Invoke-PsGadgetStepper -Index 0 -Degrees 90 -StepMode Full

# Custom calibration (use your measured value)
Invoke-PsGadgetStepper -Index 0 -Degrees 360 -StepsPerRevolution 4082.5

# Stable device identification by serial number
Invoke-PsGadgetStepper -SerialNumber "FTAXBFCQ" -Steps 1000

# OOP interface - calibrate once, call many times
$dev = New-PsGadgetFtdi -Index 0
$dev.StepsPerRevolution = 4082.5   # measured value for this specific motor
$dev.Step(2000)                    # 2000 half-steps forward
$dev.Step(2000, 'Reverse')         # 2000 half-steps reverse
$dev.StepDegrees(90)               # ~90 degrees using calibrated SPR
$dev.StepDegrees(180, 'Reverse')   # 180 degrees reverse
$dev.Close()

# Return value inspection
$r = Invoke-PsGadgetStepper -Index 0 -Degrees 90
$r.Steps              # actual step count computed from calibration
$r.StepsPerRevolution # value used (default or supplied)
$r.Degrees            # degrees requested
```

---

## SSD1306 OLED Display (FT232H via MPSSE I2C)

The SSD1306 is a 128x64 monochrome OLED controller, commonly used on
0.96" and 1.3" I2C display modules. PSGadget drives it over I2C using
the FT232H MPSSE engine — no third-party library required.

### Hardware Wiring

| FT232H pin     | MPSSE signal | SSD1306 pin |
|----------------|--------------|-------------|
| ADBUS0         | TCK / SCK    | SCL         |
| ADBUS1         | TDI / DO     | SDA         |
| 3.3V           | Power        | VCC         |
| GND            | Ground       | GND         |

Most modules use I2C address **0x3C**. Modules with the ADDR pin pulled
high use **0x3D**.

### Display Layout

The 128x64 display is divided into 8 horizontal **pages** (rows), each
8 pixels tall. One character from the built-in 6x8 font occupies 6
pixels wide, giving ~21 characters per row at normal size.

| Page | Pixel rows | Typical use       |
|------|------------|-------------------|
| 0    | 0 - 7      | Header / title    |
| 1    | 8 - 15     | Status line 1     |
| 2    | 16 - 23   | Status line 2     |
| 3    | 24 - 31   | Status line 3     |
| 4    | 32 - 39   | Status line 4     |
| 5    | 40 - 47   | Status line 5     |
| 6    | 48 - 55   | Status line 6     |
| 7    | 56 - 63   | Footer            |

### Commands

```powershell
# 1. Connect FTDI device (must be FT232H with HasMpsse = True)
$ftdi = New-PsGadgetFtdi -Index 0

# 2. Clear entire display
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Clear

# Clear a single page (row)
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Clear -Page 2

# 3. Write text (single row, 6x8 font, ~21 chars)
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Text "Hello World" -Page 0
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Text "Centered"    -Page 2 -Align center
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Text "Right"       -Page 4 -Align right

# 4. Double-height text (spans page N and page N+1, requires page <= 6)
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Text "BIG" -Page 0 -Align center -FontSize 2

# 5. Inverted text (dark text on white background)
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Text "ALARM" -Page 6 -Align center -Invert

# 6. Draw sysadmin symbol (16x16 at pages 0-1; auto-falls to 8x8 at page 7)
#    Symbols: Warning, Alert, Checkmark, Error, Info, Lock, Unlock, Network
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Symbol Warning   -Page 0
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Symbol Checkmark -Page 0 -Column 20
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Symbol Error      -Page 7  # 8x8 (page 7)

# 7. Non-default I2C address (ADDR pin pulled high)
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -I2CAddress 0x3D -Text "Alt addr" -Page 0

# 8. Live status loop
Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Text "Live Clock" -Page 0 -Align center
for ($i = 0; $i -lt 60; $i++) {
    $time = Get-Date -Format "HH:mm:ss"
    Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Clear -Page 2
    Invoke-PsGadgetI2C -PsGadget $ftdi -I2CModule SSD1306 -Text $time -Page 2 -Align center -FontSize 2
    Start-Sleep -Seconds 1
}

# 9. Always close the FTDI device when done
$ftdi.Close()
```

> **See also**: [examples/Example-Ssd1306.md](Example-Ssd1306.md) for a
> complete multi-persona walkthrough with troubleshooting and Quick Reference.

---

## SPI Workflow (FT232H via MPSSE)

MPSSE SPI is available on the FT232H only. FT232R does not support MPSSE and
cannot be used for SPI. No EEPROM programming is required.

The MPSSE pins ADBUS0-2 are reserved for the SPI bus. Chip-select uses ADBUS3
by default and is configurable to ADBUS3-7 via `-CsPin`. SPI modes 0-3 are
supported via `-SpiMode`.

### Hardware Wiring

| FT232H pin        | MPSSE signal | SPI role        | Connect to              |
|-------------------|--------------|-----------------|-------------------------|
| ADBUS0 (D0)       | TCK/SCK      | SPI clock       | SCK on SPI device       |
| ADBUS1 (D1)       | TDI          | MOSI            | MOSI / SDI on device    |
| ADBUS2 (D2)       | TDO          | MISO            | MISO / SDO on device    |
| ADBUS3 (D3)       | GPIOL0       | Chip select (CS)| CS / nSS on device      |
| 3.3V or 5V        | Power        | VCC             | VCC on device           |
| GND               | Ground       | GND             | GND on device           |

Add a 10k pull-up resistor between D3 (CS) and VCC to keep CS inactive when idle.

### Commands

```powershell
# Confirm FT232H with HasMpsse = True at index 0
Get-FtdiDevice | Format-Table Index, Type, HasMpsse, SerialNumber

# Write 3 bytes to a SPI device register (write-only, no read)
# Returns [bool] $true; use [void] to suppress: [void](Invoke-PsGadgetSpi ...)
Invoke-PsGadgetSpi -Index 0 -Data @(0x02, 0x00, 0xFF)

# Read 4 bytes from SPI device (MOSI stays LOW during read)
$bytes = Invoke-PsGadgetSpi -Index 0 -ReadCount 4

# Full-duplex: send 4-byte command, receive 4-byte response simultaneously
$response = Invoke-PsGadgetSpi -Index 0 -Data @(0x01, 0x00, 0x00, 0x00) -ReadCount 4

# 10 MHz clock, SPI Mode 3, chip select on ADBUS4
Invoke-PsGadgetSpi -Index 0 -Data @(0xAB) -ClockHz 10000000 -SpiMode 3 -CsPin 4

# Address by serial number (stable across replug and hub changes)
Invoke-PsGadgetSpi -SerialNumber "FT4ABCDE" -Data @(0x9F) -ReadCount 3

# Polling loop -- keep device open across iterations
$dev = New-PsGadgetFtdi -SerialNumber "FT4ABCDE"
try {
    while ($true) {
        # MCP3208 8-ch ADC: start=1, single-ended ch0=0x80, pad=0x00
        $raw = Invoke-PsGadgetSpi -PsGadget $dev -Data @(0x01, 0x80, 0x00) -ReadCount 3
        $value = (($raw[1] -band 0x0F) -shl 8) -bor $raw[2]
        Write-Host "ADC ch0: $value"
        Start-Sleep -Seconds 5
    }
} finally {
    $dev.Close()
}
```

> **FT232R note**: Calling `Invoke-PsGadgetSpi` with an FT232R device fails at
> initialization. Verify `HasMpsse = True` in `Get-FtdiDevice` before proceeding.

---

## UART Workflow (FT232H and FT232R)

D2XX UART works on FT232R, FT232H, and compatible FTDI devices. It uses the
factory-default bit mode — no EEPROM programming required. The device acts as a
USB-to-serial bridge: TX transmits, RX receives.

### Hardware Wiring

| FT232H/FT232R pin | Signal | Connect to               |
|-------------------|--------|--------------------------|
| TXD / ADBUS0 (D0) | TX     | RX pin on target device  |
| RXD / ADBUS1 (D1) | RX     | TX pin on target device  |
| GND               | GND    | GND on target device     |

> **Cross-wiring rule**: TX on the FT232x goes to RX on the target, and RX goes
> to TX. Swapped TX/RX is the most common setup error.

### Commands

```powershell
# Send "AT\r\n" and read the response line (waits up to 2 seconds by default)
$resp = Invoke-PsGadgetUart -Index 0 -Data "AT`r`n" -ReadLine -BaudRate 9600

# $null = timeout (no \n received); "" = device sent bare \n; non-empty = response
if ($null -eq $resp) {
    Write-Host "No response within timeout -- check baud rate and wiring"
} else {
    Write-Host "Response: $resp"
}

# Raw read of 16 bytes at 115200 baud
$bytes = Invoke-PsGadgetUart -Index 0 -ReadCount 16 -BaudRate 115200

# Write binary bytes (no read)
Invoke-PsGadgetUart -Index 0 -Data ([byte[]](0x01, 0x02, 0x03)) -BaudRate 57600

# Address by serial number (stable across replug and USB hub changes)
Invoke-PsGadgetUart -SerialNumber "BG01X3GX" -Data "STATUS`r`n" -ReadLine -BaudRate 9600

# Increase readline timeout for slow-to-boot devices (5 seconds)
$resp = Invoke-PsGadgetUart -Index 0 -Data "BOOT`r`n" -ReadLine -LineTimeout 5000 -BaudRate 9600

# Polling loop -- keep device open to avoid per-call open/close overhead
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"
try {
    while ($true) {
        $resp = Invoke-PsGadgetUart -PsGadget $dev -Data "READ`r`n" -ReadLine
        if ($null -ne $resp) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss')  $resp"
        }
        Start-Sleep -Seconds 30
    }
} finally {
    $dev.Close()
}
```

---

## ESP-NOW Wireless Telemetry (MicroPython + FT232H UART)

ESP-NOW is a connectionless 802.11 protocol that lets ESP32 nodes send telemetry
to each other without a WiFi router. PSGadget bridges ESP-NOW traffic to the host
over UART using an FT232H as a USB-to-serial adapter (no MPSSE/GPIO needed here).

### Architecture

```
[ESP32 Transmitter] --ESP-NOW--> [ESP32 Receiver] --UART--> [FT232H] --USB--> [Host / PowerShell]
```

### Hardware Wiring (FT232H UART bridge)

| FT232H pin | Signal | ESP32 Receiver pin (default) |
|------------|--------|------------------------------|
| AD0 (TXD)  | TX     | GPIO6 (RX)                   |
| AD1 (RXD)  | RX     | GPIO5 (TX)                   |
| 3.3V       | Power  | 3.3V                         |
| GND        | Ground | GND                          |

> **Cross-wiring rule**: FT232H TX -> ESP32 RX, FT232H RX -> ESP32 TX.
> Swapped TX/RX produces no output and is the most common setup error.

All pin and baud defaults are overridable via `mpy/scripts/config.json`.

### Step 1 - Deploy MicroPython scripts

```powershell
# Deploy receiver role to the ESP32 wired to FT232H
Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB0" -Role Receiver

# Deploy transmitter role to the untethered wireless node
Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB1" -Role Transmitter

# Use a custom config for non-default pin assignments
Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB0" -Role Receiver -ConfigPath "./lab_pins.json"

# Skip the confirmation prompt
Install-PsGadgetMpyScript -SerialPort "COM4" -Role Transmitter -Force
```

Both devices reset automatically after push. The receiver boots and prints
`PsGadget-Receiver:ready` on UART. The transmitter prints
`PsGadget-Transmitter:ready` on serial.

### Step 2 - Read telemetry frames

Once both scripts are running, the receiver forwards telemetry frames to the
host over UART at 115200 baud. Read them via `Connect-PsGadgetMpy` or directly
through any serial terminal.

Telemetry frame format (pipe-delimited):
```
type|serial|machine|temp|battery|payload
```

### Step 3 - Query known devices

```powershell
# Pull the receiver's known_devices.txt (devices it has paired with)
Get-PsGadgetEspNowDevices -SerialPort "/dev/ttyUSB0"

# Save to a custom path
Get-PsGadgetEspNowDevices -SerialPort "COM4" -OutputPath "./lab_devices.txt"

# Inspect in pipeline
$devices = Get-PsGadgetEspNowDevices -SerialPort "/dev/ttyUSB0"
$devices | Format-Table Mac, LastSeen
```

### Custom config.json overrides

Deploy a custom `config.json` to change pins, baud rate, or timing without
modifying the bundled scripts:

```json
{
  "uart_tx_pin": 5,
  "uart_rx_pin": 6,
  "uart_baud": 115200,
  "send_interval_ms": 1000,
  "neopixel_pin": 21
}
```

All fields are optional; omitted keys use built-in defaults.

> **See also**: [examples/Example-EspNow.md](../examples/Example-EspNow.md) for a
> full multi-persona walkthrough including troubleshooting and a Quick Reference.

---

## Device Capability Comparison

| Feature              | FT232H          | FT232R               |
|----------------------|-----------------|----------------------|
| GPIO pins            | ACBUS0-7        | CBUS0-3              |
| GPIO pin count       | 8               | 4                    |
| GPIO mechanism       | MPSSE (0x02)    | CBUS bit-bang (0x20) |
| One-time EEPROM setup| Optional (DisableVcp if VCP conflict) | Required (once)      |
| EEPROM inspection    | Get-PsGadgetFtdiEeprom (Windows)    | Get-PsGadgetFtdiEeprom (Windows) / Get-FtdiNativeCbusEepromInfo (Linux) |
| EEPROM programming   | Set-PsGadgetFtdiEeprom (Windows)    | Set-PsGadgetFtdiEeprom (Windows) |
| GpioMethod value     | MPSSE           | CBUS                 |
| HasMpsse             | True            | False                |
| SPI / I2C / JTAG     | Yes (MPSSE) — `Invoke-PsGadgetSpi`, `Invoke-PsGadgetI2C` | No |
| SSD1306 OLED display | Yes             | No                   |
| Async bit-bang ADBUS | Yes             | Yes (stepper motor primary path) |
| Stepper motor        | Yes (Invoke-PsGadgetStepper) | Yes (Invoke-PsGadgetStepper) |
| Windows GPIO support | Yes             | Yes                  |
| Linux GPIO support   | Yes (IoT .NET)  | Yes (native P/Invoke, requires libftd2xx.so) |
| macOS GPIO support   | Yes (IoT .NET)  | Yes (native P/Invoke, requires libftd2xx.dylib) |

---

## Available CBUS Mode Options (FT232R)

These are valid values for the `-Mode` parameter of `Set-PsGadgetFt232rCbusMode`:

| Mode name           | Function                     |
|---------------------|------------------------------|
| FT_CBUS_IOMODE      | GPIO / bit-bang (use this for Set-PsGadgetGpio) |
| FT_CBUS_TXLED       | Pulses on Tx data            |
| FT_CBUS_RXLED       | Pulses on Rx data            |
| FT_CBUS_TXRXLED     | Pulses on Tx or Rx data      |
| FT_CBUS_PWRON       | Power-on signal              |
| FT_CBUS_SLEEP       | Sleep indicator              |
| FT_CBUS_CLK48       | 48 MHz clock output          |
| FT_CBUS_CLK24       | 24 MHz clock output          |
| FT_CBUS_CLK12       | 12 MHz clock output          |
| FT_CBUS_CLK6        | 6 MHz clock output           |
| FT_CBUS_TXDEN       | Tx Data Enable               |
| FT_CBUS_BITBANG_WR  | Bit-bang write strobe        |
| FT_CBUS_BITBANG_RD  | Bit-bang read strobe         |

---

## OOP Class Interface

PSGadget exposes an object-oriented interface via `New-PsGadgetFtdi`, which returns a
`PsGadgetFtdi` instance whose methods wrap the underlying D2XX connection.

> **Note**: Because PSGadget uses dot-sourced class files inside the module, the
> `[PsGadgetFtdi]` type is not visible in the caller's global scope after
> `Import-Module`. Always use `New-PsGadgetFtdi` to create instances.

```powershell
# Create a device object - connected immediately (no .Connect() needed)
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"

# Identify by USB port location (stable for fixed demo rig wiring)
# Get-FtdiDevice | Select-Object Index, SerialNumber, LocationId
$dev = New-PsGadgetFtdi -LocationId 197634

# FT232R CBUS GPIO (pins 0-3)
$dev.SetPin(0, "HIGH")   # CBUS0 HIGH
$dev.SetPin(1, $true)    # bool overload: $true = HIGH, $false = LOW
$dev.SetPins(@(0, 1), "HIGH")   # set multiple pins at once
$dev.SetPins(@(0, 1), $false)   # clear multiple pins

# FT232H MPSSE GPIO (pins 0-7 = ACBUS0-7)
$dev.SetPin(2, "HIGH")   # ACBUS2
$dev.SetPins(@(2, 4), "LOW")

# Pulse a pin HIGH for 500 ms then revert to LOW
$dev.PulsePin(0, "HIGH", 500)

# Raw device I/O
$dev.Write([byte[]] @(0x01, 0x82, 0xFF, 0x00))
$buf = $dev.Read(4)

# Inspect state
$dev.Type        # e.g. "FT232R"
$dev.GpioMethod  # e.g. "CBUS"
$dev.SerialNumber
$dev.IsOpen

# Always close when done
$dev.Close()
```

### Available PsGadgetFtdi methods

| Method                                   | Description                                |
|------------------------------------------|--------------------------------------------|
| `Connect()`                              | Re-open after Close() (idempotent: no-op if already open) |
| `Close()`                                | Close the device connection                |
| `SetPin(int pin, string state)`          | Set pin HIGH/LOW/H/L/1/0                   |
| `SetPin(int pin, bool high)`             | Set pin via boolean                        |
| `SetPins(int[] pins, string state)`      | Set multiple pins simultaneously           |
| `SetPins(int[] pins, bool high)`         | Set multiple pins via boolean              |
| `PulsePin(int pin, string state, int ms)`| Hold state for ms then invert              |
| `Write(byte[] data)`                     | Write raw bytes to device                  |
| `Read(int count)`                        | Read raw bytes from device                 |
| `Step(int steps)`                        | Move N half-steps forward (uses DefaultStepMode) |
| `Step(int steps, string direction)`      | Move N steps in given direction            |
| `Step(int steps, string dir, string mode)` | Explicit step mode (Half/Full)           |
| `Step(int steps, string dir, string mode, int delayMs)` | With custom delay      |
| `StepDegrees(double degrees)`            | Rotate by angle using StepsPerRevolution calibration |
| `StepDegrees(double degrees, string direction)` | Rotate in given direction           |
| `StepDegrees(double degrees, string dir, string mode)` | Explicit step mode       |
| `StepDegrees(double degrees, string dir, string mode, double spr)` | Override calibration |

### Set-PsGadgetGpio -Connection

`Set-PsGadgetGpio` also accepts a `-Connection` object directly from
`Connect-PsGadgetFtdi`. The caller owns the connection lifecycle (the function
does not close it).

```powershell
$conn = Connect-PsGadgetFtdi -SerialNumber "BG01X3GX"
Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH
Set-PsGadgetGpio -Connection $conn -Pins @(1) -State HIGH
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW
$conn.Close()
```

---

## Public Function Quick Reference

| Function                    | Purpose                                                       |
|-----------------------------|---------------------------------------------------------------|
| New-PsGadgetFtdi            | Create a PsGadgetFtdi device object (OOP entry point; -SerialNumber, -Index, or -LocationId) |
| Get-FtdiDevice           | Enumerate PsGadget-compatible FTDI devices (D2XX only by default; use -ShowVCP to include VCP) |
| Connect-PsGadgetFtdi        | Open a device connection by index, serial number, or LocationId |
| Get-PsGadgetFtdiEeprom      | Read EEPROM contents (FT232H and FT232R: inspect IsVCP flag, CBUS/ACBUS modes, drive settings) |
| Set-PsGadgetFtdiEeprom      | Write EEPROM settings for FT232H or FT232R (-DisableVcp to fix VCP/MPSSE conflict; -CbusPins to configure CBUS pins; -ACDriveCurrent/-ADDriveCurrent for FT232H) |
| Set-PsGadgetFt232rCbusMode  | Program FT232R CBUS pins to GPIO mode (legacy one-chip command; Set-PsGadgetFtdiEeprom preferred) |
| Set-PsGadgetGpio            | Set GPIO pin state (FT232H and FT232R; -Connection supported) |
| Invoke-PsGadgetI2C          | Unified I2C dispatch (-I2CModule PCA9685 for servo control, SSD1306 for OLED); auto-opens/closes device unless -PsGadget supplied |
| Invoke-PsGadgetI2CScan      | Scan I2C bus and report devices found (-Index, -SerialNumber) |
| Invoke-PsGadgetSpi          | MPSSE SPI on FT232H: -Data write, -ReadCount read, or both for full-duplex; -ClockHz, -SpiMode 0-3, -CsPin; auto-opens/closes unless -PsGadget supplied |
| Invoke-PsGadgetUart         | D2XX UART on FT232H/FT232R: -Data write, -ReadCount raw read, or -ReadLine (returns $null on timeout); -BaudRate, -LineTimeout; auto-opens/closes unless -PsGadget supplied |
| Invoke-PsGadgetStepper      | Drive a stepper motor via async bit-bang ADBUS0-3 (FT232R or FT232H); -Steps or -Degrees; -StepsPerRevolution for calibrated angles (28BYJ-48 default ~4075.77 half-steps/rev, NOT 4096) |
| Get-PsGadgetMpy            | Enumerate MicroPython serial ports                            |
| Connect-PsGadgetMpy         | Open a MicroPython REPL connection                            |
| Install-PsGadgetMpyScript   | Deploy bundled ESP-NOW Receiver or Transmitter main.py + config.json to an ESP32 via mpremote (-SerialPort, -Role, -ConfigPath, -Force) |
| Get-PsGadgetEspNowDevices   | Pull known_devices.txt from Receiver flash via mpremote; returns [PSCustomObject]{Mac, LastSeen}[] (-SerialPort, -OutputPath) |
| Send-PsGadgetI2CWrite       | Write bytes to an I2C device over MPSSE (-PsGadget, -Address, -Data); call after Set-PsGadgetFtdiMode -Mode MpsseI2c |
| Set-PsGadgetFtdiMode        | Set operating mode of a connected FTDI device (MPSSE, MpsseI2c, CBUS, AsyncBitBang); MpsseI2c also runs I2C idle-state init |
| Get-PsGadgetConfig          | Return current in-memory PSGadget config; use -Section ftdi or logging to filter |
| Set-PsGadgetConfig          | Set a config value by dot-key (e.g. 'ftdi.highDriveIOs') and persist to ~/.psgadget/config.json |
| Test-PsGadgetEnvironment    | Verify environment, backend, native lib, and device count; returns Status/Reason/NextStep (-Verbose for detail) |

---

## Maintenance Notes

- Update this file whenever a new device type is supported or a public function changes.
- Add a new H2 section for each new board type following the FT232H / FT232R pattern.
- Keep the Device Capability Comparison table current with all supported types.
- Keep the Public Function Quick Reference table in sync with FunctionsToExport in PSGadget.psd1.
