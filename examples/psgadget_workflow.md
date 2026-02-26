# PSGadget Workflow Reference

This file documents end-to-end usage workflows for each supported FTDI device type.
It is maintained alongside the codebase and updated whenever new device support or
public functions are added.

---

## Module Setup

```powershell
# Load module for the current session
Import-Module ./PSGadget.psd1 -Force

# Enumerate all connected FTDI devices
List-PsGadgetFtdi | Format-Table

# Example output:
# Index  Description          SerialNumber  Type    GpioMethod  HasMpsse
# -----  -----------          ------------  ----    ----------  --------
#   0    USB Serial Converter FT4ABCDE      FT232H  MPSSE       True
#   1    USB Serial Adapter   FT1XYZAB      FT232R  CBUS        False
```

---

## FT232H Workflow (MPSSE - ACBUS0-7)

The FT232H has a built-in MPSSE engine. GPIO is available immediately on
ACBUS0-7 (physical pins 21-31). No EEPROM programming is required.

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
List-PsGadgetFtdi | Format-Table

# Set ACBUS2 and ACBUS4 HIGH
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(2, 4) -State HIGH

# Pulse ACBUS0 LOW for 500 ms then restore
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State LOW -DurationMs 500

# Turn both off
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(2, 4) -State LOW

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
When both VCP and D2XX drivers are installed (standard Windows setup), each physical FTDI device appears **twice** in `List-PsGadgetFtdi`:

```powershell
List-PsGadgetFtdi | Format-Table Index, Type, Driver, SerialNumber, ComPort

# Example output for one physical device:
# Index Type   Driver              SerialNumber ComPort
# ----- ----   ------              ------------ -------
#   0   FT232R ftd2xx.dll          BG01X3GX            # <- Use this for PSGadget
#   3   FT232R ftdibus.sys (VCP)   BG01X3GXA   COM3    # <- Same device, VCP view
```

**Key observations:**
- **Same physical device** = Same LocationId, SerialNumber with/without "A" suffix
- **D2XX entry** (no "A" suffix): Use this index for PSGadget EEPROM/GPIO functions
- **VCP entry** ("A" suffix): Available for serial terminal applications
- **No driver switching needed** - Both modes coexist perfectly!

**Find your D2XX-enabled device:**
```powershell
# Look for devices with ftd2xx.dll driver - these are ready for PSGadget
List-PsGadgetFtdi | Where-Object Driver -eq "ftd2xx.dll" | Format-Table Index, SerialNumber
```

### Step 2 - Inspect current EEPROM (optional, recommended first time)

```powershell
# Use the Index with ftd2xx.dll driver from Step 1
$ee = Get-PsGadgetFtdiEeprom -Index 0
$ee | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# Factory defaults will show something like:
# Cbus0          Cbus1          Cbus2         Cbus3
# -----          -----          -----         -----
# FT_CBUS_TXLED  FT_CBUS_RXLED  FT_CBUS_PWRON FT_CBUS_SLEEP
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
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0, 1) -State HIGH

# Pulse CBUS0 LOW for 200 ms
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State LOW -DurationMs 200

# Restore
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0, 1) -State LOW

# Pins 4-7 will throw a clear error (CBUS bit-bang supports 0-3 only):
# Set-PsGadgetGpio -DeviceIndex 0 -Pins @(4) -State HIGH
# ERROR: Pin(s) [4] are out of range for CBUS bit-bang. FT232R CBUS GPIO supports CBUS0-3 only.
```

---

### Troubleshooting FT232R Issues

**Error: "Failed to open device via OpenByIndex and OpenBySerialNumber: FT_DEVICE_NOT_FOUND"**

This typically means you're trying to use a VCP-only index. Solution:
```powershell
# Check which devices have D2XX access
List-PsGadgetFtdi | Where-Object Driver -eq "ftd2xx.dll" | Format-Table Index, SerialNumber

# Use one of those Index values instead
Set-PsGadgetFt232rCbusMode -Index <D2XX_INDEX>
```

**Understanding Dual Enumeration:**
- **One physical device** = Two entries in `List-PsGadgetFtdi`
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

## Device Capability Comparison

| Feature              | FT232H          | FT232R               |
|----------------------|-----------------|----------------------|
| GPIO pins            | ACBUS0-7        | CBUS0-3              |
| GPIO pin count       | 8               | 4                    |
| GPIO mechanism       | MPSSE (0x02)    | CBUS bit-bang (0x20) |
| One-time EEPROM setup| Not required    | Required (once)      |
| EEPROM inspection    | N/A             | Get-PsGadgetFtdiEeprom |
| EEPROM programming   | N/A             | Set-PsGadgetFt232rCbusMode |
| GpioMethod value     | MPSSE           | CBUS                 |
| HasMpsse             | True            | False                |
| SPI / I2C / JTAG     | Yes (MPSSE)     | No                   |
| Async bit-bang ADBUS | No              | Not yet implemented  |

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
# Create a device object and connect
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"
$dev.Connect()           # opens D2XX connection, populates Type/GpioMethod/etc.

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
| `Connect()`                              | Open the device connection                 |
| `Close()`                                | Close the device connection                |
| `SetPin(int pin, string state)`          | Set pin HIGH/LOW/H/L/1/0                   |
| `SetPin(int pin, bool high)`             | Set pin via boolean                        |
| `SetPins(int[] pins, string state)`      | Set multiple pins simultaneously           |
| `SetPins(int[] pins, bool high)`         | Set multiple pins via boolean              |
| `PulsePin(int pin, string state, int ms)`| Hold state for ms then invert              |
| `Write(byte[] data)`                     | Write raw bytes to device                  |
| `Read(int count)`                        | Read raw bytes from device                 |

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
| New-PsGadgetFtdi            | Create a PsGadgetFtdi device object (OOP entry point)         |
| List-PsGadgetFtdi           | Enumerate connected FTDI devices                              |
| Connect-PsGadgetFtdi        | Open a device connection by index or serial number            |
| Get-PsGadgetFtdiEeprom      | Read EEPROM contents (FT232R: inspect CBUS modes)             |
| Set-PsGadgetFt232rCbusMode  | Program FT232R CBUS pins to GPIO mode (one-time)              |
| Set-PsGadgetGpio            | Set GPIO pin state (FT232H and FT232R; -Connection supported) |
| List-PsGadgetMpy            | Enumerate MicroPython serial ports                            |
| Connect-PsGadgetMpy         | Open a MicroPython REPL connection                            |

---

## Maintenance Notes

- Update this file whenever a new device type is supported or a public function changes.
- Add a new H2 section for each new board type following the FT232H / FT232R pattern.
- Keep the Device Capability Comparison table current with all supported types.
- Keep the Public Function Quick Reference table in sync with FunctionsToExport in PSGadget.psd1.
