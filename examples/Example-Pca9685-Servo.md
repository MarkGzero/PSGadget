# Example: PCA9685 Servo Control via I2C (Hardware PWM)

Drive multiple RC hobby servos using a PCA9685 16-channel PWM controller board connected via I2C to an FT232H FTDI adapter. This approach provides high-precision, jitter-free servo positioning with zero CPU overhead — the FTDI chip handles I2C timing, and the PCA9685 generates PWM autonomously.

Two hardware approaches are covered:

- **Single PCA9685** — up to 16 servos; each servo position set via simple degree value (0-180).
- **Multi-board via I2C addressing** — stack multiple PCA9685 boards at different I2C addresses (0x40-0x47) for up to 112 servos on one FTDI adapter.

---

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [What You Need](#what-you-need)
- [Hardware Background](#hardware-background)
  - [How RC Servo PWM Works](#how-rc-servo-pwm-works)
  - [Why PCA9685 Is Better Than GPIO Bit-Bang](#why-pca9685-is-better-than-gpio-bit-bang)
  - [The PCA9685 Chip](#the-pca9685-chip)
  - [Wiring: FT232H I2C to PCA9685](#wiring-ft232h-i2c-to-pca9685)
  - [Power Considerations](#power-considerations)
- [Step 1 - Install Drivers and Verify Detection](#step-1---install-drivers-and-verify-detection)
- [Step 2 - Smoke Test: Move to Three Positions](#step-2---smoke-test-move-to-three-positions)
- [Step 3 - Precise Position Script (Multiple Servos)](#step-3---precise-position-script-multiple-servos)
- [Servo Position Reference](#servo-position-reference)
- [Troubleshooting](#troubleshooting)
- [Quick Reference (Pro)](#quick-reference-pro)

---

## Who This Is For

- **Beginner** - new to servos and I2C hardware. Explains the wiring, the PWM signal, the PCA9685 chip, and every PowerShell command from scratch.
- **Scripter** - comfortable with PowerShell, wants to control multiple servos with simple angle commands (0-180 degrees).
- **Engineer** - familiar with I2C protocols, servo specs, and PWM timing; wants to understand the PCA9685 register map and how PSGadget interfaces with it via MPSSE I2C.
- **Pro** - skip to Quick Reference for condensed code.

---

## What You Need

- **FT232H FTDI USB adapter** (recommended) - provides I2C host controller via MPSSE engine.
  - Alternatives: FT232RL with I2C bit-bang (slower, less reliable), or direct USB-to-I2C adapter.
- **PCA9685 16-channel PWM controller breakout board**. Common boards:
  - Adafruit PCA9685 servo hat (https://www.adafruit.com/product/2327)
  - Generic PCA9685 I2C PWM breakout (~$3-5 on Amazon/AliExpress)
  - Standard I2C address: 0x40 (jumpers can set 0x40-0x47)
- **Standard RC hobby servos** (SG90, MG996R, DS3218, or similar).
  - Red wire: power (5V external)
  - Brown/black wire: ground (shared with PCA9685 and FTDI GND)
  - Yellow/white/orange wire: PWM signal input (from PCA9685 servo output pin)
- **External 5V power supply** capable of at least 500 mA per servo (servo stall current can exceed 1 A).
  - **Do not power servos from FTDI USB 5V rail** — brownout will break GPIO and I2C.
- **I2C pull-up resistors** — 4.7k on both SCL and SDA (required; some breakouts have them built-in).
- Jumper wires.
- Windows PC with FTDI D2XX drivers installed (or Linux with libftd2xx).
- PowerShell 5.1+ and the PSGadget module.

> **Beginner**: A servo has three wires. Power and ground go to an external 5V supply. The signal wire (PWM) connects to a PCA9685 output channel. The PCA9685 itself connects to the FTDI adapter via two I2C wires (SCL and SDA).

> **Engineer**: RC servo specs (MG996R datasheet, SG90 spec sheet) typically quote a PWM input range of 1.0-2.0 ms, but the MG996R and most modern hobby servos respond to the wider standard RC range of 0.5-2.5 ms (full 180 deg travel). PSGadget defaults to 0.5-2.5 ms to cover more servo models without clipping travel. If your servo spec sheet is narrower (e.g. 0.75-2.25 ms), pass `-PulseMinUs`/`-PulseMaxUs` at connect time. The PCA9685 uses a 25 MHz internal oscillator with 12-bit PWM resolution (0-4095 counts per period). I2C standard mode (100 kHz) is sufficient; most breakouts support fast mode (400 kHz) but PSGadget defaults to 100 kHz.

---

## Hardware Background

### How RC Servo PWM Works

An RC servo expects a periodic pulse on its signal wire:

- **Period**: 20 ms (50 Hz)
- **Pulse width encodes position**:

| Pulse width | Position   |
|-------------|------------|
| 1.0 ms      | 0 deg (min / full CCW)  |
| 1.5 ms      | 90 deg (center / neutral) |
| 2.0 ms      | 180 deg (max / full CW) |

The servo holds its position as long as pulses continue arriving at 50 Hz. If pulses stop, most servos hold position briefly then go limp (no torque).

> **Beginner**: think of the pulse width as a message: "go to this angle and hold." The servo has an internal motor, gearbox, and potentiometer. It keeps turning until the angle matches what the pulse is asking for.

> **Engineer**: the servo's internal control loop runs at ~50 Hz. Each pulse encodes a desired position; the servo motor drives until feedback matches setpoint. Missing or erratic pulses cause the position loop to hunt or become unstable.

### Why PCA9685 Is Better Than GPIO Bit-Bang

Covered in detail in Example-ServoMotor.md, but the summary:

| Approach | Timing | CPU | Jitter | Servos | Best For |
|----------|--------|-----|--------|--------|----------|
| GPIO bit-bang (FT232H ADBUS + Stopwatch) | Host PowerShell loop | 100% (one core) | Visible on scope | 1-4 | Hobbyist, single servo, learning |
| PCA9685 I2C (Tier 0 hardware) | FTDI MPSSE + PCA9685 silicon | <1% (I2C write only) | None (hardware clocked) | 16 (or 112 multi-board) | Production, precision, multi-servo |

**Key advantage**: PWM timing is handled entirely by the PCA9685 chip. PowerShell only sends register writes (2-4 bytes) and receives I2C ACK. Result: deterministic, zero jitter, no Windows scheduler interference.

### The PCA9685 Chip

The NXP PCA9685 is a 16-channel 12-bit PWM controller designed for LED dimming and servo control:

- **16 independent PWM channels** (channels 0-15)
- **12-bit resolution** — 4096 steps per PWM period
- **Frequency range** — 23-1526 Hz (50 Hz for servos is typical)
- **Internal 25 MHz oscillator** — frequency set via prescaler register
- **I2C interface** — standard 100 kHz (slow) or 400 kHz (fast) mode
- **Sleep mode** — required to reprogram prescaler for frequency changes
- **Auto-increment** — write multiple registers in single I2C transaction

PSGadget's PsGadgetPca9685 class handles all of this. The preferred API is `Invoke-PsGadgetI2C`:

```powershell
# Preferred (current) API
Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -ServoAngle @(0, 90)

# Legacy API (still works, but deprecated)
Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 90
```

PSGadget calculates the register values, sends the I2C write, and the chip generates the PWM.

> **Note**: `Connect-PsGadgetPca9685`, `Invoke-PsGadgetPca9685SetChannel`, `Invoke-PsGadgetPca9685SetChannels`, `Get-PsGadgetPca9685Channel`, and `Get-PsGadgetPca9685Frequency` are still loaded and functional but are deprecated. Use `Invoke-PsGadgetI2C -I2CModule PCA9685` for new code.

> **Engineer**: at 50 Hz, 20 ms period, 4096 steps:
> - Step duration: 20 ms / 4096 = 4.88 µs
> - Default pulse range: 0.5 ms (0 deg) to 2.5 ms (180 deg) — 0 deg = 102 steps, 90 deg = 307 steps, 180 deg = 512 steps
> - Prescaler formula: `prescale = round(25MHz / (4096 * 50 Hz)) - 1 = 121`
> - Count formula: `offCount = pulseUs * frequency * 4096 / 1_000_000`
>
> PSGadget uses `DegreesToCounts()` with per-instance `PulseMinUs`/`PulseMaxUs` properties. Defaults are 500/2500. Pass `-PulseMinUs`/`-PulseMaxUs` to `Connect-PsGadgetPca9685` or `Invoke-PsGadgetI2C` to retune for your specific servo model.

### Wiring: FT232H I2C to PCA9685

Connect as follows:

| FT232H pin | Signal | PCA9685 pin | Breakout label |
|-----------|--------|------------|-----------------|
| D0 (ADBUS0) | SCL (clock) | SCL | SCL |
| D1 (ADBUS1) | SDA (data) | SDA | SDA |
| GND | Ground | GND | GND (shared with servo supply) |
| 3.3V or board logic rail | — | VCC / VDD | Logic power |
| *(separate 5V servo supply)* | — | V+ / VIN / EXT_PWR | Servo power |
| (servo power output) | — | (servo signal pins) | OUT0-OUT15 |

**Critical**: Add 4.7k pull-up resistors from SCL and SDA to the PCA9685 logic rail (VCC / VDD). Most PCA9685 breakouts have these built-in; verify with a multimeter if unsure.

Many PCA9685 servo boards have **two separate power domains**:

- **VCC / VDD** = logic power for the chip and I2C pull-ups
- **V+ / VIN / EXT_PWR** = high-current servo power rail

If only the servo rail is powered, the board may move no servo and also fail to ACK on I2C because the PCA9685 logic core is still off.

```
SCL line:  FT232H D0 -- [4.7k] -- +3.3V or logic VCC
           PCA9685 SCL

SDA line:  FT232H D1 -- [4.7k] -- +3.3V or logic VCC
           PCA9685 SDA

Logic:     FT232H 3.3V -- PCA9685 VCC/VDD
Servo:     External 5V -- PCA9685 V+/VIN
GND:       FT232H GND -- PCA9685 GND -- Servo supply GND (all connected)
```

**Multiple boards**: To control 16+ servos, provide each PCA9685 a unique I2C address (0x40-0x47 via jumpers on the breakout). Connect all boards to the same SCL/SDA lines; each responds to its unique address.

### Power Considerations

- **External 5V servo supply (mandatory)**: At least 500 mA per servo; larger servos (MG996R) may draw 2.5 A stall current.
- **Power the logic rail too**: VCC / VDD must be powered for the PCA9685 to respond on I2C. On many FT232H setups this is 3.3V from the FT232H breakout.
- **Servo power supply GND must be connected to FTDI GND** — I2C signals have no return path otherwise.
- **Add a 100-470 µF capacitor across the servo supply terminals** — smooths power spikes and prevents I2C glitches during servo stall.
- **Do not assume V+ also powers VCC** — many boards keep them isolated on purpose. Check the silkscreen.

> **Beginner**: The servo and FTDI adapter must share the same ground reference. Without shared ground, the I2C signal (SDA) has no return path and devices cannot communicate.

---

## Step 1 - Install Drivers and Verify Detection

```powershell
Import-Module PSGadget.psd1 -Force
Get-FtdiDevice | Format-Table Index, Type, SerialNumber, GpioMethod
```

For FT232H you should see `GpioMethod : MPSSE`. Verify I2C detection:

```powershell
$dev = New-PsGadgetFtdi -Index 0
Set-PsGadgetFtdiMode -PsGadget $dev -Mode MpsseI2c
Invoke-PsGadgetI2CScan -PsGadget $dev | Format-Table
```

You should see the PCA9685 at address 0x40 (or your custom address if you changed the jumpers) in the list.

```
Address
-------
0x40
```

If address 0x40 does not appear:
- Check wiring (SCL/SDA connected correctly?)
- Verify pull-up resistors are present (4.7k on both lines)
- Check that PCA9685 VCC is connected to +5V

---

## Step 2 - Smoke Test: Move to Three Positions

Minimal script to verify the servo moves:

```powershell
Import-Module PSGadget.psd1 -Force

$pca = Connect-PsGadgetPca9685 -Index 0

try {
    Write-Host "-> Moving to 0 degrees (full CCW)"
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 0
    Start-Sleep -Seconds 1

    Write-Host "-> Moving to 90 degrees (center)"
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 90
    Start-Sleep -Seconds 1

    Write-Host "-> Moving to 180 degrees (full CW)"
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 180
    Start-Sleep -Seconds 1

    Write-Host "-> Back to 90 degrees"
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 90

} finally {
    $pca
}
```

You should see the servo arm swing to each position. If it does not move, see the Troubleshooting section.

> **Beginner**: `Start-Sleep -Seconds 1` pauses for 1 second between moves so you can see the motion. Without the pause, all moves happen instantly.

> **Engineer**: Each `Invoke-PsGadgetPca9685SetChannel` call performs **one I2C write** (2-4 bytes). The I2C round-trip takes ~1-2 ms on Windows. The PCA9685 hardware then generates the PWM for that channel independently. If multiple channels are set sequentially, they all operate at exactly 50 Hz with no crosstalk.

---

## Step 3 - Precise Position Script (Multiple Servos)

Set multiple servos at different angles, then sweep them:

```powershell
Import-Module PSGadget.psd1 -Force

$pca = Connect-PsGadgetPca9685 -Index 0

try {
    # Beginner: center all 4 servos
    Write-Host "Centering servos..."
    Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees @(90, 90, 90, 90)
    Start-Sleep -Milliseconds 500

    # Scripter: sweep each servo 0->180->90
    for ($deg = 0; $deg -le 180; $deg += 10) {
        Write-Host "Position: $deg deg"
        Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees $deg
        Start-Sleep -Milliseconds 100
    }

    for ($deg = 180; $deg -ge 0; $deg -= 10) {
        Write-Host "Position: $deg deg"
        Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees $deg
        Start-Sleep -Milliseconds 100
    }

    Write-Host "Back to center"
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 90

    # Engineer: simultaneous multi-servo update
    Write-Host "Pan-tilt combination"
    Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees @(45, 70)   # Pan left, tilt down
    Start-Sleep -Milliseconds 200
    Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees @(135, 110) # Pan right, tilt up
    Start-Sleep -Milliseconds 200
    Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees @(90, 90)   # Center both

} finally {
    $pca
}
```

> **Scripter**: `Invoke-PsGadgetPca9685SetChannels` accepts an array of angles (one per channel). It sets all provided channels in rapid succession, then you can wait for them to reach position together.

> **Engineer**: Each channel operates independently once the I2C write completes. The PCA9685 PWM outputs are **frame-aligned**: all 16 channels' HIGH edges occur at exactly the same time (start of period), so multi-servo systems have zero inter-channel skew.

---

## Servo Position Reference

Use this table to understand the degree-to-pulse mapping (PSGadget default range: 0.5-2.5 ms):

| Degrees | Pulse width | PWM counts (50 Hz) | Servo behavior |
|---------|-------------|---------------------|----------------|
| 0 | 0.5 ms | 102 | Full counterclockwise |
| 45 | 1.0 ms | 205 | 1/4 travel left from center |
| 90 | 1.5 ms | 307 | Center/neutral (typical idle position) |
| 135 | 2.0 ms | 410 | 1/4 travel right from center |
| 180 | 2.5 ms | 512 | Full clockwise |

All values outside 0-180 are clamped by PSGadget. The pulse range is configurable via `-PulseMinUs`/`-PulseMaxUs` (see Troubleshooting if your servo does not reach full travel).

---

## Troubleshooting

### I2C device does not appear in I2CScan

- **Check wiring**: SCL = FT232H D0, SDA = FT232H D1, GND shared
- **Check pull-ups**: 4.7k resistors on both SCL and SDA must be present
- **Check power**: PCA9685 VCC must be +5V; measure with multimeter
- **Try a different address**: If PCA9685 address jumpers are set to something other than 0x40, specify `-Address 0x41` (or your custom address) in `Connect-PsGadgetPca9685`
- **Try direct I2C read**: Use I2CScan with verbose output to see if any address responds:
  ```powershell
  Invoke-PsGadgetI2CScan -PsGadget $dev -Verbose
  ```

### Servo does not move at all

- **First check**: I2CScan sees your PCA9685 at the correct address?
- **Power**: Is the servo power (red wire) connected to +5V external supply? Is the brown/black (ground) wire connected?
- **Signal wiring**: Yellow/white/orange signal wire from servo connected to a PCA9685 OUT pin (OUT0-OUT15)?
- **PCA9685 VCC/GND**: Board powered (+5V and GND connected)?
- **Shared ground**: Servo GND, PCA9685 GND, and FTDI GND all connected together?
- **Try a known-good servo**: Some servos have nonstandard PWM ranges or are damaged

### Servo twitches or buzzes continuously

- **Power supply insufficient**: If the servo is stalling (resistance when you try to move it by hand), the 5V supply may be sagging. Add a larger capacitor across the servo supply (100-470 µF electrolytic).
- **Ground loop**: Ensure all grounds (FTDI, PCA9685, servo supply) are connected at one point; floating grounds introduce noise.

### Servo does not reach full travel (short range or stiff at extremes)

- Your servo may have a narrower pulse range than the PSGadget default of 0.5-2.5 ms (e.g., the datasheet may specify 0.75-2.25 ms or 1.0-2.0 ms). Pass `-PulseMinUs` and `-PulseMaxUs` at connect time to match your servo:
  ```powershell
  # Legacy API - tune pulse range
  $pca = Connect-PsGadgetPca9685 -Index 0 -PulseMinUs 750 -PulseMaxUs 2250

  # Preferred API - tune pulse range
  Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -ServoAngle @(0, 0) -PulseMinUs 750 -PulseMaxUs 2250
  ```
- Conversely, if the servo buzzes or strains at 0 or 180 degrees, the pulse range may be too wide. Reduce `PulseMaxUs` or increase `PulseMinUs`.

---

## Quick Reference (Pro)

```powershell
Import-Module PSGadget.psd1 -Force

# --- Preferred API (Invoke-PsGadgetI2C) ---

# Single channel (opens + closes device automatically)
Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -ServoAngle @(0, 90)

# By serial number (stable across USB re-plug)
Invoke-PsGadgetI2C -SerialNumber 'FTAXBFCQ' -I2CModule PCA9685 -ServoAngle @(0, 90)

# Multiple channels in one call
Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -ServoAngle @(@(0,90), @(1,45), @(2,135))

# Custom pulse range (for servos with non-standard range)
Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -ServoAngle @(0, 90) -PulseMinUs 750 -PulseMaxUs 2250

# Reuse an open device (device is NOT closed after call)
$dev = New-PsGadgetFtdi -Index 0
Invoke-PsGadgetI2C -PsGadget $dev -I2CModule PCA9685 -ServoAngle @(0, 90)

# --- Legacy API (deprecated - still functional) ---

$pca = Connect-PsGadgetPca9685 -Index 0   # 0x40, 50 Hz, 500-2500 us
$pca = Connect-PsGadgetPca9685 -Index 0 -PulseMinUs 750 -PulseMaxUs 2250  # custom range
Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 90
Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees @(0, 45, 90, 135, 180)
$pos = Get-PsGadgetPca9685Channel -PsGadget $pca -Channel 0   # reads local cache
$freq = Get-PsGadgetPca9685Frequency -PsGadget $pca

# Sweep example (works with either API; shown with legacy for multi-step)
$pca = Connect-PsGadgetPca9685 -Index 0
for ($deg = 0; $deg -le 180; $deg += 5) {
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees $deg
    Start-Sleep -Milliseconds 50   # 50 ms/step = ~9 sec total sweep
}
```

**Performance**: Every `Invoke-PsGadgetPca9685SetChannel` call is **Tier 0** (hardware I2C clocking). PowerShell involvement is minimal: parameter binding + 1 I2C write. Typical latency: 1-2 ms per I2C command. The PCA9685 generates PWM independently with zero CPU overhead.

---

## Practical Example: Pan-Tilt Laser Rig

Two servos on channels 0 (pan) and 1 (tilt) position a laser pointer:

```powershell
Import-Module PSGadget.psd1 -Force
$pca = Connect-PsGadgetPca9685 -Index 0

function Aim-Laser {
    param([int]$PanDeg, [int]$TiltDeg, [int]$FireMs = 0)

    Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees @($PanDeg, $TiltDeg)
    Start-Sleep -Milliseconds 300

    if ($FireMs -gt 0) {
        # If you have a relay on another GPIO, trigger it here
        Write-Host "FIRE (simulated for $($FireMs) ms)"
        # Set-PsGadgetGpio -Connection $conn -Pins @(2) -State HIGH -DurationMs $FireMs
        Start-Sleep -Milliseconds $FireMs
    }
}

try {
    Write-Host "Centering..."
    Aim-Laser -PanDeg 90 -TiltDeg 90

    Write-Host "Target 1: pan left, aim down"
    Aim-Laser -PanDeg 30 -TiltDeg 60 -FireMs 200

    Write-Host "Target 2: pan right, aim up"
    Aim-Laser -PanDeg 150 -TiltDeg 120 -FireMs 200

    Write-Host "Back to center"
    Aim-Laser -PanDeg 90 -TiltDeg 90

} finally {
    $pca
}
```

> **Engineer**: This script uses `Invoke-PsGadgetPca9685SetChannels` to set both pan and until servos in one command. Each channel receives its own 50 Hz PWM independent of the other, but they start at the same rising edge (zero inter-channel skew). The 300 ms wait gives the servos time to move and settle before the next aim command.

---
