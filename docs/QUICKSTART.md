# PSGadget Quick Start

Get from zero to a working device in under five minutes.

If you have not installed PSGadget yet, start at [INSTALL.md](INSTALL.md).

---

## Table of Contents

- [Pick your path](#pick-your-path)
- [No hardware -- stub mode](#no-hardware----stub-mode)
- [FT232H](#ft232h)
  - [Minimum happy path](#minimum-happy-path)
  - [I2C scan (FT232H only)](#i2c-scan-ft232h-only)
- [FT232R](#ft232r)
  - [First-time setup (one-time, per device)](#first-time-setup-one-time-per-device)
  - [Minimum happy path (after EEPROM setup)](#minimum-happy-path-after-eeprom-setup)
- [SSD1306 OLED](#ssd1306-oled)
- [MicroPython REPL](#micropython-repl)
- [Persona walkthroughs](#persona-walkthroughs)
  - [Nikola -- new to everything](#nikola----new-to-everything)
  - [Jordan -- PowerShell scripter](#jordan----powershell-scripter)
  - [Izzy -- hardware engineer](#izzy----hardware-engineer)
  - [Scott -- quick reference](#scott----quick-reference)

---

## Pick your path

**By persona**
- [I am new to PowerShell and hardware (Nikola)](#nikola-new-to-everything)
- [I know PowerShell but not hardware (Jordan)](#jordan-powershell-scripter)
- [I know hardware but not PowerShell modules (Izzy)](#izzy-hardware-engineer)
- [Just show me the commands (Scott)](#scott-quick-reference)

**By device**
- [FT232H -- 8-pin GPIO + I2C/SPI via MPSSE](#ft232h)
- [FT232R -- 4-pin CBUS GPIO](#ft232r)
- [SSD1306 OLED display over I2C](#ssd1306-oled)
- [MicroPython board over serial REPL](#micropython-repl)
- [No hardware -- explore in stub mode](#no-hardware-stub-mode)

---

## No hardware -- stub mode

The module works without any hardware connected. It returns simulated devices
and lets you call every cmdlet. This is useful for exploring the API or writing
and testing scripts before your hardware arrives.

```powershell
Import-Module PSGadget

# Lists two simulated stub devices
List-PsGadgetFtdi | Format-Table

# Check environment -- will report backend and stub status
Test-PsGadgetEnvironment

# OOP interface works in stub mode too
$dev = New-PsGadgetFtdi -Index 0
$dev.SetPin(0, 'HIGH')
$dev.Close()
```

No errors mean everything is working. Stub mode is the default on any machine
where the native FTDI library is not installed.

---

## FT232H

The FT232H is an FTDI chip with 8 GPIO pins (ACBUS0-7) accessible via MPSSE.
It supports I2C, SPI, JTAG, and raw bit-bang. No EEPROM programming needed
before first use.

### Minimum happy path

```powershell
Import-Module PSGadget

# 1. Confirm environment
Test-PsGadgetEnvironment

# 2. List devices and find your FT232H
List-PsGadgetFtdi | Format-Table

# 3. Connect by serial number (stable across USB ports)
$dev = New-PsGadgetFtdi -SerialNumber 'BG01X3GX'

# 4. Toggle GPIO pin ACBUS0 HIGH then LOW
$dev.SetPin(0, 'HIGH')
Start-Sleep -Milliseconds 500
$dev.SetPin(0, 'LOW')

# 5. Set multiple pins at once
$dev.SetPins(@(0, 1, 2), 'HIGH')

# 6. Done
$dev.Close()
```

Pin numbering: ACBUS0 = pin 0, ACBUS1 = pin 1, ... ACBUS7 = pin 7.
All pins are 3.3 V. Do not connect 5 V signals directly.

### I2C scan (FT232H only)

```powershell
$dev = New-PsGadgetFtdi -SerialNumber 'BG01X3GX'
$dev.Scan()    # returns list of I2C addresses that responded with ACK
$dev.Close()
```

---

## FT232R

The FT232R has 4 CBUS GPIO pins (CBUS0-3). Unlike the FT232H, CBUS bit-bang
mode requires a one-time EEPROM configuration step before the pins respond.

### First-time setup (one-time, per device)

```powershell
Import-Module PSGadget

# Program the EEPROM on the device at index 0 to enable CBUS bit-bang
# This writes to the device EEPROM -- you only do this once per device
Set-PsGadgetFt232rCbusMode -Index 0
```

After the EEPROM is written, unplug and replug the USB cable to activate
the new configuration.

### Minimum happy path (after EEPROM setup)

```powershell
Import-Module PSGadget

$dev = New-PsGadgetFtdi -Index 0

# Toggle CBUS0 HIGH then LOW
$dev.SetPin(0, 'HIGH')
Start-Sleep -Milliseconds 500
$dev.SetPin(0, 'LOW')

$dev.Close()
```

Pin numbering: CBUS0 = pin 0, CBUS1 = pin 1, CBUS2 = pin 2, CBUS3 = pin 3.
CBUS4 exists on the chip but can only be configured via EEPROM, not driven
at runtime.

---

## SSD1306 OLED

A 128x64 pixel OLED display connected to an FT232H over I2C.
Default wiring: FT232H ACBUS0 = SCL, ACBUS1 = SDA. Power the display from
3.3 V and GND on the FT232H breakout.

```powershell
Import-Module PSGadget

# 1. Open the FTDI device
$ftdi = Connect-PsGadgetFtdi -Index 0

# 2. Connect to the display (default I2C address 0x3C)
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi

# 3. Clear the screen
Clear-PsGadgetSsd1306 -Display $display

# 4. Write text to a page (page 0 = top row)
Write-PsGadgetSsd1306 -Display $display -Text 'Hello World' -Page 0
Write-PsGadgetSsd1306 -Display $display -Text 'PSGadget v0.3' -Page 1

# 5. Set cursor and write more
Set-PsGadgetSsd1306Cursor -Display $display -Page 4 -Column 0
Write-PsGadgetSsd1306 -Display $display -Text 'Running...' -Page 4

# 6. Done
$ftdi.Close()
```

The display has 8 pages (rows). Page 0 is the top, page 7 is the bottom.
Each page is 8 pixels tall.

---

## MicroPython REPL

Connect to a Raspberry Pi Pico, ESP32, or any MicroPython board over USB serial.

```powershell
Import-Module PSGadget

# List available serial ports
List-PsGadgetMpy | Format-Table

# Connect to the board (adjust port name for your system)
# Windows: COM3, COM4, etc.
# Linux:   /dev/ttyUSB0, /dev/ttyACM0, etc.
# macOS:   /dev/tty.usbmodem*, /dev/tty.usbserial*, etc.
$mpy = Connect-PsGadgetMpy -SerialPort '/dev/ttyUSB0'

# Run MicroPython code
$mpy.Invoke("print('hello from MicroPython')")
$mpy.Invoke("import machine; machine.freq()")

# Run a multi-line block
$mpy.Invoke(@"
import time
for i in range(3):
    print(i)
    time.sleep(0.1)
"@)
```

---

## Persona walkthroughs

### Nikola -- new to everything

**What you need**: a Windows or Linux computer, PowerShell installed, and an
FTDI USB adapter (search "FT232H breakout" on Amazon, ~$10).

**Step 1**: Install PSGadget:

```powershell
Install-Module PSGadget -Scope CurrentUser
```

**Step 2**: Plug in your FTDI adapter. Open PowerShell and type:

```powershell
Import-Module PSGadget
Test-PsGadgetEnvironment
```

Read the `Status` line. If it says `READY`, you are set. If it says `Fail`,
copy the `NextStep` value and run that command.

**Step 3**: See your device:

```powershell
List-PsGadgetFtdi | Format-Table
```

This shows the device type, serial number, and what kind of GPIO it supports.

**Step 4**: Connect and blink:

```powershell
$dev = New-PsGadgetFtdi -Index 0
$dev.SetPin(0, 'HIGH')    # turn on pin 0
Start-Sleep -Seconds 1
$dev.SetPin(0, 'LOW')     # turn off pin 0
$dev.Close()
```

If you have an LED connected between ACBUS0 and GND through a 330 ohm
resistor, it blinks.

---

### Jordan -- PowerShell scripter

You already know PowerShell. The important things to know about PSGadget:

- `New-PsGadgetFtdi` returns a `PsGadgetFtdi` object. Use its methods rather
  than individual cmdlets for multi-step scripts -- it owns the connection.
- `Test-PsGadgetEnvironment` returns a structured object you can check in
  scripts: `$result.Status -eq 'OK'`.
- All cmdlets follow standard PowerShell conventions: `-Verbose` for detail,
  `-ErrorAction Stop` to catch failures, pipeline-friendly output.

```powershell
# Scriptable environment check
$env = Test-PsGadgetEnvironment
if ($env.Status -ne 'OK') {
    Write-Warning "PSGadget not ready: $($env.Reason)"
    Write-Warning "Fix: $($env.NextStep)"
    return
}

# Connect using serial number for stability across reboots
$devices = List-PsGadgetFtdi
$target  = $devices | Where-Object { $_.Type -match 'FT232H' } | Select-Object -First 1
$dev     = New-PsGadgetFtdi -SerialNumber $target.SerialNumber

# Use and clean up
try {
    $dev.SetPins(@(0, 1), 'HIGH')
    Start-Sleep -Milliseconds 200
    $dev.SetPins(@(0, 1), 'LOW')
} finally {
    $dev.Close()
}
```

---

### Izzy -- hardware engineer

PSGadget exposes four layers:

| Layer | Files | What it does |
|-------|-------|-------------|
| Transport | `lib/net48/`, `lib/net8/` (loaded by `Initialize-FtdiAssembly.ps1`) | Open/close USB device, raw read/write bytes |
| Protocol | `Private/Ftdi.Mpsse.ps1` | MPSSE command sequences, I2C/SPI primitives, GPIO direction + state |
| Device | `Classes/PsGadgetFtdi.ps1`, `Classes/PsGadgetSsd1306.ps1` | Chip-level logic, register maps, mode management |
| API | `Public/*.ps1` | Thin cmdlet wrappers, parameter validation, pipeline output |

MPSSE I2C clock: 60 MHz base / (1 + divisor) / 2. Standard 100 kHz uses
divisor `0x14B`. Fast mode 400 kHz uses divisor `0x4A`.

GPIO pin state is preserved on each `SetPin` / `SetPins` call via
read-modify-write. The current direction byte and value byte are read from the
device before applying changes so unrelated pins keep their state.

I2C writes validate ACK after each byte. A NACK throws a terminating error
with the address and byte position in the error message.

---

### Scott -- quick reference

```powershell
# Import
Import-Module PSGadget

# Diagnostics
Test-PsGadgetEnvironment [-Verbose]
List-PsGadgetFtdi [| Format-Table]

# Connect
$dev = New-PsGadgetFtdi -SerialNumber 'BG01X3GX'
$dev = New-PsGadgetFtdi -Index 0

# GPIO
$dev.SetPin(0, 'HIGH' | 'LOW')
$dev.SetPins(@(0,1,2), 'HIGH' | 'LOW')
$dev.PulsePin(0, 'HIGH', <ms>)
$dev.Close()

# I2C scan
$dev.Scan()

# SSD1306
$ftdi    = Connect-PsGadgetFtdi -Index 0
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi [-Address 0x3C]
Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text 'text' -Page <0-7>
Set-PsGadgetSsd1306Cursor -Display $display -Page <0-7> -Column <0-127>
$ftdi.Close()

# MicroPython
$mpy = Connect-PsGadgetMpy -SerialPort <port>
$mpy.Invoke(<"code">)

# Config
Get-PsGadgetConfig
Set-PsGadgetConfig -Key <key> -Value <value>

# Compat alias (same as Test-PsGadgetEnvironment)
Test-PsGadgetSetup
```
