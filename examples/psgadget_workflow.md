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
| 4-7                | (invalid)   | Error thrown; use 0-3 only |

### Step 1 - Ensure D2XX Driver Access

**CRITICAL**: EEPROM programming requires D2XX API access. If `List-PsGadgetFtdi` shows your FT232R devices with `ftdibus.sys (VCP)` driver, you must switch them to D2XX driver first.

**Check driver status:**
```powershell
List-PsGadgetFtdi | Format-Table Index, Type, Driver, SerialNumber

# If you see "ftdibus.sys (VCP)" for FT232R devices, they need driver switching
# Example problem output:
#   1 FT232R ftdibus.sys (VCP) B001BT11A    # <- Cannot access EEPROM
#   0 FT232H ftd2xx.dll       CT9UMHFA      # <- Can access EEPROM
```

**To switch from VCP to D2XX driver:**

**Option A: Programmatic VCP Unloading (Experimental)**
```powershell
# Attempt programmatic VCP unloading for your specific device
Invoke-PsGadgetFtdiVcpUnload -SerialNumber "BG01B0I1A"

# Check if it worked
List-PsGadgetFtdi | Where-Object SerialNumber -eq "BG01B0I1A" | Format-Table Driver

# If still VCP, try different methods
Invoke-PsGadgetFtdiVcpUnload -SerialNumber "BG01B0I1A" -Method CyclePort
Invoke-PsGadgetFtdiVcpUnload -SerialNumber "BG01B0I1A" -Method Windows
```

**Option B: Manual Driver Switching**

1. Download and install [FTDI's CDM driver package](https://ftdichip.com/drivers/) (includes both VCP and D2XX)
2. Use Windows Device Manager to switch driver:
   - Right-click device under "Ports (COM & LPT)"
   - Update Driver → Browse → Let me pick → Select "USB Serial Converter" (D2XX)
   - Or use FTDI's CDM Uninstaller GUI to switch driver modes

**Alternative: Use Zadig for WinUSB (logic analyzer use)**
- Download [Zadig](https://zadig.akeo.ie/) to install WinUSB driver 
- Note: WinUSB blocks both PSGadget (D2XX) and serial apps (VCP)
- Only use WinUSB if primary use is logic analyzer tools like sigrok/Pulseview

### Step 2 - Inspect current EEPROM (optional, recommended first time)

```powershell
$ee = Get-PsGadgetFtdiEeprom -Index 1
$ee | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# Factory defaults will show something like:
# Cbus0          Cbus1          Cbus2         Cbus3
# -----          -----          -----         -----
# FT_CBUS_TXLED  FT_CBUS_RXLED  FT_CBUS_PWRON FT_CBUS_SLEEP
```

### Step 3 - Program EEPROM for GPIO (one time per device)

```powershell
# Configure all four CBUS pins as GPIO (default and most common):
Set-PsGadgetFt232rCbusMode -Index 1

# Preview the change without writing:
Set-PsGadgetFt232rCbusMode -Index 1 -WhatIf

# Configure only CBUS0 and CBUS1; leave CBUS2/3 at factory function:
Set-PsGadgetFt232rCbusMode -Index 1 -Pins @(0, 1)

# Set a pin to a specific non-GPIO CBUS function:
Set-PsGadgetFt232rCbusMode -Index 1 -Pins @(0) -Mode FT_CBUS_RXLED
```

**IMPORTANT**: Replug the USB device after writing EEPROM. The new settings do not
take effect until the device re-enumerates.

### Step 4 - Verify after replug

```powershell
Get-PsGadgetFtdiEeprom -Index 1 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# Expected result after Set-PsGadgetFt232rCbusMode with defaults:
# Cbus0          Cbus1          Cbus2          Cbus3
# -----          -----          -----          -----
# FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE FT_CBUS_IOMODE
```

### Step 5 - Runtime GPIO

```powershell
# Set CBUS0 and CBUS1 HIGH
Set-PsGadgetGpio -DeviceIndex 1 -Pins @(0, 1) -State HIGH

# Pulse CBUS0 LOW for 200 ms
Set-PsGadgetGpio -DeviceIndex 1 -Pins @(0) -State LOW -DurationMs 200

# Restore
Set-PsGadgetGpio -DeviceIndex 1 -Pins @(0, 1) -State LOW

# Pins 4-7 will throw a clear error (CBUS bit-bang supports 0-3 only):
# Set-PsGadgetGpio -DeviceIndex 1 -Pins @(4) -State HIGH
# ERROR: Pin(s) [4] are out of range for CBUS bit-bang. FT232R CBUS GPIO supports CBUS0-3 only.
```

---

### Troubleshooting FT232R Issues

**Error: "Failed to open device via OpenByIndex and OpenBySerialNumber: FT_DEVICE_NOT_FOUND"**

This error occurs when the device is using VCP driver instead of D2XX driver. Check device list:
```powershell
List-PsGadgetFtdi | ft Index, Type, Driver, SerialNumber
```

If you see `ftdibus.sys (VCP)` instead of `ftd2xx.dll`, return to Step 1 above to switch drivers.

**Driver Switching Reference:**
- **D2XX mode**: Enables PSGadget EEPROM functions (`Get-PsGadgetFtdiEeprom`, `Set-PsGadgetFt232rCbusMode`) 
- **VCP mode**: Enables serial communication (COM ports for terminal apps)
- **WinUSB mode**: Enables logic analyzer tools (sigrok/Pulseview) but blocks PSGadget

**Multiple Device Management:**
Each FTDI device maintains its driver independently. You can have:
- FT232H#1 in D2XX mode (for PSGadget GPIO)
- FT232R#1 in D2XX mode (for PSGadget EEPROM programming and GPIO) 
- FT232R#2 in VCP mode (for serial terminal)
- FT232R#3 in WinUSB mode (for logic analyzer)

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

## Public Function Quick Reference

| Function                      | Purpose                                              |
|-------------------------------|------------------------------------------------------|
| List-PsGadgetFtdi             | Enumerate connected FTDI devices                     |
| Connect-PsGadgetFtdi          | Open a device connection by index or serial number   |
| Get-PsGadgetFtdiEeprom        | Read EEPROM contents (FT232R: inspect CBUS modes)    |
| Set-PsGadgetFt232rCbusMode    | Program FT232R CBUS pins to GPIO mode (one-time)     |
| Invoke-PsGadgetFtdiVcpUnload  | Programmatically unload VCP driver (experimental)    |
| Set-PsGadgetGpio              | Set GPIO pin state (works for both FT232H and FT232R)|
| List-PsGadgetMpy              | Enumerate MicroPython serial ports                   |
| Connect-PsGadgetMpy           | Open a MicroPython REPL connection                   |

---

## Maintenance Notes

- Update this file whenever a new device type is supported or a public function changes.
- Add a new H2 section for each new board type following the FT232H / FT232R pattern.
- Keep the Device Capability Comparison table current with all supported types.
- Keep the Public Function Quick Reference table in sync with FunctionsToExport in PSGadget.psd1.
