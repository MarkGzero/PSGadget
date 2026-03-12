# Example: Servo Control with FT232H (ACBUS) or FT232R (Async Bit-Bang)

Drive a standard RC hobby servo directly from an FTDI USB adapter using
software-generated PWM — no dedicated PWM driver board required.

Two hardware approaches are covered:

- **FT232H / MPSSE + Stopwatch spin-wait** — D4-D7 (ADBUS GPIO) drives one
  servo with ~1 us pulse accuracy. Recommended for one or two servos.
- **Async bit-bang streaming** — FT232R or FT232H ADBUS, streams a
  pre-built byte buffer at a hardware-clocked baud rate. Up to 8 simultaneous
  servos; best resolution; requires rewiring to ADBUS pins.

---

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [What You Need](#what-you-need)
- [Hardware Background](#hardware-background)
  - [How RC Servo PWM Works](#how-rc-servo-pwm-works)
  - [Why FTDI Cannot Do Real PWM](#why-ftdi-cannot-do-real-pwm)
  - [The Two Software PWM Approaches](#the-two-software-pwm-approaches)
  - [Wiring - FT232H D4-D7 ADBUS (single servo)](#wiring---ft232h-d4-d7-adbus-single-servo)
  - [Wiring - FT232H C0-C7 ACBUS (single servo, alternative)](#wiring---ft232h-c0-c7-acbus-single-servo-alternative)
  - [Wiring - FT232R or FT232H Async Bit-Bang (multi-servo)](#wiring---ft232r-or-ft232h-async-bit-bang-multi-servo)
  - [Power Considerations](#power-considerations)
- [Step 1 - Install Drivers and Verify Detection](#step-1---install-drivers-and-verify-detection)
- [Step 2 - Smoke Test: Move to Three Positions](#step-2---smoke-test-move-to-three-positions)
- [Step 3 - Precise Position Script (Single Servo)](#step-3---precise-position-script-single-servo)
  - [Fix Windows Timer Resolution and USB Latency](#fix-windows-timer-resolution-and-usb-latency)
  - [Set-Servo function](#set-servo-function)
  - [Sweep demo](#sweep-demo)
- [Speeding Up and Resolution Limits](#speeding-up-and-resolution-limits)
  - [Raw MPSSE write path](#raw-mpsse-write-path)
  - [Async bit-bang streaming (multi-servo)](#async-bit-bang-streaming-multi-servo)
- [Troubleshooting](#troubleshooting)
  - [Device appears twice in List-PsGadgetFtdi (VCP driver conflict)](#device-appears-twice-in-list-psgadgetftdi-vcp-driver-conflict)
  - [FT232H signal is wrong frequency on scope (~20 Hz instead of 50 Hz)](#ft232h-signal-is-wrong-frequency-on-scope-20-hz-instead-of-50-hz)
  - [Servo does not move at all](#servo-does-not-move-at-all)
  - [Servo twitches or buzzes continuously](#servo-twitches-or-buzzes-continuously)
  - [Position is wrong or inconsistent](#position-is-wrong-or-inconsistent)
  - [Servo only reaches two positions](#servo-only-reaches-two-positions)
- [Quick Reference (Pro)](#quick-reference-pro)
- [Practical Example: Pan-Tilt Laser Rig](#practical-example-pan-tilt-laser-rig)

---

## Who This Is For

- **Beginner** - new to servos and USB GPIO. The guide explains the wiring,
  the PWM signal, and every PowerShell command from scratch.
- **Scripter** - comfortable with PowerShell, wants a reusable `Set-Servo`
  function with degree-to-pulse mapping.
- **Engineer** - familiar with RC servo PWM; wants to understand the FTDI
  timing constraints and what resolution is achievable without a dedicated
  PWM IC.
- **Pro** - skip to Quick Reference for the condensed code.

---

## What You Need

- FTDI USB adapter with GPIO capability:
  - **FT232H** (recommended) - ACBUS0 or ADBUS0-7; 3.3 V logic level
    (most servo signal inputs accept 3.3 V).
  - **FT232R/FT232RNL** - ADBUS0-7 (async bit-bang); CBUS0-3 are limited
    (3-position only without extra hardware).
- Standard RC hobby servo (SG90, MG996R, DS3218, or similar). Any servo
  that accepts a standard 50 Hz PWM signal works.
- External 5 V power supply capable of at least 500 mA per servo.
  **Do not power servos from the FTDI USB 5 V rail** — servo stall current
  can exceed 1 A and will brown-out the USB port.
- Jumper wires.
- Windows PC with FTDI D2XX drivers installed.
- PowerShell 5.1+ and the PSGadget module.

> **Beginner**: a servo has three wires — power (red or orange), ground
> (brown or black), and signal (yellow, white, or orange). The signal wire
> carries the PWM pulse that tells the servo what angle to hold. You only
> connect the signal wire to the FTDI adapter; power and ground go to your
> external supply.

> **Engineer**: most servo datasheets specify 4.8-6.0 V on the power rail.
> The signal input is typically tolerant of 3.3 V logic from the FT232H
> (datasheet input high threshold is usually 2.0-2.5 V). Verify your specific
> servo's signal threshold before connecting. If in doubt, add a 5 V level
> shifter on the signal line.

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

The servo holds its position as long as pulses continue arriving. If pulses
stop, most servos hold position briefly then go limp (no torque).

The pulse width range varies slightly between manufacturers (some allow
0.5-2.5 ms for a wider 270 deg range). The 1.0-2.0 ms / 0-180 deg range is
universal.

> **Beginner**: think of the pulse width as a message: "go to this angle and
> hold." The servo has an internal motor, a gearbox, and a potentiometer that
> measures its own angle. It keeps turning until the angle matches what the
> pulse is asking for.

> **Engineer**: the servo's internal control loop runs continuously; it
> compares the pulse width to its wiper voltage and drives the motor to close
> the error. Missing or inconsistent pulses cause the position loop to open;
> the servo coasts or jitters depending on the design.

### Why FTDI Cannot Do Real PWM

FTDI chips (FT232H, FT232R) have no hardware PWM timer. All PWM must be
generated in software:

1. Drive the signal pin HIGH.
2. Wait exactly `pulseMs` milliseconds.
3. Drive the pin LOW.
4. Wait the remainder of the 20 ms period (`20 - pulseMs` ms).
5. Repeat at 50 Hz.

The achievable resolution is limited by the host timer granularity. On
Windows, `Start-Sleep` defaults to ~15.625 ms granularity. Calling
`timeBeginPeriod(1)` is unreliable in PowerShell — `Add-Type` caches the
definition, so the winmm.dll registration silently fails in some sessions
(scope-confirmed: still 20.83 Hz / 33% duty with `Start-Sleep`). A reliable
alternative is a **Stopwatch spin-wait** for the short pulse using the CPU
performance counter (~10 MHz), which requires no `Add-Type` and gives accurate
pulse widths to ~1 us regardless of OS timer state.

### The Two Software PWM Approaches

| Approach | Resolution | Servos | Chip | Notes |
|---|---|---|---|---|
| Stopwatch spin-wait + raw `0x80` write | ~100+ positions (~1 us) | 1-4 | FT232H | Recommended; D4-D7 or C0-C7 |
| Async bit-bang streaming | ~100 positions (10 us) | up to 8 | FT232H or FT232R | Best for multi-servo; D0-D7 |

> **Engineer**: the async bit-bang approach streams a pre-computed byte
> buffer representing multiple PWM periods. The FTDI chip clocks each byte
> out at the programmed baud rate independently of the host CPU. At
> 100,000 baud (10 us/byte) you can represent each 20 ms servo period as
> a 2000-byte buffer with ~10 us pulse resolution — far better than the
> 1 ms software approach. The tradeoff is that changing position requires
> rebuilding the buffer and re-streaming.

### Wiring - FT232H D4-D7 ADBUS (single servo)

Connect D7 (ADBUS7) to the servo signal wire. D4-D7 are the MPSSE GPIO pins
on the low byte (D-bus); D0-D3 are reserved by the MPSSE engine for serial
protocol signals (clock, MOSI, MISO, CS) and cannot be used as servo outputs.

| FT232H pin | Signal | Servo wire |
|-----------|--------|------------|
| D7 (ADBUS7) | Signal | Signal (yellow/white/orange) |
| GND | Ground | Ground (brown/black) — shared with servo supply GND |
| *(separate 5 V supply)* | — | Power (red/orange) |

Any of D4-D7 works. D7 is a safe default when not running SPI/I2C, since it
is furthest from the D0-D3 protocol pins.

> **Beginner**: the GND of the FTDI adapter and the GND of the servo power
> supply MUST be connected together. Otherwise the signal has no return path
> and the servo will not respond.

> **Engineer**: D4-D7 are MPSSE GPIO controlled by the `0x80` (Set Data Bits
> Low Byte / ADBUS) command. Byte 1 = output value; byte 2 = direction mask.
> D0-D3 are managed by the MPSSE engine and must not be set via `0x80` writes
> during active SPI/I2C transfers. Output is 3.3 V at 4 mA drive. Most SG90
> and MG996R servo signal inputs accept 3.3 V logic.

### Wiring - FT232H C0-C7 ACBUS (single servo, alternative)

C0-C7 (ACBUS0-7) are the second MPSSE GPIO bank, controlled by the `0x82`
(Set Data Bits High Byte / ACBUS) command. Use these if D4-D7 are occupied by
SPI/I2C chip select or reset lines.

| FT232H pin | Signal | Servo wire |
|-----------|--------|------------|
| C0 (ACBUS0) | Signal | Signal (yellow/white/orange) |
| GND | Ground | Ground (brown/black) — shared with servo supply GND |
| *(separate 5 V supply)* | — | Power (red/orange) |

In code, replace `0x80` with `0x82`. Pin mask is the same: C0 = bit 0, C7 = bit 7.

> **Engineer**: C8 and C9 are NOT general-purpose GPIO — they are
> special-purpose EEPROM-configured pins (PWREN/SLEEP/TXDEN). Only C0-C7 are
> freely usable as GPIO. The PSGadget `Set-PsGadgetGpio` cmdlet controls ACBUS
> via `0x82`; it does NOT currently support ADBUS D-bus GPIO. Use raw `0x80`
> writes (as shown in the code examples) when controlling D4-D7.

### Wiring - FT232R or FT232H Async Bit-Bang (multi-servo)

Use ADBUS0-7 (the UART lines: TX/RX/RTS/CTS/DTR/DSR/DCD/RI). Each bit in
the streamed byte independently controls one servo. Requires rewiring from
ACBUS to ADBUS.

| ADBUS pin | Servo # | Servo wire     |
|-----------|---------|----------------|
| ADBUS0 (TX)  | 0   | Signal (S0)    |
| ADBUS1 (RX)  | 1   | Signal (S1)    |
| ADBUS2 (RTS) | 2   | Signal (S2)    |
| ADBUS3 (CTS) | 3   | Signal (S3)    |
| GND          | all | Ground (shared with supply GND) |
| *(separate 5 V supply)* | all | Each servo power wire |

### Power Considerations

- Servo stall current (MG996R): up to 2.5 A. Use a beefy 5 V supply.
- SG90 micro servo: stall ~360 mA, running ~120 mA. USB 5 V rail may work
  for one SG90 if no other load, but it is risky and not recommended.
- Always share ground between the FTDI adapter and the servo power supply.
- Add a 100-470 uF electrolytic capacitor across the servo power supply
  terminals to absorb current spikes and prevent brownout glitches on the
  signal line.

---

## Step 1 - Install Drivers and Verify Detection

```powershell
Import-Module PSGadget.psd1 -Force
List-PsGadgetFtdi | Format-Table Index, Type, SerialNumber, GpioMethod
```

For FT232H you should see `GpioMethod : MPSSE`. For FT232R you should see
`GpioMethod : CBUS` (CBUS bit-bang) or use async bit-bang on ADBUS directly.

```powershell
# Verify you can open the device
$dev = New-PsGadgetFtdi -Index 0
$dev | Get-Member   # confirms object type
$dev.Close()
```

**Check for VCP driver conflict before continuing (applies to both FT232H and FT232R):**

```powershell
# Both FT232H and FT232R can enumerate as a VCP COM port simultaneously with D2XX,
# depending on their EEPROM configuration. When this happens, the VCP driver holds
# partial ownership of the hardware interface and D2XX SetBitMode calls succeed
# without error but produce no electrical output.
#
# FT232H: factory EEPROM may have IsVCP=True (chip- and board-dependent).
# FT232R: factory EEPROM defaults to RIsD2XX=False, meaning VCP is ON by default.
#         Almost every fresh FT232R will enumerate as a COM port out of the box.
#         Running CBUS bit-bang or async bit-bang on ADBUS requires D2XX exclusive
#         access, so VCP must be disabled first.

# Check: does the device appear twice?
List-PsGadgetFtdi -ShowVCP | Format-Table Index, Type, SerialNumber, Flags
# If the same serial number appears twice (once as D2XX, once as a COM port),
# you have a VCP conflict. Fix it before running any servo code:

# Read EEPROM to confirm (look for IsVCP : True on FT232H, RIsD2XX : False on FT232R)
Get-PsGadgetFtdiEeprom -Index 0

# Fix: disable VCP permanently in EEPROM (one-time, requires USB replug)
Set-PsGadgetFtdiEeprom -Index 0 -DisableVcp

# Verify: after replug, should show only one D2XX entry with no COM port
List-PsGadgetFtdi -ShowVCP | Format-Table
Get-PsGadgetFtdiEeprom -Index 0   # IsVCP : False (FT232H) or RIsD2XX : True (FT232R)
```

> **Engineer**: when the VCP driver (`ftdibus.sys`) is loaded alongside `ftd2xx.dll`
> for the same physical device, it holds a partial claim on the USB interface.
> `SetBitMode` calls return `FT_OK` but the mode change has no effect — the MPSSE
> engine (FT232H) never activates, and CBUS/async bit-bang (FT232R) produce no
> output. FT232H EEPROM flag: `IsVCP` (set to `False` to fix). FT232R EEPROM flag:
> `RIsD2XX` (set to `True` to fix). Both are written by `Set-PsGadgetFtdiEeprom
> -DisableVcp`; a USB replug is the only requirement after writing.

---

## Step 2 - Smoke Test: Move to Three Positions

Three positions only (0, 90, 180 degrees). Uses a Stopwatch spin-wait for
accurate pulse timing — no `Add-Type` or `timeBeginPeriod` required.

Note: `Set-PsGadgetGpio` only controls ACBUS (C-bus) pins via `0x82` and does
not support ADBUS D-bus pins. For D4-D7, use raw MPSSE writes as shown below.

```powershell
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1

$dev     = New-PsGadgetFtdi -Index 0
$rawFtdi = $dev._connection.Device
$rawFtdi.SetLatency(1) | Out-Null   # reduce USB latency timer from 16 ms to 1 ms

# Stopwatch for accurate sub-ms pulse timing (immune to OS timer granularity)
$sw     = [System.Diagnostics.Stopwatch]::new()
$swFreq = [System.Diagnostics.Stopwatch]::Frequency   # typically 10 MHz HPET

# Servo on D7 (ADBUS7): MPSSE command 0x80, pin mask = bit 7 = 0x80
$D7_HI = [byte[]](0x80, 0x80, 0xFF)   # D7 HIGH, all D-bus as outputs
$D7_LO = [byte[]](0x80, 0x00, 0xFF)   # all D-bus LOW

function Send-ServoPulse {
    param(
        [double]$PulseMs = 1.5,   # 1.0 = 0 deg, 1.5 = 90 deg, 2.0 = 180 deg
        [int]$Cycles     = 25     # 25 cycles at ~20 ms period = ~500 ms hold
    )
    $pulseTicks = [long]($PulseMs * $swFreq / 1000.0)
    $lowMs      = 20.0 - $PulseMs
    $w = 0
    for ($i = 0; $i -lt $Cycles; $i++) {
        $rawFtdi.Write($D7_HI, 3, [ref]$w) | Out-Null
        $sw.Restart()
        while ($sw.ElapsedTicks -lt $pulseTicks) {}   # spin-wait: accurate to ~1 us
        $rawFtdi.Write($D7_LO, 3, [ref]$w) | Out-Null
        Start-Sleep -Milliseconds $lowMs              # low period; OS imprecision OK
    }
}

try {
    Write-Host "-> Center (90 deg)"
    Send-ServoPulse -PulseMs 1.5

    Write-Host "-> Minimum (0 deg)"
    Send-ServoPulse -PulseMs 1.0

    Write-Host "-> Maximum (180 deg)"
    Send-ServoPulse -PulseMs 2.0

    Write-Host "-> Back to center (90 deg)"
    Send-ServoPulse -PulseMs 1.5

} finally {
    $rawFtdi.Write($D7_LO, 3, [ref]0) | Out-Null
    $dev.Close()
}
```

You should see the servo arm swing to each position. If it does not move,
see the Troubleshooting section.

> **Beginner**: `$Cycles = 25` sends 25 pulses = ~500 ms hold at each position.
> Increase this number to hold longer. The servo moves immediately on each
> `Write()` call — the `while` spin-wait just keeps the pin HIGH long enough
> for the servo to recognize the pulse width.

> **Scripter**: `PulseMs` only accepts 1.0, 1.5, or 2.0 here because
> `Start-Sleep` in 1 ms increments is the resolution limit. Non-integer
> values will be rounded by the OS scheduler anyway. Step 3 adds proper
> degree-to-pulse mapping and sub-ms resolution.

---

## Step 3 - Precise Position Script (Single Servo)

### FTDI Setup and Pulse Timing

Two setup steps before any servo loop:
- `SetLatency(1)` — reduces the FTDI USB latency timer from 16 ms to 1 ms. Without this, each `Write()` stalls for a USB IN token, inflating write time and distorting period.
- **Stopwatch spin-wait** — uses the CPU performance counter (~10 MHz) for accurate 1-2 ms pulse widths. Unlike `timeBeginPeriod(1)` + `Start-Sleep`, a spin-wait requires no `Add-Type` and is immune to OS scheduler granularity (scope-confirmed: `Start-Sleep` still snaps to 15.625 ms ticks even with `timeBeginPeriod(1)` in PowerShell).

`Start-Sleep` is still used for the ~18 ms LOW period. Imprecision there only shifts the overall frequency (from 50 Hz toward 40-60 Hz), which all RC servos tolerate.

### Set-Servo function

Maps degrees (0-180) to a pulse width (1.0-2.0 ms) and sends the requested
number of cycles. Uses raw `0x80` MPSSE writes and a Stopwatch spin-wait for
accurate pulse timing on D4-D7 (ADBUS GPIO).

```powershell
$rawFtdi = $dev._connection.Device   # FTD2XX_NET.FTDI handle
$rawFtdi.SetLatency(1) | Out-Null    # reduce USB latency timer from 16 ms to 1 ms

$sw     = [System.Diagnostics.Stopwatch]::new()
$swFreq = [System.Diagnostics.Stopwatch]::Frequency   # ~10 MHz HPET on Windows

function Set-Servo {
    param(
        [double]$Degrees,          # 0 to 180
        [int]$AdBusPin  = 7,       # D-bus GPIO pin (D4-D7; default D7 = ADBUS7)
        [int]$Cycles    = 50,      # number of ~20 ms pulses to send (50 = ~1 second)
        [double]$MinMs  = 1.0,     # pulse width at 0 deg (adjust for your servo)
        [double]$MaxMs  = 2.0      # pulse width at 180 deg (adjust for your servo)
    )

    if ($Degrees -lt 0)   { $Degrees = 0 }
    if ($Degrees -gt 180) { $Degrees = 180 }

    $pulseMs    = $MinMs + ($Degrees / 180.0) * ($MaxMs - $MinMs)
    $pulseTicks = [long]($pulseMs * $swFreq / 1000.0)   # convert ms to SW ticks
    $lowMs      = 20.0 - $pulseMs

    # MPSSE 0x80 = Set Data Bits Low Byte (ADBUS / D-bus)
    $pinMask = [byte](1 -shl $AdBusPin)
    $highCmd = [byte[]](0x80, $pinMask, 0xFF)   # pin HIGH, all D-bus as outputs
    $lowCmd  = [byte[]](0x80, 0x00,    0xFF)    # all D-bus LOW

    $w = 0
    for ($i = 0; $i -lt $Cycles; $i++) {
        $rawFtdi.Write($highCmd, 3, [ref]$w) | Out-Null
        $sw.Restart()
        while ($sw.ElapsedTicks -lt $pulseTicks) {}   # spin-wait: ~1 us accuracy
        $rawFtdi.Write($lowCmd, 3, [ref]$w) | Out-Null
        Start-Sleep -Milliseconds $lowMs              # low period; OS granularity OK
    }
}
```

> **Engineer**: `0x80` is the MPSSE "Set Data Bits Low Byte" (ADBUS / D-bus)
> command. Byte 1 = output value; byte 2 = direction mask (0xFF = all 8 ADBUS
> bits as outputs; use `0x80` to set D7 output only and leave D4-D6 as inputs).
> One 3-byte USB write per edge — two writes per period. The MPSSE engine drives
> the pin level immediately on receipt. Use `0x82` instead to control ACBUS
> (C0-C7) pins.

> **Scripter**: `$rawFtdi = $dev._connection.Device` accesses the FTD2XX_NET
> .NET object directly. Two separate issues affect timing: (1) USB latency
> timer — `SetLatency(1)` drops write stall from 16 ms to ~1 ms, essential;
> (2) `Start-Sleep` OS timer granularity — snaps to 15.625 ms ticks even with
> `timeBeginPeriod(1)` in PowerShell (scope-confirmed: 20.83 Hz / 33% duty).
> Solution: Stopwatch spin-wait for the 1-2 ms pulse (accurate to ~1 us,
> no `Add-Type` needed), `Start-Sleep` for the ~18 ms low period (imprecision
> there only shifts frequency slightly, which servos tolerate).

### Sweep demo

```powershell
# $rawFtdi, $sw, $swFreq are initialised in the Set-Servo block above.

try {
    # Sweep from 0 to 180 degrees in 10 degree increments
    for ($deg = 0; $deg -le 180; $deg += 10) {
        Write-Host "Position: $deg deg"
        Set-Servo -Degrees $deg -Cycles 30   # hold ~600 ms at each position
    }

    # Sweep back
    for ($deg = 180; $deg -ge 0; $deg -= 10) {
        Write-Host "Position: $deg deg"
        Set-Servo -Degrees $deg -Cycles 30
    }

    # Park at center
    Set-Servo -Degrees 90 -Cycles 25

} finally {
    $rawFtdi.Write([byte[]](0x80, 0x00, 0xFF), 3, [ref]0) | Out-Null
    $dev.Close()
}
```

> **Beginner**: the servo moves to each position and holds for about 0.6 seconds
> (30 cycles x ~20 ms). Increase `-Cycles` to hold longer.

> **Pro**: the Stopwatch spin-wait resolves pulse width to ~1 us — 1000x
> better than `timeBeginPeriod(1)` + `Start-Sleep`. All 180 degree positions
> are achievable. For multi-servo or zero-CPU-overhead positioning, use the
> async bit-bang approach in the next section; for single-servo use the
> Stopwatch approach here.

---

## Speeding Up and Resolution Limits

### Raw MPSSE write path

The `Set-Servo` function above uses a Stopwatch spin-wait for the pulse and
`Start-Sleep` for the low period. Achieved characteristics:

- Pulse width accuracy: ~1 us (Stopwatch performance counter)
- Overall frequency: ~45-55 Hz (depends on `Start-Sleep` OS tick)
- Angular resolution: continuous (not discrete) across 0-180 deg

**Measured signal characteristics (FT232H ADBUS D7, scope, SG90 servo):**

| Setup | Freq | Duty+ | Pulse width | Result |
|-------|------|-------|-------------|--------|
| Default (no SetLatency, Start-Sleep) | 20 Hz | 40% | ~20 ms | Servo stuck at max |
| SetLatency(1), Start-Sleep for pulse | 20.83 Hz | 33% | ~16 ms | Servo still stuck |
| SetLatency(1), Stopwatch spin-wait | ~50 Hz | ~7.5% | 1.5 ms | Servo responds correctly |
| Target (RC servo spec) | 50 Hz | 7.5% | 1.5 ms | Ideal |

Signal amplitude: 3.43 V (FT232H ADBUS at 4 mA drive, 3.3 V nominal).

> **Engineer**: two independent timing issues exist. (1) USB latency timer:
> `FT_SetLatencyTimer` default 16 ms causes each `Write()` to stall; fix with
> `SetLatency(1)`. (2) OS timer granularity: `Start-Sleep` in PowerShell snaps
> to the 15.625 ms Windows scheduler tick (20.83 Hz / 33% duty scope-confirmed)
> even after `timeBeginPeriod(1)` — `Add-Type` type caching prevents reliable
> re-registration. Fix: Stopwatch spin-wait for the 1-2 ms pulse only.
> `[System.Diagnostics.Stopwatch]::Frequency` is typically 10,000,000 Hz
> (HPET) on modern Windows, giving ~100 ns per tick — well within servo spec.

### Async bit-bang streaming (multi-servo)

The async bit-bang approach pre-builds a buffer where each byte represents one
GPIO snapshot held for a fixed duration. The FTDI chip clocks the bytes out
autonomously at the programmed baud rate — no host CPU involvement during
transmission.

**Key insight**: at 100,000 baud, each byte is output for exactly 10 us. A
full 20 ms servo period = 2000 bytes. A 1.5 ms pulse = 150 bytes HIGH
followed by 1850 bytes LOW. Changing the HIGH/LOW byte boundary gives ~10 us
pulse resolution = approximately **100 discrete positions** across 0-180 deg.

Up to 8 servos can share the same buffer — one bit per servo per byte.

```powershell
# Async bit-bang: streams pre-computed servo pulses at hardware clock speed
# Requires ADBUS wiring (ADBUS0 = servo 0, ADBUS1 = servo 1, etc.)

$dev = New-PsGadgetFtdi -Index 0
Set-PsGadgetFtdiMode -PsGadget $dev -Mode AsyncBitBang -Mask 0xFF   # all ADBUS pins output

# Set baud rate: this controls the byte clock rate
# 100000 baud = 100000 bytes/sec = 10 us/byte
# Each 20 ms servo period = 2000 bytes
$dev._connection.Device.SetBaudRate(100000) | Out-Null

function Build-ServoPwmBuffer {
    param(
        [double[]]$DegreesPerServo,   # array of target degrees, one per servo (index 0-7)
        [int]$Periods = 50,           # number of complete 20 ms cycles to generate
        [double]$MinMs = 1.0,
        [double]$MaxMs = 2.0
    )

    $bytesPerPeriod = 2000    # at 100000 baud: 2000 bytes = 20 ms

    # Pre-compute high-sample count (how many bytes the pin stays HIGH) per servo
    $highSamples = @()
    for ($s = 0; $s -lt $DegreesPerServo.Count; $s++) {
        $deg = [math]::Max(0, [math]::Min(180, $DegreesPerServo[$s]))
        $pulseMs = $MinMs + ($deg / 180.0) * ($MaxMs - $MinMs)
        $highSamples += [int]($pulseMs * 100)   # 100 samples/ms at 100000 baud
    }

    # Build the buffer
    $buf = [byte[]]::new($bytesPerPeriod * $Periods)
    for ($p = 0; $p -lt $Periods; $p++) {
        $base = $p * $bytesPerPeriod
        for ($b = 0; $b -lt $bytesPerPeriod; $b++) {
            [byte]$snapshot = 0
            for ($s = 0; $s -lt $highSamples.Count; $s++) {
                if ($b -lt $highSamples[$s]) {
                    $snapshot = $snapshot -bor [byte](1 -shl $s)
                }
            }
            $buf[$base + $b] = $snapshot
        }
    }
    return $buf
}

# Example: two servos
# Servo 0 on ADBUS0 -> 45 deg, Servo 1 on ADBUS1 -> 135 deg
$buf = Build-ServoPwmBuffer -DegreesPerServo @(45.0, 135.0) -Periods 50

$w = 0
$dev._connection.Device.Write($buf, $buf.Length, [ref]$w) | Out-Null
Write-Host "Wrote $w bytes"

# De-energize all pins after streaming
$dev._connection.Device.Write([byte[]](0x00), 1, [ref]$w) | Out-Null

Set-PsGadgetFtdiMode -PsGadget $dev -Mode UART
$dev.Close()
```

> **Engineer**: the buffer is a 2D time x servo matrix collapsed into a flat
> byte array. Bit `s` of byte `b` within a period is HIGH if `b < highSamples[s]`;
> LOW otherwise. Since all servo pulses start at byte 0 of each period (the 50 Hz
> rising edge is synchronized), up to 8 servos receive a coherent frame-aligned
> update with zero inter-servo skew.

> **Scripter**: to change position, rebuild the buffer with new degree values and
> stream again. The servo will snap to the new position after the current buffer
> drains. Add a double-buffer scheme in C# (via `Add-Type`) if you need
> continuous real-time updates.

> **Pro**: The FTDI TX FIFO is 256 bytes (FT232R) or 4096 bytes (FT232H).
> Buffers larger than the FIFO depth are automatically chunked by the D2XX
> driver. For very long streaming sequences (> 1 s), the host CPU must keep
> up with buffer re-fills or gaps will appear in the output. Use the
> FT232H for multi-servo work; its larger FIFO reduces re-fill pressure.

---

## Troubleshooting

### Device appears twice in List-PsGadgetFtdi (VCP driver conflict)

Symptom: `List-PsGadgetFtdi -ShowVCP` shows the same device at two different
indices — one as a D2XX device and one as a COM port (e.g. COM11). Serial
numbers match except the VCP entry has a trailing `A`.

Affected chips and default state:

| Chip    | Factory EEPROM default | VCP on by default? |
|---------|------------------------|--------------------|
| FT232H  | `IsVCP = True` on some breakout boards | Sometimes |
| FT232R  | `RIsD2XX = False`      | Almost always      |

For FT232R this is the expected out-of-box state — the chip enumerates as a
COM port by design until you set `RIsD2XX=True`. CBUS bit-bang and async
bit-bang both require D2XX exclusive access via `SetBitMode`; neither works
while `ftdibus.sys` holds the interface.

Root cause: Windows loads both `ftdibus.sys` (VCP driver → COM port) and
`ftd2xx.dll` for the same physical chip. The VCP driver holds partial
ownership of the hardware interface. `SetBitMode` returns `FT_OK` but the
mode change has no effect — all GPIO commands succeed without error but
produce no electrical output.

Quick workaround (no replug needed):
```
Device Manager -> Ports (COM & LPT) -> USB Serial Port (COMxx) -> Disable device
```
Servos will work until the next reboot or replug reloads the driver.

Permanent fix:
```powershell
# Confirm EEPROM state
Get-PsGadgetFtdiEeprom -Index 0
# FT232H: look for IsVCP : True
# FT232R: look for RIsD2XX : False

# Write EEPROM to disable VCP (non-volatile, survives power cycle)
Set-PsGadgetFtdiEeprom -Index 0 -DisableVcp
# Accept the prompt to cycle the USB port, or replug manually.

# Verify: single D2XX entry, no COM port
List-PsGadgetFtdi -ShowVCP | Format-Table
Get-PsGadgetFtdiEeprom -Index 0   # IsVCP : False (FT232H) or RIsD2XX : True (FT232R)
```

> **Beginner**: after running `Set-PsGadgetFtdiEeprom -Index 0 -DisableVcp`
> and replugging the USB cable, the COM port entry disappears from Device
> Manager. The FTDI adapter still works for everything — you just cannot use
> it as a plain serial port any more. If you ever need the COM port back, run
> `Set-PsGadgetFtdiEeprom -Index 0 -EnableVcp`.

### FT232H signal is wrong frequency on scope (~20 Hz instead of 50 Hz)

Two independent root causes produce similar ~20 Hz symptoms. Diagnose by
the duty cycle:

**Cause A: USB latency timer (20 Hz, ~40% duty)**

Each `Write()` stalls up to 16 ms waiting for a USB IN token (default latency
timer = 16 ms). Two stalls per cycle expand the period from 20 ms to ~50 ms
and the 1.5 ms pulse inflates to ~20 ms.

Fix:
```powershell
$rawFtdi.SetLatency(1) | Out-Null   # call immediately after OpenByIndex
```

**Cause B: `Start-Sleep` OS timer granularity (20.83 Hz, ~33% duty)**

`Start-Sleep -Milliseconds 1.5` snaps to the 15.625 ms Windows scheduler tick
even after `timeBeginPeriod(1)`. Scope result: 1 tick HIGH (15.6 ms) + 2 ticks
LOW (31.25 ms) = 46.9 ms period / 20.83 Hz / 33% duty. `timeBeginPeriod(1)`
is unreliable in PowerShell because `Add-Type` caches the compiled type
definition and silently skips re-registration in some sessions.

Fix: use a Stopwatch spin-wait for the pulse:
```powershell
$sw     = [System.Diagnostics.Stopwatch]::new()
$swFreq = [System.Diagnostics.Stopwatch]::Frequency

# In the servo loop:
$pulseTicks = [long]($pulseMs * $swFreq / 1000.0)
$rawFtdi.Write($highCmd, 3, [ref]$w) | Out-Null
$sw.Restart()
while ($sw.ElapsedTicks -lt $pulseTicks) {}   # spin-wait: ~1 us accuracy
$rawFtdi.Write($lowCmd,  3, [ref]$w) | Out-Null
Start-Sleep -Milliseconds $lowMs              # low period; imprecision OK here
```

With both fixes applied, expected scope: ~50 Hz, ~7.5% duty, 1.5 ms pulse.

### Servo does not move at all

- **Check for VCP driver conflict first.** This is the most common cause of
  silent GPIO failure on both FT232H and FT232R. FT232R ships with VCP enabled
  by default (`RIsD2XX=False`); FT232H may also have `IsVCP=True` from the
  factory. Run `List-PsGadgetFtdi -ShowVCP | Format-Table` — if the device
  appears twice (D2XX entry + COM port entry), see the section above.
- Check power: the servo power (red) wire must be connected to an external
  5 V supply **and** that supply's GND must be connected to the FTDI GND.
  A servo with no shared ground will not respond to the signal.
- Confirm signal polarity: the signal pin must go HIGH during the pulse, not
  LOW. Verify `Set-PsGadgetGpio -State HIGH` actually pulls ACBUS0 high by
  measuring with a multimeter (expect ~3.3 V when HIGH, ~0 V when LOW).
- Verify the FTDI device listed with `List-PsGadgetFtdi` has `GpioMethod : MPSSE`
  (FT232H). If it shows `CBUS`, you have an FT232R and must use the async
  bit-bang (ADBUS) wiring for anything beyond 3 positions.
- Run the smoke test with a simple LED on ACBUS0 first to confirm the GPIO
  path works before adding the servo.

### Servo twitches or buzzes continuously

- The servo is receiving inconsistent pulse widths and its position loop is
  hunting. Two common causes:
  - **Pulse using `Start-Sleep`**: OS timer snaps to 15.625 ms ticks, producing
    a wildly inconsistent pulse. Replace with the Stopwatch spin-wait from the
    Set-Servo function in Step 3 — accurate to ~1 us regardless of system load.
  - **Spin-wait thread preempted**: the Stopwatch spin-wait occupies one CPU
    core at 100% for 1-2 ms per cycle. On a heavily loaded system the thread
    may occasionally be preempted, causing a single long pulse. For production
    use, switch to the async bit-bang approach which removes the host CPU from
    the timing path entirely.

### Position is wrong or inconsistent

- **Servo min/max calibration**: the standard 1.0-2.0 ms range is a guideline.
  Some servos use 0.5-2.5 ms for a wider travel range; others stop at 0.9 ms
  or 2.1 ms. Adjust `-MinMs` and `-MaxMs` in `Set-Servo` to match your servo.
  Start with the center (1.5 ms) and observe which direction is "true" neutral.
- **Timer jitter at sub-ms values**: with `Start-Sleep` for the pulse, all
  values between 1.0 and 2.0 ms snap to the same 15.625 ms OS tick. Use the
  Stopwatch spin-wait in Set-Servo — it handles fractional ms accurately.

### Servo only reaches two positions

`Start-Sleep` for the pulse is snapping to the 15.625 ms OS timer tick. At
that granularity, `Start-Sleep -Milliseconds 1.0`, `1.5`, and `2.0` all
round to the same value, so the servo receives the same effective pulse width
regardless of the angle command.

Replace the `Start-Sleep` for the pulse with a Stopwatch spin-wait (see the
Set-Servo function in Step 3). The `Start-Sleep` for the low period (~18 ms)
can remain — imprecision there only affects frequency, not servo position.

---

## Quick Reference (Pro)

```powershell
# Load module
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1
$dev     = New-PsGadgetFtdi -Index 0
$rawFtdi = $dev._connection.Device   # FTD2XX_NET.FTDI handle
$rawFtdi.SetLatency(1) | Out-Null    # reduce USB latency timer from 16 ms to 1 ms

# Stopwatch for accurate pulse timing (no Add-Type/timeBeginPeriod needed)
$sw     = [System.Diagnostics.Stopwatch]::new()
$swFreq = [System.Diagnostics.Stopwatch]::Frequency   # ~10 MHz HPET

function Set-Servo {
    param([double]$Degrees, [int]$AdBusPin=7, [int]$Cycles=50,
          [double]$MinMs=1.0, [double]$MaxMs=2.0)
    if ($Degrees -lt 0)   { $Degrees = 0 }
    if ($Degrees -gt 180) { $Degrees = 180 }
    $pulseMs    = $MinMs + ($Degrees/180.0)*($MaxMs-$MinMs)
    $pulseTicks = [long]($pulseMs * $swFreq / 1000.0)
    $pin = [byte](1 -shl $AdBusPin)   # D7 = 0x80
    $hi  = [byte[]](0x80,$pin,0xFF)   # MPSSE 0x80 = Set ADBUS low byte
    $lo  = [byte[]](0x80,0x00,0xFF)
    $w   = 0
    for ($i=0;$i -lt $Cycles;$i++) {
        $rawFtdi.Write($hi,3,[ref]$w) | Out-Null
        $sw.Restart(); while ($sw.ElapsedTicks -lt $pulseTicks) {}   # spin-wait
        $rawFtdi.Write($lo,3,[ref]$w) | Out-Null
        Start-Sleep -Milliseconds (20 - $pulseMs)   # low period; OS granularity OK
    }
}

try {
    Set-Servo -Degrees 90   # center
    Set-Servo -Degrees 0    # min
    Set-Servo -Degrees 180  # max
    Set-Servo -Degrees 90   # center
} finally {
    $rawFtdi.Write([byte[]](0x80,0x00,0xFF),3,[ref]0) | Out-Null
    $dev.Close()
}
```

**Pulse width reference (1.0-2.0 ms range):**

| Degrees | Pulse width | Notes |
|---------|-------------|-------|
| 0       | 1.0 ms      | Full CCW / minimum |
| 45      | 1.25 ms     | Quarter travel |
| 90      | 1.5 ms      | Center / neutral |
| 135     | 1.75 ms     | Three-quarter travel |
| 180     | 2.0 ms      | Full CW / maximum |

**Async bit-bang (multi-servo, sub-ms resolution):**

```powershell
Set-PsGadgetFtdiMode -PsGadget $dev -Mode AsyncBitBang -Mask 0xFF
$dev._connection.Device.SetBaudRate(100000) | Out-Null
# --- build buffer with Build-ServoPwmBuffer, then: ---
$dev._connection.Device.Write($buf, $buf.Length, [ref]$w) | Out-Null
Set-PsGadgetFtdiMode -PsGadget $dev -Mode UART
```

---

## Practical Example: Pan-Tilt Laser Rig

Two servos on D7 (ADBUS7, pan) and D6 (ADBUS6, tilt) position a laser pointer.

```powershell
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1

$dev     = New-PsGadgetFtdi -Index 0
$rawFtdi = $dev._connection.Device
$rawFtdi.SetLatency(1) | Out-Null    # required: default 16 ms kills servo timing
$sw     = [System.Diagnostics.Stopwatch]::new()
$swFreq = [System.Diagnostics.Stopwatch]::Frequency

function Set-TwoServos {
    param(
        [double]$PanDeg,
        [double]$TiltDeg,
        [int]$Cycles = 50,
        [double]$MinMs = 1.0,
        [double]$MaxMs = 2.0
    )
    if ($PanDeg  -lt 0)   { $PanDeg  = 0 }
    if ($PanDeg  -gt 180) { $PanDeg  = 180 }
    if ($TiltDeg -lt 0)   { $TiltDeg = 0 }
    if ($TiltDeg -gt 180) { $TiltDeg = 180 }

    $panMs  = $MinMs + ($PanDeg  / 180.0) * ($MaxMs - $MinMs)
    $tiltMs = $MinMs + ($TiltDeg / 180.0) * ($MaxMs - $MinMs)

    $shortMs    = [math]::Min($panMs, $tiltMs)
    $longMs     = [math]::Max($panMs, $tiltMs)
    $shortTicks = [long]($shortMs * $swFreq / 1000.0)
    $longTicks  = [long]($longMs  * $swFreq / 1000.0)

    # Pan = D7 (bit 7 = 0x80), Tilt = D6 (bit 6 = 0x40)
    $bothHi   = [byte](0xC0)   # D7 + D6 HIGH
    $panOnly  = [byte](0x80)   # D7 only HIGH
    $tiltOnly = [byte](0x40)   # D6 only HIGH

    $w = 0
    for ($i = 0; $i -lt $Cycles; $i++) {
        $rawFtdi.Write([byte[]](0x80, $bothHi, 0xFF), 3, [ref]$w) | Out-Null
        $sw.Restart()
        while ($sw.ElapsedTicks -lt $shortTicks) {}   # wait for shorter pulse
        if ($panMs -le $tiltMs) {
            $rawFtdi.Write([byte[]](0x80, $tiltOnly, 0xFF), 3, [ref]$w) | Out-Null
        } else {
            $rawFtdi.Write([byte[]](0x80, $panOnly,  0xFF), 3, [ref]$w) | Out-Null
        }
        while ($sw.ElapsedTicks -lt $longTicks) {}    # wait for longer pulse
        $rawFtdi.Write([byte[]](0x80, 0x00, 0xFF), 3, [ref]$w) | Out-Null
        Start-Sleep -Milliseconds (20.0 - $longMs)    # low period
    }
}

function Invoke-Fire {
    Write-Host "  FIRE"
    # Pulse D5 (ADBUS5, bit 5 = 0x20) HIGH for 200 ms if laser trigger is wired there:
    # $rawFtdi.Write([byte[]](0x80, 0x20, 0xFF), 3, [ref]0) | Out-Null
    # Start-Sleep -Milliseconds 200
    # $rawFtdi.Write([byte[]](0x80, 0x00, 0xFF), 3, [ref]0) | Out-Null
}

try {
    Write-Host "Centering both servos..."
    Set-TwoServos -PanDeg 90 -TiltDeg 90 -Cycles 50

    Write-Host "Aiming at target 1..."
    Set-TwoServos -PanDeg 45 -TiltDeg 70 -Cycles 75
    Invoke-Fire

    Write-Host "Aiming at target 2..."
    Set-TwoServos -PanDeg 135 -TiltDeg 60 -Cycles 75
    Invoke-Fire

    Write-Host "Aiming at target 3..."
    Set-TwoServos -PanDeg 90 -TiltDeg 120 -Cycles 75
    Invoke-Fire

    Write-Host "Returning to center..."
    Set-TwoServos -PanDeg 90 -TiltDeg 90 -Cycles 50

} finally {
    $rawFtdi.Write([byte[]](0x80, 0x00, 0xFF), 3, [ref]0) | Out-Null
    $dev.Close()
}
```

> **Beginner**: pan is left-right rotation; tilt is up-down angle. D7 controls
> the pan servo; D6 controls the tilt servo. Each call to `Set-TwoServos` moves
> both servos simultaneously to the requested position and holds for `$Cycles`
> pulses (50 cycles = ~1 second).

> **Scripter**: both pins share the same 20 ms frame but have different pulse
> widths. The function raises both HIGH simultaneously, uses Stopwatch ticks to
> precisely time when the shorter pulse ends, drops that pin, then waits for the
> longer pulse to end before going LOW. This gives each servo an accurate
> independent pulse within the same period.

> **Engineer**: Stopwatch ticks resolve to ~100 ns (10 MHz HPET), giving ~1 us
> effective accuracy per pulse edge. Both servos are aligned to the same rising
> edge (zero inter-servo skew). For >4 servos or sub-100 us resolution, switch
> to async bit-bang (see Speeding Up section) using bits 4-7 of ADBUS.

> **Pro**: `Set-TwoServos` is blocking — occupies the PowerShell thread for
> `$Cycles * ~20 ms`. For real-time position updates, move the loop into a
> `RunspacePool` thread and pass new degree targets via a
> `[System.Collections.Concurrent.ConcurrentQueue]`. The async bit-bang buffer
> approach is cleaner for that use case since you rebuild and re-stream from
> the worker thread on each position change.

**Pan-tilt position reference:**

| Pan | Tilt | Pan pulse | Tilt pulse | Description |
|-----|------|-----------|------------|-------------|
| 0   | 90   | 1.0 ms    | 1.5 ms     | Full left, level |
| 45  | 90   | 1.25 ms   | 1.5 ms     | Left quarter, level |
| 90  | 90   | 1.5 ms    | 1.5 ms     | Center, level |
| 135 | 90   | 1.75 ms   | 1.5 ms     | Right quarter, level |
| 180 | 90   | 2.0 ms    | 1.5 ms     | Full right, level |
| 90  | 45   | 1.5 ms    | 1.25 ms    | Center, angled down |
| 90  | 135  | 1.5 ms    | 1.75 ms    | Center, angled up |



