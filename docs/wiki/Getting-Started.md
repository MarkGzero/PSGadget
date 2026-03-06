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

Example output on Windows with one FT232H and one FT232R plugged in (Linux output is similar -- see [Linux Setup](#linux-setup)):

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
List-PsGadgetFtdi -ShowVCP

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
List-PsGadgetFtdi

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
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", MODE="0666"' | \
    sudo tee /etc/udev/rules.d/99-ftdi.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Once installed, the IoT warning disappears and GPIO is fully functional.

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
`-LocationId` as alternatives to `-Index`:

```powershell
# Stable across re-plugs on the same USB port
$dev = New-PsGadgetFtdi -LocationId 197634   # connected immediately

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
