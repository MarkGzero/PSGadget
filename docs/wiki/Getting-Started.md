# Getting Started with PSGadget

This page walks you through installing requirements, loading the module, and
making your first GPIO call on each supported device type.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| PowerShell | 5.1 or 7+. Check with `$PSVersionTable.PSVersion` |
| FTDI CDM driver package (Windows only) | Installs native `FTD2XX.dll` system-wide. [ftdichip.com/drivers/d2xx-drivers/](https://ftdichip.com/drivers/d2xx-drivers/) -- select the CDM package, install both VCP and D2XX options |
| FTD2XX_NET managed wrapper (Windows only) | Bundled in `lib/` -- no install needed. To update: [C# FTD2XX Managed .NET Wrapper](https://ftdichip.com/software-examples/code-examples/csharp-examples/) |
| FTDI D2XX library (Linux, optional) | Required for GPIO/MPSSE on Linux. See [Linux Setup](#linux-setup) below. |
| mpremote (MicroPython only) | `pip install mpremote` |

---

## Installation

### Option A -- PSGallery (recommended)

```powershell
Install-Module PSGadget
Import-Module PSGadget
```

The module auto-creates `~/.psgadget/` with `logs/` and a default
`config.json` on first import.

### Option B -- from source

Use this path for the latest development build or to contribute changes.

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

## Before you start -- verify the environment

Run this before anything else. It checks PS version, backend selection,
native library presence, and device enumeration, and returns a structured
result with a `NextStep` hint if anything is wrong.

```powershell
Test-PsGadgetEnvironment -Verbose
```

Expected output when everything is ready:

```
Status      : READY
Reason      : All checks passed
NextStep    :
Backend     : IoT
BackendReady: True
DeviceCount : 1
IsReady     : True
```

If `Status` is `Fail`, stop here and follow the `NextStep` instruction.
Do not proceed to Step 1 until `IsReady` is `True`.

---

## Step 1 -- Find Your Device

```powershell
Get-FtdiDevice | Format-Table -Property Index, Type, SerialNumber, LocationId
```

Example output on Windows with one FT232H and one FT232R plugged in (Linux output is similar -- see [Linux Setup](#linux-setup)):

```
Index  Type    SerialNumber  LocationId
-----  ----    ------------  ----------
  0    FT232H  FT4ABCDE      197634
  1    FT232R  BG01X3GX      197635
```

(`-ShowVCP` adds VCP-mode entries if your device appears twice -- once as D2XX, once as a COM port.)

The `Type` column tells you which GPIO mechanism is available:
- **FT232H** -- MPSSE, ACBUS0-7 usable immediately
- **FT232R** -- CBUS bit-bang, requires one-time EEPROM setup before GPIO is usable

---

---

## Linux Setup

PSGadget enumerates FTDI devices on Linux using the kernel sysfs filesystem
(`/sys/bus/usb/devices/`) -- no extra tools needed. However, there are two
things to be aware of before GPIO will work.

### 1. The ftdi_sio VCP driver conflict

When you plug in an FTDI device, Linux automatically loads the `ftdi_sio`
kernel module, which claims the device as a serial port (`/dev/ttyUSBx`).
While loaded, the device shows as `IsVcp = true` and direct D2XX/GPIO access
is blocked.

```powershell
# With ftdi_sio loaded -- device appears as VCP, hidden by default
Get-FtdiDevice -ShowVCP

# Index  Type    LocationId    Driver          IsVcp
# -----  ----    ----------    ------          -----
#   0    FT232R  /dev/ttyUSB0  ftdi_sio (VCP)  True
```

Unload the VCP driver to release the device for direct access:

```bash
sudo rmmod ftdi_sio
```

After unloading:

```powershell
# Device now appears in default listing (no -ShowVCP needed)
Get-FtdiDevice

# Index  Type    LocationId       Driver  IsVcp
# -----  ----    ----------       ------  -----
#   0    FT232R  usb-bus1-dev4    sysfs   False
```

To prevent `ftdi_sio` from loading automatically on boot, add a udev rule:

```bash
# /etc/modprobe.d/blacklist-ftdi.conf
echo 'blacklist ftdi_sio' | sudo tee /etc/modprobe.d/blacklist-ftdi.conf
```

### 2. The D2XX library (libftd2xx.so)

GPIO and MPSSE operations on Linux require FTDI's proprietary D2XX runtime
library (`libftd2xx.so`). PSGadget uses the .NET IoT backend
(`Iot.Device.Bindings`) on PS 7.4+/.NET 8+, which calls into this library.

Until it is installed, the IoT backend falls back to sysfs-only mode
(enumeration works, GPIO does not) and prints a warning:

```
WARNING: IoT FTDI enumeration failed: Unable to load shared library 'ftd2xx'...
```

This warning is harmless -- enumeration still works via sysfs. GPIO requires
the library to be installed.

**Install libftd2xx.so:**

```bash
# 1. Download the Linux D2XX driver from FTDI:
#    https://ftdichip.com/drivers/d2xx-drivers/
#    Select: Linux / release / libftd2xx-x86_64-<version>.gz (or arm64 for Pi)

# 2. Extract and install:
tar xfz libftd2xx-x86_64-<version>.gz
cd release/build/x86_64
sudo cp libftd2xx.so.* /usr/local/lib/
sudo ln -sf /usr/local/lib/libftd2xx.so.* /usr/local/lib/libftd2xx.so
sudo ldconfig

# 3. Allow non-root access (create udev rule):
# Add your user to the plugdev group first (log out and back in after):
sudo usermod -aG plugdev "$USER"

echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", MODE="0664", GROUP="plugdev"' | \
    sudo tee /etc/udev/rules.d/99-ftdi-d2xx.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Once installed, the IoT warning disappears and GPIO is fully functional.

---

## Pin numbering quick reference

PSGadget uses logical pin numbers, not physical IC pin numbers.

### FT232H (MPSSE) -- ACBUS pins

The `-Pins` parameter maps to ACBUS signals on the FT232H breakout header.

| Pins value | Signal name | Adafruit #2264 header label |
| ---------- | ----------- | --------------------------- |
| 0 | ACBUS0 | C0 |
| 1 | ACBUS1 | C1 |
| 2 | ACBUS2 | C2 |
| 3 | ACBUS3 | C3 |
| 4 | ACBUS4 | C4 |
| 5 | ACBUS5 | C5 |
| 6 | ACBUS6 | C6 |
| 7 | ACBUS7 | C7 |

ACBUS0 is the C0 pin on the Adafruit FT232H breakout (the row of pins
labeled C0-C7 on the board silkscreen). To blink an LED: connect the
anode through a 330-ohm resistor to C0, cathode to GND.

### FT232R (CBUS) -- CBUS pins

| Pins value | Signal name | Notes |
| ---------- | ----------- | ----- |
| 0 | CBUS0 | Requires EEPROM setup first |
| 1 | CBUS1 | Requires EEPROM setup first |
| 2 | CBUS2 | Requires EEPROM setup first |
| 3 | CBUS3 | Requires EEPROM setup first |

Run `Set-PsGadgetFt232rCbusMode -Index N` once per device before using CBUS GPIO.

### SSD1306 I2C wiring (FT232H MPSSE)

| Signal | FT232H pin | Header label |
| ------ | ---------- | ------------ |
| SCL | ADBUS0 | D0 |
| SDA | ADBUS1 | D1 |
| GND | GND | GND |

Pull-up resistors (4.7 kohm) are required on SCL and SDA to 3.3V.

---

## Step 2a -- FT232H GPIO (No Setup Required)

FT232H devices are ready to use immediately.

```powershell
# Set ACBUS0 and ACBUS1 HIGH
Set-PsGadgetGpio -Index 0 -Pins @(0, 1) -State HIGH

# Pulse ACBUS2 LOW for 250 ms, then release
Set-PsGadgetGpio -Index 0 -Pins @(2) -State LOW -DurationMs 250

# Turn all back off
Set-PsGadgetGpio -Index 0 -Pins @(0, 1) -State LOW
```

For repeated or scripted use, the OOP interface is cleaner:

```powershell
$dev = New-PsGadgetFtdi -SerialNumber "FT4ABCDE"   # connected immediately
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
Set-PsGadgetGpio -Index 1 -Pins @(0) -State HIGH
```

> See [Workflow Reference](../../examples/psgadget_workflow.md) for the full
> FT232R setup sequence including dual enumeration details.

---

## Step 3 -- SSD1306 OLED Display

Requires an FT232H (MPSSE) device. Wire SCL to ADBUS0 and SDA to ADBUS1.

```powershell
$dev = New-PsGadgetFtdi -Index 0
$d   = $dev.GetDisplay()   # default I2C address 0x3C

$d.Initialize($false) | Out-Null
$d.Clear() | Out-Null
$d.WriteText("PSGadget", 0, "center", 1, $false) | Out-Null
$d.WriteText((Get-Date -Format "HH:mm:ss"), 2) | Out-Null

$dev.Close()
```

---

## Step 4 -- MicroPython

```powershell
# Find MicroPython devices
Get-PsGadgetMpy

# Connect and run code
$mpy = Connect-PsGadgetMpy -SerialPort "/dev/ttyUSB0"   # or COM3 on Windows
$mpy.Invoke("import sys; print(sys.version)")
```

---

## Addressing by Serial Number or LocationId

Both `Set-PsGadgetGpio` and `New-PsGadgetFtdi` accept `-SerialNumber` or
`-LocationId` as alternatives to `-Index`:

```powershell
# Stable across re-plugs on the same USB port
$dev = New-PsGadgetFtdi -LocationId 197634   # connected immediately

# Stable regardless of port, but requires knowing the serial number
Set-PsGadgetGpio -SerialNumber "FT4ABCDE" -Pins @(0) -State HIGH
```

Use `Get-FtdiDevice | Select-Object SerialNumber, LocationId` to find
these values.

---

## Where to Go Next

| Task | Page |
|------|------|
| Look up a function's parameters | [Function Reference](Function-Reference.md) |
| Tune drive strength, logging, etc. | [Configuration](Configuration.md) |
| Full device workflows with pin maps | [Workflow Reference](../../examples/psgadget_workflow.md) |
