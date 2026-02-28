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
- A small DC motor rated for 3.3-5V
- A transistor -- use whichever you have:
  - **NPN**: 2N2222, BC547, or S8050 (any of these work; handles up to 600mA)
  - **PNP**: PN2907 (handles up to 600mA; logic is inverted -- see wiring below)
- Resistors: 1k ohm (base resistor) -- add a 10k ohm if using PNP
- Breadboard and jumper wires
- Windows PC with FTDI CDM drivers installed, USB cable
- PowerShell 5.1 or later
- PSGadget module cloned locally

> **Beginner**: An FT232R is a small chip (usually on a breakout board the size of a thumb drive... or your thumbnail)
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

### Why the 5V pin moves the motor but CBUS0 does not

This is the most common confusion when wiring a motor to an FT232R board.

The CBUS0 pin and the board's 5V power pin measure nearly identical voltage (both ~5V),
but they are fundamentally different in current capacity:

| Pin | Voltage | Max current |
|---|---|---|
| 5V (USB power) | ~5V | ~500mA (from the USB host) |
| CBUS0 (GPIO) | ~5V | ~4mA (CBUS output stage limit) |

When you connect a motor directly to CBUS0, the pin tries to hold 5V but can only push
4mA. The motor's inrush current collapses the pin voltage and the motor stalls -- even
though `Set-PsGadgetGpio` reports success and the pin reads correctly with no load.

The fix is to use CBUS0 as a **signal** (not a power source) and let the transistor
borrow current from the 5V rail to actually drive the motor.

> **Beginner**: Think of CBUS0 as a light switch, not a battery. It can flip something
> on or off, but you still need a power source behind it to do the actual work.

### Wiring: transistor driver (recommended for all motors)

CBUS0 sources ~4mA maximum. Most motors -- even tiny pager/coin vibration motors --
draw more than that under load, causing the pin voltage to sag and the motor to stall.
Drive a transistor from CBUS0 instead and power the motor from the USB 5V pin.

Use whichever transistor you have on hand. The circuits differ only in wiring and
switching logic.

---

#### Option A: NPN transistor (2N2222 / BC547 / S8050) -- recommended for beginners

Simplest wiring. GPIO HIGH = motor ON, GPIO LOW = motor OFF.
Works with any VCCIO setting (3.3V or 5V).

```
FT232R breakout
  CBUS0 ---[1k]--- Base      (NPN: 2N2222 / BC547 / S8050)
  5V    ---------- Motor (+)
                   Motor (-) --- Collector
                   Emitter   --- GND
  GND   ---------- GND
```

> **Beginner**: The transistor is just a remote-controlled switch. When CBUS0
> goes HIGH, a tiny signal current flows into the Base, and the transistor closes
> the path between Collector and Emitter -- letting real motor current flow from
> the 5V pin. When CBUS0 goes LOW, the switch opens and the motor stops.

> **Engineer**: Add a 1N4148 freewheeling diode across the motor terminals
> (cathode to motor+, anode to motor-) to clamp the back-EMF spike when the
> transistor switches off. Optional for a coin vibration motor; good practice for
> any inductive load.

---

#### Option B: PNP transistor (PN2907) -- inverted logic

Works equally well but the switching logic is reversed:
GPIO LOW = motor ON, GPIO HIGH = motor OFF.

**Requires VCCIO set to 5V** on your breakout board (see Voltage Selection above).
A 3.3V GPIO HIGH will not fully turn off the PN2907 with a 5V emitter supply;
the 10k pull-up resistor from 5V to Base solves this.

```
FT232R breakout  (VCCIO set to 5V)
  5V    ---[10k]---+--- Emitter   (PN2907 PNP)
                   |
  CBUS0 ---[1k]---'--- Base
                       Collector --- Motor (+)
                       Motor (-)  --- GND
  GND   -------------------------------- GND
```

> **Beginner**: A PNP transistor is wired "upside down" compared to NPN. The
> motor power comes in at the top (Emitter, connected to 5V). Pulling the Base
> LOW turns the motor ON; letting it go HIGH turns it OFF. This is the opposite
> of the NPN circuit above -- keep that in mind when writing your script.
>
> The 10k resistor between 5V and Base is essential. Without it, the 5V on the
> Emitter would partially turn the transistor on even when the GPIO pin is
> HIGH, and the motor would run weakly all the time.

