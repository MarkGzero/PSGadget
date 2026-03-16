# Example: Stepper Motor with SSD1306 Display (FT232H)

Drive a 28BYJ-48 stepper motor and show status on an SSD1306 OLED display —
both connected to the **same FT232H adapter** at the same time.

This works because the FT232H has two independent GPIO banks:

- **ADBUS D0/D1** — MPSSE I2C for the SSD1306 (SCL/SDA)
- **ACBUS C0-C3** — GPIO output for the stepper (IN1-IN4 via ULN2003)

The two banks are electrically independent and use different MPSSE commands,
so no mode switching is required. However, both banks share one USB endpoint —
**display writes must not be interleaved inside a stepper move** or the step
timing loop will stall during the I2C transaction. The correct pattern is:
write intent to display → execute full move → write confirmation.

> **Note**: This example requires an **FT232H**. The FT232R has only one GPIO
> bank (ADBUS, async bit-bang only) and cannot drive I2C, so the combined
> stepper + SSD1306 setup is not possible on FT232R.

---

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [What You Need](#what-you-need)
- [Hardware Wiring](#hardware-wiring)
  - [SSD1306 (ADBUS — MPSSE I2C)](#ssd1306-adbus--mpsse-i2c)
  - [Stepper via ULN2003 (ACBUS — GPIO)](#stepper-via-uln2003-acbus--gpio)
  - [Power](#power)
- [Step 1 - Load Module and Detect Device](#step-1---load-module-and-detect-device)
- [Step 2 - Connect and Verify Both Peripherals](#step-2---connect-and-verify-both-peripherals)
- [Step 3 - Display Splash and Confirm I2C](#step-3---display-splash-and-confirm-i2c)
- [Step 4 - Smoke Test the Stepper](#step-4---smoke-test-the-stepper)
- [Step 5 - Combined Move-and-Display Loop](#step-5---combined-move-and-display-loop)
  - [USB serialization constraint](#usb-serialization-constraint)
  - [Full rotation](#full-rotation)
  - [Bidirectional sweep](#bidirectional-sweep)
- [Complete Examples](#complete-examples)
  - [Example 1 - Single rotation with display](#example-1---single-rotation-with-display)
  - [Example 2 - Interactive jog with display feedback](#example-2---interactive-jog-with-display-feedback)
- [Display Layout Reference](#display-layout-reference)
- [Troubleshooting](#troubleshooting)
  - [Stepper does not move, display works](#stepper-does-not-move-display-works)
  - [Display is blank, stepper works](#display-is-blank-stepper-works)
  - [Both fail to initialize](#both-fail-to-initialize)
  - [Stepper pauses noticeably mid-move](#stepper-pauses-noticeably-mid-move)
  - [Stepper stalls mid-move](#stepper-stalls-mid-move)
- [Quick Reference (Pro)](#quick-reference-pro)

---

## Who This Is For

- **Beginner** — new to stepper motors and OLED displays; the tutorial walks
  through each piece before combining them.
- **Scripter** — comfortable with PowerShell; wants a reusable motion+display
  script for a small machine or fixture.
- **Engineer** — familiar with MPSSE and GPIO; interested in how PSGadget
  multiplexes both banks on a single D2XX handle without mode switching.
- **Pro** — skip to the [Quick Reference](#quick-reference-pro).

---

## What You Need

- **FT232H** USB adapter (must have MPSSE — verify `HasMpsse = True`)
- **SSD1306** 128×64 or 128×32 I2C OLED module
- **28BYJ-48** 5V geared stepper motor with **ULN2003** driver board
- 9 jumper wires (4 for I2C/power, 4 for stepper control, 1 shared GND)
- Separate 5V supply for the motor (USB 5V from the FT232H is fine for bench use)
- Windows PC with FTDI CDM D2XX drivers, USB cable
- PowerShell 5.1 or 7.x, PSGadget module cloned locally

> **Beginner**: The FT232H is a single USB chip that can speak I2C (via its
> MPSSE engine on the D-bank pins) and drive GPIO output (via its C-bank pins)
> at the same time. You do not need two adapters.

---

## Hardware Wiring

### SSD1306 (ADBUS — MPSSE I2C)

| FT232H pin | ADBUS signal | SSD1306 pin |
|------------|--------------|-------------|
| D0         | SCK / SCL    | SCL         |
| D1         | DO / SDA     | SDA         |
| 3.3V       | Power        | VCC         |
| GND        | Ground       | GND         |

> **Engineer**: ADBUS D0-D3 are owned by the MPSSE engine. D0 = SCL, D1 = SDA
> in 3-phase I2C mode (0x9E open-drain emulation). D2 and D3 are not used by
> the SSD1306 but must be left unconnected — do not wire the stepper to D2/D3.

### Stepper via ULN2003 (ACBUS — GPIO)

| FT232H pin | ACBUS signal | ULN2003 input | Coil  |
|------------|--------------|---------------|-------|
| C0         | ACBUS0       | IN1           | A     |
| C1         | ACBUS1       | IN2           | A'    |
| C2         | ACBUS2       | IN3           | B     |
| C3         | ACBUS3       | IN4           | B'    |
| GND        | Ground       | GND           | —     |

> **Beginner**: Do not connect motor wires directly to the FT232H. The ULN2003
> board is a current driver that sits between the FT232H and the motor coils.
> The FT232H C-bank pins are 3.3V logic; the ULN2003 accepts 3.3V inputs
> and drives the 5V motor coils on the other side.

> **Engineer**: ACBUS C0-C3 are driven by MPSSE SET_BITS_HIGH (0x82) independently of ADBUS. No mode switch or ResetDevice call is needed between stepper moves and I2C writes. However, both banks share the USB endpoint — I2C writes interleaved inside the stepper spin-wait loop will stall step timing. Always sequence: display write → full move → display write.

### Power

| Source     | Supplies          | Notes                              |
|------------|-------------------|------------------------------------|
| USB 5V     | FT232H adapter    | Via USB cable                      |
| USB 5V     | ULN2003 5V pin    | Take from adapter's 5V pin or hub  |
| FT232H 3.3V| SSD1306 VCC       | On-board regulator, max ~50mA      |

For bench use, a single USB port can supply both the FT232H and the motor via
the ULN2003 board's 5V input. For continuous or fast rotation, use a dedicated
5V/1A supply on the motor to avoid USB current limit.

---

## Step 1 - Load Module and Detect Device

```powershell
Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force -DisableNameChecking

Get-PsGadgetFtdi | Format-Table Index, Type, SerialNumber, HasMpsse
```

Expected:

```text
Index  Type    SerialNumber  HasMpsse
-----  ----    ------------  --------
  0    FT232H  FT4ABCDE      True
```

You need `HasMpsse = True`. If you see `FT232R` or `HasMpsse = False`, that
device cannot drive the SSD1306 over I2C.

---

## Step 2 - Connect and Verify Both Peripherals

```powershell
# 128x64 display (default)
$dev = New-PsGadgetFtdi -Index 0

# 128x32 display — must specify height
# $dev = New-PsGadgetFtdi -Index 0 -DisplayHeight 32

if (-not $dev.IsOpen) {
    Write-Error "Failed to open device. Check USB connection and index."
    return
}

Write-Host ("Connected: {0} [{1}]" -f $dev.Description, $dev.SerialNumber)

# Confirm SSD1306 is visible on the I2C bus
$scan = $dev.ScanI2CBus()
$scan | Format-Table

if (-not ($scan | Where-Object Address -eq 0x3C)) {
    Write-Warning "SSD1306 not found at 0x3C — check VCC, GND, SCL, SDA wiring."
}
```

> **Scripter**: Use `-SerialNumber` instead of `-Index` in production scripts so the reference stays stable when USB hub enumeration order changes:
>
> ```powershell
> $dev = New-PsGadgetFtdi -SerialNumber "FT4ABCDE"
> ```

---

## Step 3 - Display Splash and Confirm I2C

```powershell
$d = $dev.GetDisplay()
$d.Initialize($false)
$d.ShowSplash()   # border + "PsGadget" for 3 seconds
```

If you see the splash screen, I2C is working end-to-end. If the display stays
blank, fix the SSD1306 wiring before continuing — the stepper will still work,
but the combined example will not.

---

## Step 4 - Smoke Test the Stepper

With the device still open, test stepper motion using the existing `$dev`
object. The device stays open after the call when `-PsGadget` is used.

```powershell
# 512 half-steps forward (about 45 degrees) at 2ms/step
Invoke-PsGadgetStepper -PsGadget $dev -Steps 512 -AcBus
```

The motor should rotate smoothly. Coils are de-energized automatically after
each move so the motor does not overheat at rest.

> **Beginner**: If the motor hums but does not turn, the coil sequence is
> running but the motor is stalling. Try a slower speed: add `-DelayMs 4` to
> the `Invoke-PsGadgetStepper` call.

---

## Step 5 - Combined Move-and-Display Loop

### USB serialization constraint

ADBUS (I2C) and ACBUS (stepper) are electrically independent, but both banks
share the **same USB endpoint**. Every `Device.Write()` call — whether a
3-byte MPSSE step command or a 130-byte I2C data write — is serialized through
the same USB pipe.

An I2C display write (~20-30ms, 3-4 USB round-trips) issued while the stepper
spin-wait loop is running will block the loop for the duration of the
transaction, causing the step timing to stall.

**Rule**: display writes must never be interleaved inside a stepper move.

The correct structure for every combined operation:

```powershell
# 1. Write intent to display (before move)
$d.WriteText(">> Forward / 360 deg", 2, 'center', 1, $false)

# 2. Execute the full move uninterrupted
Invoke-PsGadgetStepper -PsGadget $dev -Steps $total -Direction Forward -AcBus

# 3. Write confirmation (after move completes)
$d.WriteText("Done", 2, 'center', 1, $false)
```

### Full rotation

```powershell
$d = $dev.GetDisplay()
$dev.ClearDisplay()

$spr   = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half   # ~4075.77
$total = [int][Math]::Round($spr)   # one full revolution

# 1. Show intent before moving
$d.WriteText("STEPPER",     0, 'center', 1, $false)
$d.WriteText(">> Forward",  2, 'center', 1, $false)
$d.WriteText("360 deg",     4, 'center', 2, $false)

# 2. Full uninterrupted move
Invoke-PsGadgetStepper -PsGadget $dev -Steps $total -Direction Forward -AcBus

# 3. Confirm completion
$dev.ClearDisplay(2)
$d.WriteText("Done",    2, 'center', 1, $false)
```

### Bidirectional sweep

```powershell
$d = $dev.GetDisplay()
$dev.ClearDisplay()
$d.WriteText("STEPPER", 0, 'center', 1, $false)

$spr      = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half
$quarter  = [int][Math]::Round($spr / 4)   # 90 degrees

foreach ($sweep in @(
    @{ Dir = 'Forward'; Label = '>> Forward'; Angle = '+90 deg' },
    @{ Dir = 'Reverse'; Label = '<< Reverse'; Angle = '-90 deg' },
    @{ Dir = 'Forward'; Label = '>> Forward'; Angle = '+90 deg' },
    @{ Dir = 'Reverse'; Label = '<< Reverse'; Angle = '-90 deg' }
)) {
    $dev.ClearDisplay(2)
    $dev.ClearDisplay(4)
    $dev.ClearDisplay(5)
    $d.WriteText($sweep.Label, 2, 'center', 1, $false)
    $d.WriteText($sweep.Angle, 4, 'center', 2, $false)

    Invoke-PsGadgetStepper -PsGadget $dev -Steps $quarter -Direction $sweep.Dir -AcBus

    Start-Sleep -Milliseconds 300   # brief pause at end of each leg
}

$dev.ClearDisplay()
$d.WriteText("Done", 3, 'center', 1, $false)
```

---

## Complete Examples

### Example 1 - Single rotation with display

Clean version, no extra output. Errors surface via `Write-Error`.

```powershell
#Requires -Version 5.1

Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force -DisableNameChecking

$dev = New-PsGadgetFtdi -Index 0
if (-not $dev.IsOpen) { Write-Error "Failed to open device."; return }

try {
    # Verify I2C bus
    $scan = $dev.ScanI2CBus()
    if (-not ($scan | Where-Object Address -eq 0x3C)) {
        Write-Warning "SSD1306 not found at 0x3C. Check wiring."
        $scan | Format-Table
    }

    $d = $dev.GetDisplay()
    $d.ShowSplash()

    $spr   = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half
    $total = [int][Math]::Round($spr)

    # Show intent before moving — no display writes during the move
    $dev.ClearDisplay()
    $d.WriteText("STEPPER",    0, 'center', 1, $false)
    $d.WriteText(">> Forward", 2, 'center', 1, $false)
    $d.WriteText("360 deg",    4, 'center', 2, $false)

    Invoke-PsGadgetStepper -PsGadget $dev -Steps $total -Direction Forward -AcBus

    # Confirm completion
    $dev.ClearDisplay(2)
    $d.WriteText("Done", 2, 'center', 1, $false)

} finally {
    $dev.Close()
    Write-Host "Device closed."
}
```

---

### Example 2 - Interactive jog with display feedback

Prompts the user for an angle and direction, moves the motor, and shows the
cumulative position on the display. Press Ctrl+C to exit.

```powershell
#Requires -Version 5.1

Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force -DisableNameChecking

$dev = New-PsGadgetFtdi -Index 0
if (-not $dev.IsOpen) { Write-Error "Failed to open device."; return }

try {
    $d = $dev.GetDisplay()
    $d.ShowSplash()
    $dev.ClearDisplay()
    $d.WriteText("JOG MODE", 0, 'center', 1, $false)

    $spr      = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half
    $position = 0.0   # cumulative degrees

    while ($true) {
        $input = Read-Host "Enter degrees (+forward / -reverse), or Q to quit"
        if ($input -eq 'Q' -or $input -eq 'q') { break }

        $deg = [double]$input
        $dir = if ($deg -ge 0) { 'Forward' } else { 'Reverse' }
        $absDeg = [Math]::Abs($deg)
        $steps  = [int][Math]::Round($absDeg / 360.0 * $spr)

        if ($steps -lt 1) {
            Write-Warning "Too small — minimum is 1 step (~0.09 degrees)"
            continue
        }

        # Update display before moving
        $dev.ClearDisplay(2)
        $dev.ClearDisplay(4)
        $dev.ClearDisplay(5)
        $dirLabel = if ($dir -eq 'Forward') { ">> Forward" } else { "<< Reverse" }
        $d.WriteText($dirLabel, 2, 'center', 1, $false)
        $d.WriteText(("{0} deg" -f $absDeg), 4, 'center', 2, $false)

        Invoke-PsGadgetStepper -PsGadget $dev -Steps $steps -Direction $dir -AcBus

        # Update cumulative position
        $position += $deg
        $posLabel = ("Pos: {0:F1} deg" -f $position)

        $dev.ClearDisplay(6)
        $dev.ClearDisplay(7)
        $d.WriteText($posLabel, 6, 'center', 1, $false)

        Write-Host ("Moved {0} deg {1}. Cumulative: {2:F1} deg" -f $absDeg, $dir, $position)
    }

    $dev.ClearDisplay()
    $d.WriteText("Done", 3, 'center', 1, $false)

} finally {
    $dev.Close()
    Write-Host "Device closed."
}
```

---

## Display Layout Reference

Layout used by the combined examples (128×64, 8 pages):

| Page | Pixels  | Content                         |
|------|---------|---------------------------------|
| 0    | 0–7     | Title / mode label              |
| 1    | 8–15    | (spare)                         |
| 2    | 16–23   | Direction arrow or status       |
| 3    | 24–31   | (spare)                         |
| 4    | 32–39   | Current angle — FontSize 2 top  |
| 5    | 40–47   | Current angle — FontSize 2 bot  |
| 6    | 48–55   | Cumulative position             |
| 7    | 56–63   | (spare / footer)                |

FontSize 2 occupies **two consecutive pages** (N and N+1). Always clear both
before rewriting:

```powershell
$dev.ClearDisplay(4)
$dev.ClearDisplay(5)
$d.WriteText("90.0 deg", 4, 'center', 2, $false)
```

For 128×32 displays (4 pages only), use this layout instead:

| Page | Content                         |
|------|---------------------------------|
| 0    | Title                           |
| 1    | Direction / status              |
| 2    | Angle — FontSize 2 top          |
| 3    | Angle — FontSize 2 bottom       |

---

## Troubleshooting

### Stepper does not move, display works

- Confirm ACBUS C0-C3 wires are seated: check at both the FT232H breakout and
  the ULN2003 IN1-IN4 header.
- Run the smoke test independently:

  ```powershell
  Invoke-PsGadgetStepper -PsGadget $dev -Steps 512 -AcBus
  ```

- Check the log:

  ```powershell
  Get-PsGadgetLog | Select-Object -Last 20
  ```

  Look for `StepperMove` entries. `stub: no Device handle` means the C-bank
  GPIO path is not active.
- Verify the ULN2003 board has 5V power on its supply pin.
- Try `-DelayMs 4` — the motor may be stalling at the default 2ms interval if
  supply voltage is marginal.

### Display is blank, stepper works

- Run `$dev.ScanI2CBus()`. If no addresses appear, the I2C bus is dead — check
  VCC (3.3V) and GND on the SSD1306 first.
- Confirm D0 = SCL and D1 = SDA. Swapping them is the most common wiring error.
- Check the I2C mode switch on your FT232H breakout (some boards have a
  physical switch labeled **I2C** that must be in the ON position).
- If `ScanI2CBus()` finds 0x3D instead of 0x3C, the ADDR pin on your module is
  pulled high. Pass `-I2CAddress 0x3D` or use `$dev.Display("text", 0, 0x3D)`.

### Both fail to initialize

- Another process holds the D2XX handle. Close any PuTTY/TeraTerm sessions
  and call `$dev.Close()` if a previous session was left open.
- Unplug and replug the USB cable, then reconnect.
- Verify `Get-PsGadgetFtdi | Format-Table HasMpsse` shows `True`.

### Stepper pauses noticeably mid-move

Symptom: motor rotation is jerky or stutters at regular intervals.

**Cause**: display writes are happening inside the stepper move (e.g. in a
chunk loop that updates the display between each chunk). Each I2C write blocks
the USB endpoint for ~20-30ms, stalling the step timing loop.

**Fix**: move all display writes outside the `Invoke-PsGadgetStepper` call.
Write intent before, run the full move, write confirmation after. See
[USB serialization constraint](#usb-serialization-constraint).

### Stepper stalls mid-move

The motor stops before completing the requested move, usually due to one of:

1. **Insufficient voltage** — the ULN2003 5V rail is drooping under load.
   Use a dedicated 5V/1A supply instead of USB.
2. **Too fast** — increase `-DelayMs` from 2 to 3 or 4.
3. **Coil sequence wrong** — if you wired IN1-IN4 in a different order than
   C0-C3, the coil phases will be out of sequence and the motor will shudder.
   Check that C0→IN1, C1→IN2, C2→IN3, C3→IN4.

---

## Quick Reference (Pro)

```powershell
# Load and connect (FT232H required)
Import-Module .\PSGadget.psd1 -DisableNameChecking
$dev = New-PsGadgetFtdi -Index 0               # 128x64 (default)
$dev = New-PsGadgetFtdi -Index 0 -DisplayHeight 32   # 128x32

# Scan I2C bus — confirm SSD1306 visible
$dev.ScanI2CBus() | Format-Table

# Display helpers
$d = $dev.GetDisplay()
$d.ShowSplash()                                    # visual init check
$dev.ClearDisplay()                                # clear all pages
$dev.ClearDisplay(3)                               # clear one page
$d.WriteText("Hello",  0, 'center', 1, $false)     # FontSize 1: 6x8
$d.WriteText("90 deg", 4, 'center', 2, $false)     # FontSize 2: 12x16 (pages 4+5)

# Invoke-PsGadgetI2C public API
Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 -Clear
Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 -Text "Hello" -Page 0 -Align center
Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 -Text "90 deg" -Page 4 -Align center -FontSize 2

# Stepper — always add -AcBus when using alongside SSD1306 (ACBUS C0-C3)
Invoke-PsGadgetStepper -PsGadget $dev -Steps 1000            -AcBus
Invoke-PsGadgetStepper -PsGadget $dev -Degrees 180 -Direction Reverse -AcBus
Invoke-PsGadgetStepper -PsGadget $dev -Degrees 90  -StepMode Full -DelayMs 3 -AcBus

# Calibration constant
$spr = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half   # ~4075.77

# Close
$dev.Close()
```
