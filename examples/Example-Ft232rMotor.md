# Example: DC Motor Control via FT232R CBUS GPIO

Drive a small DC motor (or any on/off load) using the CBUS bit-bang GPIO pins on an
FT232R USB-to-serial chip. This walkthrough covers hardware wiring, one-time EEPROM
setup, and runtime control with PSGadget.

---

## Who This Is For

This walkthrough is written with four readers in mind. Look for the labeled callouts
throughout to find the depth that matches your background.

- **Beginner** - new to microcontrollers, USB hardware, and PowerShell
- **Scripter** - comfortable with PowerShell scripting, new to hardware GPIO / FTDI
- **Engineer** - studied basic electronics, less familiar with Windows driver and PowerShell module concepts
- **Pro** - experienced with both; skip to the Quick Reference at the bottom

---

## What You Need

- An FT232R or FT232RNL USB breakout board (Waveshare USB-TO-TTL-FT232, SparkFun, etc.)
- A small DC motor rated for 3.3-5V and less than 4 mA current draw
  - Safe choices: pager (coin) vibration motors, small pancake motors
  - For anything larger: use a transistor (2N2222, BC547) or motor driver IC (DRV8833) as a buffer
- Windows PC with FTDI CDM drivers installed, USB cable
- PowerShell 5.1 or later
- PSGadget module cloned locally

> **Beginner**: An FT232R is a small chip (usually on a breakout board the size of a thumb drive)
> that lets your computer talk to hardware over USB. It has a few pins you can turn HIGH (on)
> or LOW (off) under software control -- that is what GPIO means. We are going to use one of
> those pins to switch a tiny motor on and off.

---

## Hardware Background

> **Engineer**: The FT232R exposes four CBUS pins (CBUS0-CBUS3) that can be configured as
> general-purpose digital I/O. The D2XX bit-bang API uses an 8-bit mask: upper 4 bits
> set direction (1 = output), lower 4 bits set the output value. Factory EEPROM programs
> those pins as LED drivers and sleep indicators -- you must reprogram the EEPROM once to
> switch them to IOMODE before runtime control is possible.
>
> The CBUS output stage is push-pull and sources approximately 4 mA maximum at VCCIO
> voltage. That is enough to directly drive a pager motor but not a standard DC gear motor.
> For higher current loads, connect CBUS0 to the base of an NPN transistor (through a
> 1k resistor) and power the motor from the collector side with a suitable supply.

### Voltage selection

Many FT232 breakout boards ship with VCCIO set to 3.3V by default. This means CBUS
pins output only 3.3V, which is often insufficient to run a motor at full speed or at all.

| Board type | How to select 5V |
|---|---|
| Boards with a 3-pin header labeled "5V / VCCIO / 3V3" | Bridge the 5V and VCCIO pins with a jumper cap |
| Waveshare USB-TO-TTL-FT232 | Move the SMD solder jumper on the back from 3.3V pad to 5V pad |

After changing the jumper, unplug and replug the USB cable before continuing.

### Wiring diagram (direct connection, small motor only)

```
FT232R breakout
  CBUS0 ---[motor+]---[motor-]--- GND
```

> **Engineer**: No flyback diode is needed for a direct pager motor because the inductance is
> negligible and the current is within the CBUS output stage's built-in clamp. For any
> inductive load driven through a transistor, always add a 1N4148 freewheeling diode
> across the motor terminals.

---

## Step 1 - Install Drivers and Verify Detection

FTDI provides a CDM (Combined Driver Model) package that installs both the VCP serial
driver and the D2XX library simultaneously.

> **Beginner**: A "driver" is a small program that lets Windows understand how to talk to
> your USB device. You need two kinds for this to work: one that lets PowerShell control
> the pins directly (D2XX), and one that shows it as a COM port (VCP). The FTDI CDM
> package installs both at once.