> **Engineer**: The 10k/1k resistor divider ensures Vbe = 0V when GPIO is at 5V
> (both resistors see the same voltage), and Vbe = ~4.5V when GPIO is LOW --
> well into saturation. With 3.3V VCCIO the divider gives Vbe = ~1.5V on HIGH,
> which is above the 0.7V threshold and will partially conduct -- set VCCIO to
> 5V, or use the NPN circuit instead.

The PSGadget commands to control a PNP-switched motor (inverted logic):

```powershell
$dev = New-PsGadgetFtdi -SerialNumber "YOURSERIAL"
$dev.SetPins(@(0), 'LOW')   # GPIO LOW = motor ON  (PNP is inverted)
Start-Sleep -Seconds 2
$dev.SetPins(@(0), 'HIGH')  # GPIO HIGH = motor OFF
$dev.Close()
```

---

### Direct connection (sub-4mA loads only)

A direct wire from CBUS0 to the motor works only if the motor draws less than 4mA at
all times -- this includes startup inrush current. Most motors exceed this limit.

```
FT232R breakout
  CBUS0 ---[motor+]---[motor-]--- GND
```

If the motor does not spin with a direct connection even though
`Set-PsGadgetGpio` reports success and the pin reads the correct voltage unloaded,
the motor current exceeds the CBUS0 limit. Use the transistor circuit above.

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
$ee | Select-Object Cbus0, Cbus1, Cbus2, Cbus3,Cbus4
```

Factory default output:

```
Cbus0          Cbus1          Cbus2         Cbus3          Cbus4
-----          -----          -----         -----          -----
FT_CBUS_TXLED  FT_CBUS_RXLED  FT_CBUS_PWRON FT_CBUS_SLEEP  FT_CBUS_UNUSED
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

After writing, the function will display a prompt:

```
EEPROM written successfully.
The new CBUS pin settings will not take effect until the device re-enumerates on the USB bus.

You have two options:
  [Y] Cycle the USB port automatically right now (no cable unplug needed)
  [N] Unplug and replug the USB cable manually, then continue

Apply EEPROM Changes
Cycle the USB port now to apply the new settings?
[Y] Yes  [N] No  [?] Help (default is "Y"):
```

- **Press Y (or Enter)** to cycle the port automatically. No cable unplug required.
- **Press N** if you prefer to unplug and replug the USB cable manually.

> **Beginner**: Just press Enter (or Y) when prompted. The chip will briefly
> disconnect and reconnect on its own, and you will see a confirmation message
> when it is done. No need to touch the cable.

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
$dev = New-PsGadgetFtdi -SerialNumber "BG01B0I1"   # use your serial number

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

## Unattended / Scripted Setup

For unattended automation (CI pipelines, deployment scripts), use `-Confirm:$false` to
skip both the EEPROM write confirmation and the port-cycle prompt:

```powershell
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0) -Confirm:$false
```

This writes the EEPROM and cycles the port without any interactive prompts. The returned
object's `PortCycled` property will be `True` on success.

To cycle the port later from an already-connected device object:

```powershell
$dev = New-PsGadgetFtdi -Index 0
$dev.CyclePort()   # triggers USB re-enumeration; the device handle is released automatically
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

First confirm the pin is actually toggling (no motor connected):

```powershell
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State HIGH
# Probe CBUS0 to GND with a multimeter - should read ~5V
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State LOW
# Should read 0V
```

If voltage toggles correctly but motor still does not spin, the motor current
exceeds the 4mA CBUS0 limit. Use the transistor wiring (see Hardware Wiring section).

Other checks:
- Run `Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0` to confirm `FT_CBUS_IOMODE`
- Check the VCCIO jumper -- most boards default to 3.3V which may be too low
- Verify the transistor wiring:
  - NPN: 1k from CBUS0 to Base, motor between 5V and Collector, Emitter to GND
  - PNP (PN2907): 10k from 5V to Base, 1k from CBUS0 to Base, motor between Collector and GND, Emitter to 5V (requires VCCIO = 5V)

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
$dev = New-PsGadgetFtdi -Index 0   # connected immediately
Set-PsGadgetGpio -PsGadget $dev -Pins @(0) -State HIGH
$dev.Close()

# Transistor quick reference
# NPN (2N2222/BC547/S8050)  -- HIGH=ON, LOW=OFF, works at 3.3V or 5V VCCIO
#   CBUS0 -[1k]- Base | Collector - Motor(-) | Motor(+) - 5V | Emitter - GND
#
# PNP (PN2907)             -- LOW=ON, HIGH=OFF, requires VCCIO=5V
#   CBUS0 -[1k]- Base | 5V -[10k]- Base | Emitter - 5V | Collector - Motor(+) | Motor(-) - GND
```
