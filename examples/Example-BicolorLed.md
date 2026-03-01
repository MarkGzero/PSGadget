# Example: Bi-Color LED Control via FT232R CBUS GPIO

Drive a 3-leg common cathode bi-color LED (red + green) using the CBUS GPIO pins
on an FT232R USB-to-serial chip with PSGadget.

---

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [What You Need](#what-you-need)
- [Hardware Background](#hardware-background)
  - [Wiring diagram](#wiring-diagram)
  - [Why you need the resistors](#why-you-need-the-resistors-and-why-the-led-glows-dim-without-them)
- [CBUS pin state at startup](#cbus-pin-state-at-startup----why-the-red-led-glows-before-you-say-so)
- [A note on independent LED control](#a-note-on-independent-led-control-one-high-one-low)
- [Step 1 - Install Drivers and Verify Detection](#step-1---install-drivers-and-verify-detection)
- [Step 2 - Inspect Current EEPROM State](#step-2---inspect-current-eeprom-state)
- [Step 3 - Program EEPROM (One Time Per Device)](#step-3---program-eeprom-one-time-per-device)
- [Step 4 - Verify EEPROM After Replug](#step-4---verify-eeprom-after-replug)
- [Step 5 - Runtime LED Control](#step-5---runtime-led-control)
  - [OOP style (recommended for scripts)](#oop-style-recommended-for-scripts)
  - [Independent control without glitch (advanced)](#independent-control-without-glitch-advanced)
  - [Blink pattern (quick cmdlet style)](#blink-pattern-quick-cmdlet-style)
- [CBUS Pin Map](#cbus-pin-map)
- [Troubleshooting](#troubleshooting)
  - [LED glows dim when it should be fully off](#led-glows-dim-when-it-should-be-fully-off)
  - [One LED glows dim when the other is on](#one-led-glows-dim-when-the-other-is-on)
  - [FT_DEVICE_NOT_FOUND](#ft_device_not_found)
  - [LED does not light at all on HIGH](#led-does-not-light-at-all-on-high)
  - [Both LEDs stay on after the script ends](#both-leds-stay-on-after-the-script-ends)
- [Quick Reference (Pro)](#quick-reference-pro)

---

## Who This Is For

This walkthrough is written with four readers in mind. Look for the labeled callouts
throughout to find the depth that matches your background.

- **Beginner** - new to microcontrollers, USB hardware, and PowerShell
- **Scripter** - comfortable with PowerShell scripting, new to hardware GPIO / FTDI
- **Engineer** - studied basic electronics, less familiar with the Windows driver and PowerShell module concepts
- **Pro** - experienced with both; skip to the Quick Reference at the bottom

---

## What You Need

- An FT232R or FT232RNL USB breakout board (Waveshare USB-TO-TTL-FT232, SparkFun, etc.)
- A 3-leg common cathode bi-color LED (red + green)
- Two 1k ohm resistors (current limiting, one per LED leg)
- Breadboard and jumper wires
- Windows PC with FTDI CDM drivers installed, USB cable
- PowerShell 5.1 or later
- PSGadget module cloned locally

> **Beginner**: A bi-color LED is two LEDs in one package. It has three legs: one for red,
> one for green, and a shared ground (the cathode). The longest leg is usually the common
> cathode -- connect it to GND. The two shorter legs each connect to a CBUS pin through a
> resistor.

---

## Hardware Background

> **Engineer**: The FT232R CBUS pins are push-pull outputs rated at approximately 4 mA
> maximum source current at VCCIO. A common cathode LED package places both LED anodes
> on separate pins and joins both cathodes at a common GND terminal. The red and green
> dies have different forward voltages (V_F approx 2.0V and 2.2V respectively), so use
> a separate series resistor on each leg to hold current at a safe level regardless of V_F
> variation.
>
> Resistor sizing: (V_CBUS_HIGH - V_F) / I_target = (5V - 2V) / 3mA = 1k.
> 1k ohm resistors keep both legs well within the 4mA CBUS limit at 5V VCCIO.

### Wiring diagram

```
FT232R breakout
  CBUS0 ---[1k resistor]--- RED   anode  (3-leg LED, pin 1)
  CBUS1 ---[1k resistor]--- GREEN anode  (3-leg LED, pin 2)
                            Common cathode (3-leg LED, pin 3) --- GND
  GND   -------------------- GND rail
```

The 3-leg LED middle pin is almost always the common cathode (longest leg on a T1-3/4
through-hole package). Confirm with your datasheet -- if it is not the middle leg, test
with a 3V coin cell through a 1k resistor before installing it in the breadboard.

> **Beginner**: Wire the longest leg of the LED to GND. Run one short wire from CBUS0
> through a 1k resistor to the first short leg, and another from CBUS1 through a second
> 1k resistor to the remaining short leg.

### Why you need the resistors (and why the LED glows dim without them)

Without a series resistor there is no defined off-state impedance. When the CBUS pin is
driven HIGH, the LED and pin's low output impedance (roughly 50 ohm internal) set the
current far above 4 mA, potentially damaging the pin. When the pin is driven LOW, the
circuit should be off -- but there is a window at startup (see next section) where the
CBUS pin floats, and without a resistor even a small floating voltage can forward-bias
the LED visibly.

A 1k resistor limits runtime current to about 3 mA (safe and bright enough) and ensures
that any residual floating voltage during initialization cannot push enough current to
visibly illuminate the LED.

---

## CBUS pin state at startup -- why the red LED glows before you say so

This is the most common confusion when first driving LEDs from CBUS pins.

When you run `Connect-PsGadgetFtdi` or `New-PsGadgetFtdi`, the
D2XX driver opens the device handle but does **not** call `SetBitMode` until the first
`Set-PsGadgetGpio` command arrives. Until that moment, CBUS pins programmed as
`FT_CBUS_IOMODE` in the EEPROM are floating -- the FT232R's internal weak pull-up
resistors hold them loosely near VCCIO, causing both LEDs to glow at partial intensity.

**How to prevent it:** immediately after connecting, drive all LED pins LOW in a single
initialization call. This is the first line of every script in this example.

```powershell
$conn = Connect-PsGadgetFtdi -SerialNumber "BG01X3GX"

# Drive both pins LOW immediately -- eliminates the floating-pin glow
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW
```

> **Scripter**: The `SetBitMode(mask, 0x20)` call inside PSGadget sends a single byte that
> sets both direction (output/input) and logic value for all four CBUS pins simultaneously.
> Passing `-Pins @(0, 1) -State LOW` builds the mask with CBUS0 and CBUS1 as outputs,
> both LOW. Pins not listed (CBUS2, CBUS3) are left as inputs with no effect.

> **Engineer**: `SetBitMode(0x30, 0x20)` -- direction nibble 0x3 (CBUS0 + CBUS1 as outputs),
> value nibble 0x0 (both LOW). CBUS2 and CBUS3 bits are zero, leaving them as high-Z inputs.
> The full mask byte is `(dir_nibble << 4) | val_nibble`.

---

## A note on independent LED control (one HIGH, one LOW)

Each `SetBitMode(0x20)` call replaces the direction and value for all four CBUS pins
atomically. This means:

- `Set-PsGadgetGpio -Pins @(0) -State HIGH` --> CBUS0=output HIGH, CBUS1=input (floating)
- `Set-PsGadgetGpio -Pins @(1) -State LOW`  --> CBUS1=output LOW, CBUS0=input (floating!)

The second call silently makes CBUS0 an input again. The red LED goes dim between the
two calls because CBUS0 is momentarily floating.

**The correct pattern for independent LED states is to always include all active output
pins in the direction mask.** Use `Set-FtdiCbusBits` with `-OutputPins` to declare
all output pins while controlling only the ones that change value:

```powershell
# Red ON, Green OFF -- direction covers both pins, value covers only CBUS0
Set-FtdiCbusBits -Connection $conn -Pins @(0) -State HIGH -OutputPins @(0, 1)
```

> **Beginner**: Think of each `Set-PsGadgetGpio` call as telling the chip the complete
> state for all controlled pins at once, not just the one or two you mention. If you do
> not mention a pin, the chip sets it to floating (which for an LED can look like a dim
> glow). Always include both LED pins in every call.

Because the current public API (`Set-PsGadgetGpio`) sends a single state to all listed
pins, the safest workaround for "one on, one off" without intermediate glitches is to
call the lower-level function `Set-FtdiCbusBits` directly with the `-OutputPins`
parameter, or to structure scripts so you control both pins in bulk operations (both HIGH,
both LOW, blink sequences):

```powershell
# Bulk operations through the public cmdlet work cleanly
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State HIGH  # both on
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW   # both off
Set-PsGadgetGpio -Connection $conn -Pins @(0)    -State HIGH  # red only (green floats)
```

For precise individual-pin control with the other pin held at a defined level, use
`Set-FtdiCbusBits` directly (see the Quick Reference section).

---

## Step 1 - Install Drivers and Verify Detection

FTDI provides a CDM (Combined Driver Model) package that installs both the VCP serial
driver and the D2XX library simultaneously.

> **Beginner**: Before PSGadget can talk to the FT232R, Windows needs a driver -- a small
> program that lets it understand the USB device. The FTDI CDM package installs everything
> you need in one step.

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

The D2XX row (no "A" suffix, no COM port) is the one PSGadget uses. Note its **Index**.

> **Pro**: `List-PsGadgetFtdi | Where-Object Driver -eq 'ftd2xx.dll'` to filter directly.

---

## Step 2 - Inspect Current EEPROM State

Read the current CBUS pin configuration before making any changes.

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

If both CBUS0 and CBUS1 already show `FT_CBUS_IOMODE`, the device was already programmed
and you can skip to Step 4.

> **Engineer**: Factory CBUS assignments route pins to internal signal generators (Tx/Rx
> LED blink, power-on active-low, sleep indicator). These cannot be overridden at runtime
> by D2XX SetBitMode -- the EEPROM must be rewritten to switch a pin to IOMODE first.

---

## Step 3 - Program EEPROM (One Time Per Device)

Program both CBUS0 and CBUS1 to GPIO mode. You only need to do this once per device.

Preview with no changes (safe):

```powershell
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0, 1) -WhatIf
```

Write the EEPROM:

```powershell
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0, 1)
```

Expected output:

```
EEPROM written successfully.
The new CBUS pin settings will not take effect until the device re-enumerates.

Apply EEPROM Changes
Cycle the USB port now to apply the new settings?
[Y] Yes  [N] No  [?] Help (default is "Y"):
```

Press Enter (or Y) to cycle the port automatically. No cable unplug required.

> **Beginner**: This writes new settings to a tiny persistent memory inside the chip.
> Press Enter when prompted -- the chip briefly disconnects and reconnects by itself.
> You will see a confirmation message when it is done.

> **Engineer**: The FT232R EEPROM is 128 x 16-bit. CBUS mode fields sit in words 0x18-0x1A.
> The write endurance is approximately 10,000 cycles; as a one-time setup step this is
> not a practical concern.

---

## Step 4 - Verify EEPROM After Replug

Confirm both CBUS0 and CBUS1 are now in GPIO mode:

```powershell
Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3
```

Expected result:

```
Cbus0           Cbus1           Cbus2           Cbus3
-----           -----           -----           -----
FT_CBUS_IOMODE  FT_CBUS_IOMODE  FT_CBUS_PWRON   FT_CBUS_SLEEP
```

---

## Step 5 - Runtime LED Control

With the EEPROM programmed and the resistors in place, you can now switch the LEDs.

### OOP style (recommended for scripts)

```powershell
Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force

# Create device object using serial number (stable across USB port changes)
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"   # use your serial number

try {
    # ---- Critical: initialize both pins LOW before anything else ----
    # This prevents the floating-pin glow that occurs before the first SetBitMode call.
    $dev.SetPins(@(0, 1), 'LOW')

    # Both LEDs off (already done above, shown for clarity)
    $dev.SetPins(@(0, 1), 'LOW')
    Write-Host "Both off"
    Start-Sleep -Seconds 1

    # Red only
    $dev.SetPins(@(0, 1), 'LOW')   # ensure known state first
    $dev.SetPins(@(0), 'HIGH')     # CBUS0 HIGH -- note: CBUS1 goes hi-Z here
    Write-Host "Red on"            # green may flicker; see note below for clean control
    Start-Sleep -Seconds 1

    # Green only
    $dev.SetPins(@(0, 1), 'LOW')   # both LOW to clear residual red
    $dev.SetPins(@(1), 'HIGH')     # CBUS1 HIGH
    Write-Host "Green on"
    Start-Sleep -Seconds 1

    # Both on (amber/yellow on many bi-color LEDs)
    $dev.SetPins(@(0, 1), 'HIGH')
    Write-Host "Both on"
    Start-Sleep -Seconds 1

    # Return to off
    $dev.SetPins(@(0, 1), 'LOW')
    Write-Host "Both off"

} finally {
    $dev.SetPins(@(0, 1), 'LOW')   # ensure LEDs are off before closing
    $dev.Close()
}
```

### Independent control without glitch (advanced)

When you need to hold one LED at a steady state while toggling the other, use
`Set-FtdiCbusBits` directly. The `-OutputPins` parameter declares the full direction
mask independently from which pins change value:

```powershell
$conn = Connect-PsGadgetFtdi -SerialNumber "BG01X3GX"

# Initialize -- both as outputs, both LOW
Set-FtdiCbusBits -Connection $conn -Pins @(0, 1) -State LOW

# Red ON, Green OFF -- both pins declared as outputs; only CBUS0 is in the value mask
Set-FtdiCbusBits -Connection $conn -Pins @(0) -State HIGH -OutputPins @(0, 1)
Write-Host "Red on, Green off"
Start-Sleep -Seconds 2

# Green ON, Red OFF
Set-FtdiCbusBits -Connection $conn -Pins @(1) -State HIGH -OutputPins @(0, 1)
Write-Host "Green on, Red off"
Start-Sleep -Seconds 2

# Both off
Set-FtdiCbusBits -Connection $conn -Pins @(0, 1) -State LOW
Write-Host "Both off"

$conn.Close()
```

> **Scripter**: `-OutputPins @(0, 1)` sets bits 4 and 5 of the CBUS mask byte to 1
> (both CBUS0 and CBUS1 are outputs), regardless of which pins are in `-Pins`. This
> matches what the hardware needs: direction must be maintained for both pins on every
> `SetBitMode` call, or the unmentioned pin reverts to a high-impedance input.

> **Engineer**: `Set-FtdiCbusBits -Pins @(0) -State HIGH -OutputPins @(0,1)` builds mask
> `0x31` -- direction=0b0011 (CBUS0+1 output), value=0b0001 (CBUS0 HIGH, CBUS1 LOW).
> `Set-FtdiCbusBits -Pins @(1) -State HIGH -OutputPins @(0,1)` builds `0x32` -- same
> direction, CBUS1 HIGH, CBUS0 LOW. Both pins remain as outputs throughout.

### Blink pattern (quick cmdlet style)

```powershell
$conn = Connect-PsGadgetFtdi -Index 0

# Init
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW

# Alternate blink using DurationMs
for ($i = 0; $i -lt 5; $i++) {
    Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH -DurationMs 300  # red pulse
    Set-PsGadgetGpio -Connection $conn -Pins @(1) -State HIGH -DurationMs 300  # green pulse
}

Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW
$conn.Close()
```

---

## CBUS Pin Map

| `-Pins` value | CBUS signal | FT232R physical pin | LED leg in this example |
|---|---|---|---|
| 0 | CBUS0 | Pin 23 | Red anode (via 1k resistor) |
| 1 | CBUS1 | Pin 22 | Green anode (via 1k resistor) |
| - | Common cathode | - | GND |

---

## Troubleshooting

### LED glows dim when it should be fully off

The pin is floating (no `SetBitMode` has been sent yet). Add this line immediately after
connecting and before any individual pin calls:

```powershell
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW
```

If the glow persists after that call, check:
- Is a 1k resistor in series on each LED leg? Without a resistor, trace leakage can dim
  an LED even with a theoretically-zero drive voltage.
- Is the VCCIO jumper set to 5V? Boards defaulting to 3.3V sometimes have unexpected
  behavior when driving LEDs near the forward voltage threshold.

### One LED glows dim when the other is on

You called `Set-PsGadgetGpio -Pins @(0) -State HIGH` which left CBUS1 as a floating
input. The floating pin wanders near the LED forward voltage causing a dim glow.
Use `Set-FtdiCbusBits` with `-OutputPins @(0, 1)` to keep both pins as defined outputs,
or always send both pins with the same state (`-Pins @(0,1)`) and structure your script
around bulk transitions.

### "FT_DEVICE_NOT_FOUND"

You are using the VCP index instead of the D2XX index. Run:

```powershell
List-PsGadgetFtdi | Where-Object Driver -eq "ftd2xx.dll" | Format-Table Index, SerialNumber
```

Use one of those Index values.

### LED does not light at all on HIGH

- Check the VCCIO jumper -- many boards default to 3.3V
- Verify both CBUS0 and CBUS1 show `FT_CBUS_IOMODE` in EEPROM
- Confirm the LED is common cathode (not common anode) with a coin cell and 1k resistor
  before inserting in the breadboard

### Both LEDs stay on after the script ends

The D2XX handle was closed while pins were HIGH. Add a finally block:

```powershell
try {
    # your LED code here
} finally {
    Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW
    $conn.Close()
}
```

---

## Quick Reference (Pro)

```powershell
# Enumerate (D2XX only)
List-PsGadgetFtdi | Where-Object Driver -eq "ftd2xx.dll" | Format-Table

# EEPROM read
Get-PsGadgetFtdiEeprom -Index 0 | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

# EEPROM write -- CBUS0 and CBUS1 to GPIO (one time)
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0, 1)

# Connect and initialize
$conn = Connect-PsGadgetFtdi -SerialNumber "BG01X3GX"
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW   # init -- kills floating glow

# Bulk state (public cmdlet -- both pins same state)
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State HIGH  # both on
Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW   # both off
Set-PsGadgetGpio -Connection $conn -Pins @(0)    -State HIGH  # red on (green hi-Z)

# Independent state (Set-FtdiCbusBits -- both pins held as outputs)
Set-FtdiCbusBits -Connection $conn -Pins @(0) -State HIGH -OutputPins @(0, 1)  # red on, green off
Set-FtdiCbusBits -Connection $conn -Pins @(1) -State HIGH -OutputPins @(0, 1)  # green on, red off
Set-FtdiCbusBits -Connection $conn -Pins @(0, 1) -State LOW                    # both off

# Timed pulse
Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH -DurationMs 500  # red 500ms then auto-off

# OOP
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"   # connected immediately
$dev.SetPins(@(0, 1), 'LOW')    # init
$dev.SetPins(@(0), 'HIGH')      # red on
$dev.SetPins(@(1), 'HIGH')      # green on
$dev.SetPins(@(0, 1), 'LOW')    # both off
$dev.Close()
```
