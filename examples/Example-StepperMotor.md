# Example: Stepper Motor Control with FT232RNL and ULN2003

Drive a 5V geared stepper (28BYJ-48 or similar) via the KS0327/ULN2003 driver
board using the CBUS GPIO pins on an FT232RNL USB serial adapter. This
walkthrough covers hardware wiring, EEPROM setup, basic testing, and full
revolution / precise-angle motion scripts.

---

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [What You Need](#what-you-need)
- [Hardware Background](#hardware-background)
  - [Wiring](#wiring)
  - [Coil sequencing](#coil-sequencing)
  - [Power considerations](#power-considerations)
- [Step 1 - Install Drivers and Verify Detection](#step-1---install-drivers-and-verify-detection)
- [Step 2 - Program CBUS EEPROM (one-time)](#step-2---program-cbus-eeprom-one-time)
- [Step 3 - Verify GPIO Availability](#step-3---verify-gpio-availability)
- [Step 4 - Rapid Smoke Test](#step-4---rapid-smoke-test)
- [Step 5 - Precise Motion Script](#step-5---precise-motion-script)
  - [Half-step function](#half-step-function)
  - [Rotate by degrees](#rotate-by-degrees)
- [Troubleshooting](#troubleshooting)
  - [Motor does not move](#motor-does-not-move)
  - [Only one coil energizes](#only-one-coil-energizes)
  - [Stepper shudders or stalls](#stepper-shudders-or-stalls)
- [Quick Reference (Pro)](#quick-reference-pro)

---

## Who This Is For

This example is written for:

- **Beginner** – new to USB GPIO and stepper motors; the tutorial explains the
  wiring and code in simple terms.
- **Scripter** – comfortable with PowerShell, wants a reusable script to move a
  stepper precise distances.
- **Engineer** – interested in coil sequencing and timing; may adapt the
  patterns for another motor/driver.
- **Pro** – skip to the Quick Reference section for the code snippets.

---

## What You Need

- FTDI USB‑to‑serial adapter with GPIO capability.
  * For FT232R/FT232RNL boards use the on‑board CBUS pins (0‑3) and make sure
    the board’s VCCIO jumper is set to **5 V** (not 3.3 V) before proceeding –
    the ULN2003 inputs require full‑scale logic and the motor supply may also
    be taken from the same 5 V rail.
  * For FT232H (or any MPSSE device) use ACBUS0‑3 instead; no EEPROM step is
    required and the outputs are already 5 V if you set VCCIO accordingly.
- KS0327 "Keyestudio" ULN2003 stepper motor driver board (or generic
  ULN2003‑based module) with 5‑wire 28BYJ‑48 stepper attached.
- 5 V power supply capable of ≥500 mA for the motor (USB 5 V is fine if you
  don't power the FTDI adapter from 5 V at the same time).
- Jumper wires and a breadboard or loosely wired harness.
- Windows PC with FTDI D2XX drivers installed (or Linux with libftd2xx).
- PowerShell 5.1+ and the PSGadget module cloned locally.

> **Engineer**: The ULN2003 board inverts the logic – a high on an input
> pin pulls the corresponding coil current through the Darlington array to
> ground. Our CBUS pins will therefore behave as positive logic sources.

---

## Hardware Background

### Wiring

| FT232RNL pin | CBUS signal | ULN2003 input | Significance |
|-------------|-------------|---------------|--------------|
| CBUS0        | `CBUS0`     | `IN1`         | Coil A        |
| CBUS1        | `CBUS1`     | `IN2`         | Coil A'       |
| CBUS2        | `CBUS2`     | `IN3`         | Coil B        |
| CBUS3        | `CBUS3`     | `IN4`         | Coil B'       |
| 5 V USB      |             | `5 V`         | Motor supply  |
| GND          |             | `GND`         | Common ground |

> **Beginner**: do **not** connect the motor wires directly to the FTDI
> board. The ULN2003 board handles the high current and provides built-in
> flyback diodes. Just connect the four control pins to CBUS0–CBUS3 as above.

### Coil sequencing

The 28BYJ‑48 is a unipolar stepper with a 64‑step internal cycle and a 64:1
gearbox (2048 half-steps per output revolution). We will use the standard
half‑step sequence:

```powershell
$seq = @(
    @(1,0,0,0), @(1,1,0,0), @(0,1,0,0), @(0,1,1,0),
    @(0,0,1,0), @(0,0,1,1), @(0,0,0,1), @(1,0,0,1)
)
```

Each sub-array corresponds to the four CBUS pins IN1–IN4; 1 energizes the coil.

### Power considerations

- Use a separate 5 V supply for the motor if you run the FT232RNL at 5 V on
  VCCIO; otherwise the USB rail can supply both.
- The ULN2003 board can draw ~240 mA per energized coil. Limit continuous
  power-on time or heat-sink the chip.

---

## Step 1 - Install Drivers and Verify Detection

```powershell
Import-Module PSGadget.psd1 -Force
List-PsGadgetFtdi | Format-Table Index, Type, SerialNumber, GpioMethod
```

Look for an entry like the one you posted earlier (`Type : FT232R` etc.).
The `GpioMethod` should show `CBUS`.

---

## Step 2 - Program CBUS EEPROM (one-time for FT232R only)

*Skip this step if you are using an FT232H/MPSSE device; the ACBUS pins are
immediately available and no EEPROM programming is required.*

Before runtime GPIO will work on an FT232R you must set CBUS0‑3 to
`FT_CBUS_IOMODE`. Run this once for each physical device:

```powershell
Set-PsGadgetFt232rCbusMode -Index 1  # use your index value here
# unplug/replug the USB cable when prompted or manually
```

Verify with:

```powershell
Get-PsGadgetFtdiEeprom -Index 1 | Select Cbus0,Cbus1,Cbus2,Cbus3
```

All four lines should read `FT_CBUS_IOMODE`.

---

## Step 3 - Verify GPIO Availability

Confirm you can drive the pins (use the same numbers on either chip):

```powershell
# drive all four high, then low
Set-PsGadgetGpio -Index 1 -Pins @(0..3) -State HIGH -DurationMs 200
Set-PsGadgetGpio -Index 1 -Pins @(0..3) -State LOW
```

On an FT232R this toggles CBUS0‑3; on an FT232H it toggles ACBUS0‑3. The
ULN2003 board LEDs will light accordingly (they are tied to each IN pin).

---

## Step 4 - Rapid Smoke Test

Run a simple script to step the motor one revolution (2048 half-steps) at a
moderate pace. Leave the motor disconnected if you just want to watch the
LEDs blink.

```powershell
$seq = @( @(1,0,0,0), @(1,1,0,0), @(0,1,0,0), @(0,1,1,0),
          @(0,0,1,0), @(0,0,1,1), @(0,0,0,1), @(1,0,0,1) )
$conn = Connect-PsGadgetFtdi -Index 1
for ($i=0; $i -lt 2048; $i++) {
    $pattern = $seq[$i % 8]
    for ($pin=0; $pin -lt 4; $pin++) {
        $state = if ($pattern[$pin] -eq 1) { 'HIGH' } else { 'LOW' }
        Set-PsGadgetGpio -Connection $conn -Pins @($pin) -State $state
    }
    Start-Sleep -Milliseconds 3    # adjust for speed
}
# de-energize
Set-PsGadgetGpio -Connection $conn -Pins @(0..3) -State LOW
$conn.Close()
```

If the motor rotates smoothly the basics are operational.

---

## Step 5 - Precise Motion Script

Below is a reusable script that wraps the sequencing logic in functions.

### Optional: use Async Bit‑Bang for smoother motion

For the highest step rate and very smooth motion you can switch the FT232R
into asynchronous bit‑bang mode. This repurposes the lower eight UART pins
(ADBUS0‑7) as a byte‑wide GPIO port; each byte written to the FTDI internal
buffer is output to the pins at a fixed clock rate without further USB
traffic. Even though we only need the first four bits for the ULN2003, this
mode lets you stream an entire step sequence in one bulk transfer, and the
hardware clocks each byte out at the baud rate you set (the driver uses the
same `SetBaudRate` value as for UART mode). The result is dramatically
higher step rates (often several thousand steps/sec) and nearly jitter‑free
pulses.

You do need to rewire to the D0‑D3 lines instead of CBUS: these correspond to
pins ADBUS0‑3 on the chip. The ULN2003 connector in the kit is keyed for the
CBUS pins by default; simply move the jumper wires to the adjacent UART pins
on the FTDI breakout board or create a short adapter harness.

**Half‑step byte sequence** (binary pattern follows IN1‑IN4 from LSB):

```
0001  # 1
0011  # 3
0010  # 2
0110  # 6
0100  # 4
1100  # 12
1000  # 8
1001  # 9
```

Here is an example using the PSGadget API to enable async bit‑bang and stream
bytes:

```powershell
# NOTE: Set-PsGadgetFtdiMode is not yet exported in the current PSGadget
# release. The example below shows the intended API for async bit-bang mode.

# connect and switch mode
$conn = Connect-PsGadgetFtdi -Index 0
Set-PsGadgetFtdiMode -Connection $conn -Mode AsyncBitBang -Mask 0x0F
# pick a baud rate - this controls step timing
# 9600 bytes/sec -> 9600 half-steps/sec
$conn.SetBaudRate(9600)

# build sequence buffer (repeat pattern as needed)
$seq = [byte[]](1,3,2,6,4,12,8,9)
$buf = [System.Collections.Generic.List[byte]]::new()
for ($i=0; $i -lt 2048; $i++) { $buf.Add($seq[$i % 8]) }

# send in one bulk write
$written = 0
$conn.Write($buf.ToArray(), $buf.Count, [ref]$written)

# stop asynchronous output when done
Set-PsGadgetFtdiMode -Connection $conn -Mode UART
$conn.Close()
```

You can also control individual bytes via the public `Set-PsGadgetGpio`
cmdlet once async mode is active. The cmdlet now supports writing raw byte
values, making it convenient for simple sequences without manual buffer
management:

```powershell
# after switching to AsyncBitBang above
foreach ($val in $seq) {
    Set-PsGadgetGpio -Connection $conn -Pins @(0,1,2,3) -State $val
}
```

> **Performance tip:** you can write hundreds or thousands of bytes in a
> single call (`$conn.Write`) and the FTDI chip will clock them out at the
> programmed baud rate, producing a perfectly timed step stream. This allows
> smooth acceleration ramps and high constant speeds without host CPU jitter.

The rest of the precise-motion script (half-step/rotate functions) can be
used with either CBUS or async bit‑bang mode; async bit‑bang simply gives you
better time resolution and higher throughput.

### Half-step function

```powershell
function Invoke-StepperHalfStep {
    param(
        [Parameter(Mandatory)]$Connection,
        [int]$Index,
        [int]$Direction = 1  # 1=forward, -1=backward
    )
    $seq = @( @(1,0,0,0), @(1,1,0,0), @(0,1,0,0), @(0,1,1,0),
              @(0,0,1,0), @(0,0,1,1), @(0,0,0,1), @(1,0,0,1) )
    if (-not (Test-Path variable:script:StepperPos)) { $script:StepperPos = 0 }
    $script:StepperPos = ($script:StepperPos + $Direction) % 8
    if ($script:StepperPos -lt 0) { $script:StepperPos += 8 }
    $pattern = $seq[$script:StepperPos]
    for ($pin=0; $pin -lt 4; $pin++) {
        $state = if ($pattern[$pin] -eq 1) { 'HIGH' } else { 'LOW' }
        Set-PsGadgetGpio -Connection $Connection -Pins @($pin) -State $state
    }
    Start-Sleep -Milliseconds 2
}
```

### Rotate by degrees

```powershell
function Invoke-StepperRotate {
    param(
        [Parameter(Mandatory)]$Connection,
        [double]$Degrees,
        [int]$Direction = 1
    )
    # 2048 half-steps per 360°
    $steps = [math]::Round(2048 * ($Degrees / 360))
    for ($i=0; $i -lt $steps; $i++) {
        Invoke-StepperHalfStep -Connection $Connection -Direction $Direction
    }
}

# Usage example:
$conn = Connect-PsGadgetFtdi -Index 1
Invoke-StepperRotate -Connection $conn -Degrees 90   # quarter turn
Invoke-StepperRotate -Connection $conn -Degrees 45  -Direction -1  # back
Set-PsGadgetGpio -Connection $conn -Pins @(0..3) -State LOW
$conn.Close()
```

Adjust `Start-Sleep` delays in `Invoke-StepperHalfStep` to trade speed vs.
stalling.

---

## Troubleshooting

### Motor does not move

- Verify 5 V supply to the ULN2003 board; the LEDs should light if any coil is
  energized. **Important:** the LEDs only draw a few mA; they may blink even if
  the motor is starving for current. Use a multimeter to measure the voltage
  at the motor connector while a coil is being driven – it should stay near 5 V.
  If it collapses to 1‑2 V or below, the supply cannot source enough current.
- Confirm CBUS GPIO commands produce output (watch the ULN2003 LEDs change
  state one at a time). Seeing the LED blink proves the FTDI side works but
  does not guarantee the motor is getting power.
- Ensure common ground between FT232RNL and motor supply. A missing ground
  reference causes the ULN2003 inputs to float; the LEDs may still glow but the
  transistors won't switch hard.
- Check the mechanical load/gearing. Try running the sequence **with the motor
  disconnected** or hold the rotor lightly by hand; if it turns freely in that
  condition the gearbox or whatever you're coupling to is too stiff or seized.

> **Kit note:** the common 28BYJ‑48 stepper motors bundled with ULN2003 boards
> (as shown above) frequently suffer from **seized or badly‑assembled gear
> trains**. If you feel vibration but no shaft rotation even with proper 5 V
> power and shared ground, swap to one of the other motors in the kit or remove
> the metal cover and inspect/clean the plastic gearbox. In many cases the
> gearbox is glued or partially jammed at the factory and simply replacing the
> motor resolves the issue.

### Only one coil energizes

You may have miswired one of the CBUS pins. Check the mapping again and swap
wires if necessary. The ULN2003 board outputs are labeled IN1–IN4.

### Stepper shudders or stalls

- Increase the delay in `Invoke-StepperHalfStep` (try 5 ms or 10 ms).
- Reduce supply voltage if the motor overheats; the gearbox is fragile.
- Use full-step sequence (`@(1,0,1,0), @(0,1,0,1)` etc.) for more torque.

---

## Quick Reference (Pro)

```powershell
# one‑time setup
Set-PsGadgetFt232rCbusMode -Index 1

# half‑step pattern
$seq=@(@(1,0,0,0),@(1,1,0,0),@(0,1,0,0),@(0,1,1,0),@(0,0,1,0),@(0,0,1,1),@(0,0,0,1),@(1,0,0,1))

# move N half‑steps
$conn=Connect-PsGadgetFtdi -Index 1
for($i=0;$i -lt 512;$i++){ $p=$seq[$i%8];for($pin=0;$pin -lt 4;$pin++){$st=if($p[$pin]){'HIGH'}else{'LOW'};Set-PsGadgetGpio -Connection $conn -Pins @($pin) -State $st};Start-Sleep -Milliseconds 3}
Set-PsGadgetGpio -Connection $conn -Pins @(0..3) -State LOW
$conn.Close()
```

---

*End of stepper example.*
