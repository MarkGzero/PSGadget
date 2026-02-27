# Getting Started with PSGadget

This page walks you through installing requirements, loading the module, and
making your first GPIO call on each supported device type.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| PowerShell | 5.1 or 7+. Check with `$PSVersionTable.PSVersion` |
| FTDI CDM drivers (Windows only) | [ftdichip.com/drivers/](https://ftdichip.com/drivers/) -- install both VCP and D2XX options |
| FTD2XX_NET.dll | Bundled in `lib/` -- no separate download needed |
| mpremote (MicroPython only) | `pip install mpremote` |

> **Linux / macOS**: The module loads and all functions are importable, but
> hardware calls stub out silently. Full D2XX hardware support is Windows-only.

---

## Installation

PSGadget is a local module -- clone or copy the folder, then import by path.

```powershell
# Clone the repo
git clone https://github.com/MarkGzero/PSGadget.git
cd PSGadget

# Import for the current session
Import-Module ./PSGadget.psd1

# Or add to your profile for every session
Add-Content $PROFILE "`nImport-Module C:\path\to\PSGadget\PSGadget.psd1"
```

---

## Verify the Module Loaded

```powershell
Get-Module PSGadget

# Expected output includes ModuleType, Name, and ExportedCommands
```

```powershell
# Confirm the config file was created
Get-PsGadgetConfig
```

The first import also creates `~/.psgadget/` with `logs/` and a default
`config.json`.

---

## Step 1 -- Find Your Device

```powershell
List-PsGadgetFtdi | Format-Table
```

Example output on Windows with one FT232H and one FT232R plugged in:

```
Index  Description          SerialNumber  LocationId  Type    GpioMethod  HasMpsse
-----  -----------          ------------  ----------  ----    ----------  --------
  0    USB Serial Converter FT4ABCDE      197634      FT232H  MPSSE       True
  1    USB Serial Adapter   BG01X3GX      197635      FT232R  CBUS        False
  2    USB Serial Adapter   BG01X3GXA     0           FT232R  CBUS        False   <- VCP view of same device
```

The `GpioMethod` column tells you which GPIO mechanism the device uses:
- **MPSSE** (FT232H) -- GPIO immediately available on ACBUS0-7
- **CBUS** (FT232R) -- requires one-time EEPROM setup before GPIO is usable

---

## Step 2a -- FT232H GPIO (No Setup Required)

FT232H devices are ready to use immediately.

```powershell
# Set ACBUS0 and ACBUS1 HIGH
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0, 1) -State HIGH

# Pulse ACBUS2 LOW for 250 ms, then release
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(2) -State LOW -DurationMs 250

# Turn all back off
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0, 1) -State LOW
```

For repeated or scripted use, the OOP interface is cleaner:

```powershell
$dev = New-PsGadgetFtdi -SerialNumber "FT4ABCDE"
$dev.Connect()
$dev.SetPin(0, "HIGH")
$dev.SetPins(@(0, 1, 2), "LOW")
$dev.Close()
```

---

## Step 2b -- FT232R GPIO (One-Time EEPROM Setup)

CBUS pins on the FT232R default to LED indicator functions. You must program the
device EEPROM once before they work as GPIO.

**Do this once per physical device:**

```powershell
# Use the D2XX-enabled index (GpioMethod = CBUS, no "A" suffix on SerialNumber)
# Preview what will be written without touching the device:
Set-PsGadgetFt232rCbusMode -Index 1 -WhatIf

# Write it:
Set-PsGadgetFt232rCbusMode -Index 1
```

You will be prompted to cycle the USB cable. After replugging:

```powershell
# Verify pins are now in GPIO mode
Get-PsGadgetFtdiEeprom -Index 1 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3
# Expected: FT_CBUS_IOMODE for all four

# Now GPIO works
Set-PsGadgetGpio -DeviceIndex 1 -Pins @(0) -State HIGH
```

> See [Workflow Reference](../../examples/psgadget_workflow.md) for the full
> FT232R setup sequence including dual enumeration details.

---

## Step 3 -- SSD1306 OLED Display

Requires an FT232H (MPSSE) device. Wire SCL to ADBUS0 and SDA to ADBUS1.

```powershell
$ftdi    = Connect-PsGadgetFtdi -Index 0
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi   # default I2C address 0x3C

Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text "PSGadget" -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $display -Text (Get-Date -Format "HH:mm:ss") -Page 2

$ftdi.Close()
```

---

## Step 4 -- MicroPython

```powershell
# Find MicroPython devices
List-PsGadgetMpy

# Connect and run code
$mpy = Connect-PsGadgetMpy -SerialPort "/dev/ttyUSB0"   # or COM3 on Windows
$mpy.Invoke("import sys; print(sys.version)")
```

---

## Addressing by Serial Number or LocationId

Both `Set-PsGadgetGpio` and `New-PsGadgetFtdi` accept `-SerialNumber` or
`-LocationId` as alternatives to `-Index` / `-DeviceIndex`:

```powershell
# Stable across re-plugs on the same USB port
$dev = New-PsGadgetFtdi -LocationId 197634
$dev.Connect()

# Stable regardless of port, but requires knowing the serial number
Set-PsGadgetGpio -SerialNumber "FT4ABCDE" -Pins @(0) -State HIGH
```

Use `List-PsGadgetFtdi | Select-Object SerialNumber, LocationId` to find
these values.

---

## Where to Go Next

| Task | Page |
|------|------|
| Look up a function's parameters | [Function Reference](Function-Reference.md) |
| Tune drive strength, logging, etc. | [Configuration](Configuration.md) |
| Full device workflows with pin maps | [Workflow Reference](../../examples/psgadget_workflow.md) |