> **Scripter**: After installing the CDM package, each physical FT232R will appear TWICE
> in `List-PsGadgetFtdi` -- once as a D2XX device (driver: ftd2xx.dll) and once as a
> virtual COM port. PSGadget functions use the D2XX entry. You can identify it because
> it has no "A" appended to the serial number.

1. Download and install the [FTDI CDM driver package](https://ftdichip.com/drivers/)
2. Plug in the FT232R board
3. Open a PowerShell window and load the module:

```powershell
Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force
```

4. Enumerate connected FTDI devices:

```powershell
List-PsGadgetFtdi | Format-Table Index, Type, Driver, SerialNumber, LocationId, ComPort
```

Expected output (one physical FT232R appears twice):

```
Index  Type    Driver              SerialNumber  LocationId  ComPort
-----  ----    ------              ------------  ----------  -------
  0    FT232R  ftd2xx.dll          BG01X3GX      197634
  3    FT232R  ftdibus.sys (VCP)   BG01X3GXA     0           COM3
```

The D2XX row (no "A" suffix on the serial number, no COM port) is the one PSGadget uses.
Note its **Index** value -- you will need it in the next steps.

> **Pro**: `List-PsGadgetFtdi | Where-Object Driver -eq 'ftd2xx.dll'` to filter directly.

---

## Step 2 - Inspect Current EEPROM State

Before programming anything, read the current EEPROM to see how CBUS pins are configured.

```powershell
$ee = Get-PsGadgetFtdiEeprom -Index 0    # use your D2XX index
$ee | Select-Object Cbus0, Cbus1, Cbus2, Cbus3
```

Factory default output:

```
Cbus0          Cbus1          Cbus2         Cbus3
-----          -----          -----         -----
FT_CBUS_TXLED  FT_CBUS_RXLED  FT_CBUS_PWRON FT_CBUS_SLEEP
```

If CBUS0 already shows `FT_CBUS_IOMODE`, the device was already programmed -- skip to Step 4.

> **Beginner**: The EEPROM is a tiny permanent memory chip inside the FT232R that stores
> settings. "TXLED" means that pin is wired to blink when data is sent -- we need to
> change it to "IOMODE" (input/output mode) so we can turn it on and off ourselves.

> **Engineer**: FT_CBUS_IOMODE sets the pin mux to the bit-bang GPIO path. Other modes route
> the pin to internal signal generators (LED pulse, clock divider, etc.) and cannot be
> overridden at runtime without EEPROM changes.

---

## Step 3 - Program EEPROM (One Time Per Device)

This step writes new settings to the FT232R's EEPROM. You only need to do it once per
physical device. The change takes effect after a USB replug.

> **Scripter**: `Set-PsGadgetFt232rCbusMode` wraps the FTD2XX_NET `EEPROM_Program` call.
> It reads the current EEPROM, patches only the CBUS fields you specify, and writes it
> back. Use `-WhatIf` to preview the change without committing it.

Preview what would be written (safe, no changes made):

```powershell
Set-PsGadgetFt232rCbusMode -Index 0 -WhatIf
```

Program CBUS0 only to GPIO mode (leaves CBUS1-3 at factory functions):

```powershell
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0)
```

Program all four CBUS pins to GPIO mode (most flexible):

```powershell
Set-PsGadgetFt232rCbusMode -Index 0
```

After the command completes, **unplug and replug the USB cable** (or use `CyclePort` --
see the OOP approach below). The new EEPROM settings do not take effect until the device
re-enumerates on the USB bus.

> **Beginner**: After running this command, unplug the USB cable from your computer, wait
> two seconds, and plug it back in. This resets the chip and loads the new settings.

> **Engineer**: The FT232R's EEPROM is 128 x 16-bit EEPROM. CBUS mode fields are stored in
> words 0x18-0x1A. Write cycles are limited to roughly 10,000 per device lifetime, but
> since this is a one-time setup that limit is not a concern in practice.

---

## Step 4 - Verify EEPROM After Replug

After replugging, confirm the CBUS0 mode was written correctly:

```powershell
Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3
```

Expected result:

```
Cbus0           Cbus1           Cbus2           Cbus3
-----           -----           -----           -----
FT_CBUS_IOMODE  FT_CBUS_TXLED   FT_CBUS_RXLED   FT_CBUS_PWRON
```

(If you ran `Set-PsGadgetFt232rCbusMode -Index 0` without `-Pins`, all four will show
`FT_CBUS_IOMODE`.)

---

## Step 5 - Runtime Motor Control

With the EEPROM programmed, you can now switch CBUS0 (and other configured pins) at runtime.

### OOP style (recommended for scripts)

```powershell
Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force

# Create device object using serial number (stable across USB port changes)
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"   # use your serial number
$dev.Connect()

try {
    # Turn motor ON (CBUS0 HIGH)
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0) -State HIGH
    Write-Host "Motor running..."
    Start-Sleep -Seconds 3

    # Turn motor OFF (CBUS0 LOW)
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0) -State LOW
    Write-Host "Motor stopped."

} finally {
    $dev.Close()
}
```

### Quick cmdlet style (use at the prompt)

```powershell
# One-liner to turn motor on for 3 seconds then off
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State HIGH
Start-Sleep -Seconds 3
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State LOW
```

> **Pro**: `-DurationMs` parameter holds the state for the specified milliseconds then
> reverts automatically -- no `Start-Sleep` needed for timed pulses.

```powershell
# Pulse CBUS0 HIGH for 500 ms, then LOW automatically
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State HIGH -DurationMs 500
```

---

## Automated EEPROM Setup With Port Cycle (No Manual Replug)

If you are scripting an unattended setup, use `CyclePort` to apply EEPROM changes
without physically unplugging the device:

```powershell
$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()

Set-PsGadgetFt232rCbusMode -PsGadget $dev -Pins @(0)

Write-Host "Cycling USB port to apply EEPROM changes..."
$dev.CyclePort()   # triggers USB re-enumeration; polls until device returns
$dev.Close()

Write-Host "Done. Run the motor control block above."
```

> **Beginner**: `CyclePort` tells the chip to disconnect and reconnect itself on the USB bus
> automatically, so you do not have to manually unplug anything. It waits until the chip
> comes back before continuing.

---

## CBUS Pin Map

| `Pins` value | CBUS signal | FT232R physical pin |
|---|---|---|
| 0 | CBUS0 | Pin 23 |
| 1 | CBUS1 | Pin 22 |
| 2 | CBUS2 | Pin 13 |
| 3 | CBUS3 | Pin 14 |
| 4 | CBUS4 | EEPROM only; not available at runtime via Set-PsGadgetGpio |

---

## Troubleshooting

### "FT_DEVICE_NOT_FOUND"

You are probably using the VCP index instead of the D2XX index. Run:

```powershell
List-PsGadgetFtdi | Where-Object Driver -eq "ftd2xx.dll" | Format-Table Index, SerialNumber
```

Use one of those Index values.

### Motor does not move

- Check the VCCIO jumper -- most boards default to 3.3V which may be too low
- Run `Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0` to confirm `FT_CBUS_IOMODE`
- Verify wiring: motor positive to CBUS0, motor negative to GND
- Measure CBUS0 with a multimeter -- it should swing between 0V and VCCIO when you toggle

### Motor spins but is very weak

Board is set to 3.3V VCCIO. Move the jumper to 5V (see Voltage Selection section above).

---

## Quick Reference (Pro)

```powershell
# Enumerate (D2XX only)
List-PsGadgetFtdi | Where-Object Driver -eq "ftd2xx.dll" | Format-Table

# EEPROM read
Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# EEPROM write (one time)
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0)   # CBUS0 only
Set-PsGadgetFt232rCbusMode -Index 0               # all CBUS0-3

# Runtime GPIO
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State HIGH
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State LOW
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State HIGH -DurationMs 500

# OOP
$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()
Set-PsGadgetGpio -PsGadget $dev -Pins @(0) -State HIGH
$dev.Close()
```
