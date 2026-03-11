# Example: Servo Control with FT232H (ACBUS) or FT232R (Async Bit-Bang)

Drive a standard RC hobby servo directly from an FTDI USB adapter using
software-generated PWM — no dedicated PWM driver board required.

Two hardware approaches are covered:

- **FT232H / MPSSE + timeBeginPeriod(1)** — ACBUS0 drives a single servo
  with 1 ms timer resolution. Recommended for one or two servos.
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
  - [Wiring - FT232H ACBUS0 (single servo)](#wiring---ft232h-acbus0-single-servo)
  - [Wiring - FT232R or FT232H Async Bit-Bang (multi-servo)](#wiring---ft232r-or-ft232h-async-bit-bang-multi-servo)
  - [Power Considerations](#power-considerations)
- [Step 1 - Install Drivers and Verify Detection](#step-1---install-drivers-and-verify-detection)
- [Step 2 - Smoke Test: Move to Three Positions](#step-2---smoke-test-move-to-three-positions)
- [Step 3 - Precise Position Script (Single Servo)](#step-3---precise-position-script-single-servo)
  - [Fix Windows Timer Resolution](#fix-windows-timer-resolution)
  - [Set-Servo function](#set-servo-function)
  - [Sweep demo](#sweep-demo)
- [Speeding Up and Resolution Limits](#speeding-up-and-resolution-limits)
  - [Raw MPSSE write path](#raw-mpsse-write-path)
  - [Async bit-bang streaming (multi-servo)](#async-bit-bang-streaming-multi-servo)
- [Troubleshooting](#troubleshooting)
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
Windows, the default timer fires at ~15.625 ms. After calling
`timeBeginPeriod(1)`, resolution improves to ~1 ms. That gives
approximately **10 discrete positions** across the 1.0-2.0 ms range —
enough for basic demos and point-to-point positioning, but not analog
smoothness.

### The Two Software PWM Approaches

| Approach | Resolution | Servos | Chip | Notes |
|---|---|---|---|---|
| `timeBeginPeriod(1)` + MPSSE GPIO | ~10 positions (1 ms steps) | 1-4 | FT232H | Simplest code; ACBUS pins |
| `timeBeginPeriod(1)` + raw MPSSE write | ~10 positions | 1-4 | FT232H | Lower overhead; same wiring |
| Async bit-bang streaming | ~50 positions (sub-ms) | up to 8 | FT232H or FT232R | Best resolution; ADBUS wiring |

> **Engineer**: the async bit-bang approach streams a pre-computed byte
> buffer representing multiple PWM periods. The FTDI chip clocks each byte
> out at the programmed baud rate independently of the host CPU. At
> 100,000 baud (10 us/byte) you can represent each 20 ms servo period as
> a 2000-byte buffer with ~10 us pulse resolution — far better than the
> 1 ms software approach. The tradeoff is that changing position requires
> rebuilding the buffer and re-streaming.

### Wiring - FT232H ACBUS0 (single servo)

Connect ACBUS0 to the servo signal wire. Use a separate 5 V supply for the
servo power rail.

| FT232H pin | Signal   | Servo wire        |
|-----------|----------|-------------------|
| ACBUS0    | Signal   | Signal (yellow/white/orange) |
| GND       | Ground   | Ground (brown/black) — shared with servo supply GND |
| *(separate 5 V supply)* | — | Power (red/orange) |

> **Beginner**: the GND (ground) of the FTDI adapter and the GND of the servo
> power supply MUST be connected together. Otherwise the servo signal has no
> reference and will not work, or may damage the FTDI output.

> **Engineer**: FT232H ACBUS0 in MPSSE mode is driven by the `0x82` high-byte
> command. Output voltage is 3.3 V when VIO is at 3.3 V (default). Check your
> servo signal threshold — most SG90 and MG996R variants accept 3.3 V signal.

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

---

## Step 2 - Smoke Test: Move to Three Positions

This test uses `timeBeginPeriod(1)` to get 1 ms resolution and sends pulses
manually. Three positions only (1 ms, 1.5 ms, 2 ms = 0, 90, 180 degrees).

```powershell
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1

# Fix Windows timer resolution from ~15 ms to ~1 ms
Add-Type -MemberDefinition '
    [DllImport("winmm.dll")] public static extern int timeBeginPeriod(int t);
    [DllImport("winmm.dll")] public static extern int timeEndPeriod(int t);
' -Name 'WinTimer' -Namespace 'Win32' -ErrorAction SilentlyContinue

[Win32.WinTimer]::timeBeginPeriod(1)

$dev = New-PsGadgetFtdi -Index 0

function Send-ServoPulse {
    param(
        [Parameter(Mandatory)]$PsGadget,
        [int]$PinAcbus = 0,
        [double]$PulseMs = 1.5,      # 1.0 = 0 deg, 1.5 = 90 deg, 2.0 = 180 deg
        [int]$Cycles   = 25          # 25 cycles at 20 ms period = 500 ms hold
    )
    $lowMs = 20 - $PulseMs
    for ($i = 0; $i -lt $Cycles; $i++) {
        Set-PsGadgetGpio -PsGadget $PsGadget -Pins @($PinAcbus) -State HIGH
        Start-Sleep -Milliseconds $PulseMs
        Set-PsGadgetGpio -PsGadget $PsGadget -Pins @($PinAcbus) -State LOW
        Start-Sleep -Milliseconds $lowMs
    }
}

try {
    Write-Host "-> Center (90 deg)"
    Send-ServoPulse -PsGadget $dev -PulseMs 1.5

    Write-Host "-> Minimum (0 deg)"
    Send-ServoPulse -PsGadget $dev -PulseMs 1.0

    Write-Host "-> Maximum (180 deg)"
    Send-ServoPulse -PsGadget $dev -PulseMs 2.0

    Write-Host "-> Back to center (90 deg)"
    Send-ServoPulse -PsGadget $dev -PulseMs 1.5

} finally {
    [Win32.WinTimer]::timeEndPeriod(1)
    # Stop sending pulses - servo will hold last position briefly then go limp
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0) -State LOW
    $dev.Close()
}
```

You should see the servo arm swing to each position. If it does not move,
see the Troubleshooting section.

> **Beginner**: `$Cycles = 25` sends 25 pulses at 50 Hz = 0.5 seconds of
> hold time at each position. Increase this number to hold longer.

> **Scripter**: `PulseMs` only accepts 1.0, 1.5, or 2.0 here because
> `Start-Sleep` in 1 ms increments is the resolution limit. Non-integer
> values will be rounded by the OS scheduler anyway. Step 3 adds proper
> degree-to-pulse mapping and sub-ms resolution.

---

## Step 3 - Precise Position Script (Single Servo)

### Fix Windows Timer Resolution

This was covered in Step 2. Add the `Add-Type` block once at the top of your
script and call `timeBeginPeriod(1)` before any servo loop.

```powershell
Add-Type -MemberDefinition '
    [DllImport("winmm.dll")] public static extern int timeBeginPeriod(int t);
    [DllImport("winmm.dll")] public static extern int timeEndPeriod(int t);
' -Name 'WinTimer' -Namespace 'Win32' -ErrorAction SilentlyContinue
[Win32.WinTimer]::timeBeginPeriod(1)
```

### Set-Servo function

Maps degrees (0-180) to a pulse width (1.0-2.0 ms) and sends the requested
number of 50 Hz cycles. Uses the raw MPSSE write path for lower overhead.

```powershell
$rawFtdi = $dev._connection.Device   # FTD2XX_NET.FTDI handle

function Set-Servo {
    param(
        [double]$Degrees,        # 0 to 180
        [int]$AcbusPin  = 0,     # ACBUS pin number (0 = ACBUS0)
        [int]$Cycles    = 50,    # number of 20 ms pulses to send (50 = 1 second)
        [double]$MinMs  = 1.0,   # pulse width at 0 deg (adjust for your servo)
        [double]$MaxMs  = 2.0    # pulse width at 180 deg (adjust for your servo)
    )

    # Clamp to valid range
    if ($Degrees -lt 0)   { $Degrees = 0 }
    if ($Degrees -gt 180) { $Degrees = 180 }

    $pulseMs = $MinMs + ($Degrees / 180.0) * ($MaxMs - $MinMs)
    $lowMs   = 20.0 - $pulseMs

    # Pre-build MPSSE command bytes: 0x82 = Set ACBUS high byte
    # bit mask for this ACBUS pin
    $pinMask = [byte](1 -shl $AcbusPin)
    $highCmd = [byte[]](0x82, $pinMask, 0xFF)   # pin HIGH
    $lowCmd  = [byte[]](0x82, 0x00,     0xFF)   # all ACBUS LOW

    $w = 0
    for ($i = 0; $i -lt $Cycles; $i++) {
        $rawFtdi.Write($highCmd, 3, [ref]$w) | Out-Null
        Start-Sleep -Milliseconds $pulseMs
        $rawFtdi.Write($lowCmd,  3, [ref]$w) | Out-Null
        Start-Sleep -Milliseconds $lowMs
    }
}
```

> **Engineer**: `0x82` is the MPSSE "Set Data Bits High Byte" (ACBUS)
> command. Byte 1 is the output value; byte 2 is the direction mask (0xFF =
> all 8 ACBUS bits as outputs). One 3-byte USB write per edge — two writes
> per period. The MPSSE engine drives the pin level immediately on receipt.

> **Scripter**: `$rawFtdi = $dev._connection.Device` accesses the underlying
> FTD2XX_NET .NET object directly, bypassing PSGadget cmdlet overhead. This
> saves ~3-5 ms per period compared to going through `Set-PsGadgetGpio`. For
> a servo loop sending 50 pulses/sec that 3 ms matters — it can throw the
> 20 ms period off by 15%.

### Sweep demo

```powershell
$rawFtdi = $dev._connection.Device

[Win32.WinTimer]::timeBeginPeriod(1)

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
    [Win32.WinTimer]::timeEndPeriod(1)
    $w = 0
    $rawFtdi.Write([byte[]](0x82, 0x00, 0xFF), 3, [ref]$w) | Out-Null
    $dev.Close()
}
```

> **Beginner**: the servo moves to each position and holds for about 0.6 seconds
> (30 cycles x 20 ms). If you increase `-Cycles` it holds longer. Decrease it
> to speed up the sweep.

> **Pro**: at 1 ms timer resolution, `pulseMs` values of 1.0, 1.5, and 2.0
> map to 0, 90, and 180 degrees reliably. Values in between (e.g. 1.3 ms for
> ~54 deg) rely on the OS scheduler honoring sub-millisecond sleep increments —
> results vary by system load. For continuous precise positioning use the async
> bit-bang approach in the next section.

---

## Speeding Up and Resolution Limits

### Raw MPSSE write path

The `Set-Servo` function above already uses the raw write path. The remaining
bottleneck is `Start-Sleep` resolution. With `timeBeginPeriod(1)`:

- Minimum reliable sleep: ~1 ms
- Pulse width resolution: 1 ms steps
- Angular resolution: ~18 deg/step (10 discrete positions over 0-180 deg)

This is sufficient for point-to-point positioning (e.g. 0, 45, 90, 135, 180
degrees) but not for smooth analog sweeps.

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

### Servo does not move at all

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
  - **Missing `timeBeginPeriod(1)`**: without it, `Start-Sleep -Milliseconds 1.5`
    sleeps ~15 ms and the 20 ms period becomes wildly irregular. Confirm the
    `Add-Type` block ran without errors and `[Win32.WinTimer]::timeBeginPeriod(1)`
    returned 0 (TIMERR_NOERROR).
  - **System load**: other processes adding jitter to the sleep calls. Close
    unnecessary applications. Use the raw MPSSE write path (bypass
    `Set-PsGadgetGpio`) to reduce per-cycle host CPU time.

### Position is wrong or inconsistent

- **Servo min/max calibration**: the standard 1.0-2.0 ms range is a guideline.
  Some servos use 0.5-2.5 ms for a wider travel range; others stop at 0.9 ms
  or 2.1 ms. Adjust `-MinMs` and `-MaxMs` in `Set-Servo` to match your servo.
  Start with the center (1.5 ms) and observe which direction is "true" neutral.
- **Timer jitter at sub-ms values**: `pulseMs = 1.3 ms` requires the OS to
  honor a 1.3 ms sleep. With `timeBeginPeriod(1)` this will actually sleep
  1 ms (floor). Stick to integer ms values (1, 1.5, 2) for reliable results
  without the async bit-bang approach.

### Servo only reaches two positions

You may not have called `timeBeginPeriod(1)` before running the loop. Without
it, `Start-Sleep -Milliseconds 1.5` and `Start-Sleep -Milliseconds 2.0` both
round up to the 15 ms tick, so the pulse is always ~15 ms and the servo
always sees the same effective command. Verify the P/Invoke `Add-Type` ran
successfully and that `timeBeginPeriod(1)` returned `0`.

---

## Quick Reference (Pro)

```powershell
# Load module
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1
$dev     = New-PsGadgetFtdi -Index 0
$rawFtdi = $dev._connection.Device   # FTD2XX_NET.FTDI handle

# Fix Windows timer resolution
Add-Type -MemberDefinition '
    [DllImport("winmm.dll")] public static extern int timeBeginPeriod(int t);
    [DllImport("winmm.dll")] public static extern int timeEndPeriod(int t);
' -Name 'WinTimer' -Namespace 'Win32' -ErrorAction SilentlyContinue
[Win32.WinTimer]::timeBeginPeriod(1)

function Set-Servo {
    param([double]$Degrees, [int]$AcbusPin=0, [int]$Cycles=50,
          [double]$MinMs=1.0, [double]$MaxMs=2.0)
    if ($Degrees -lt 0)   { $Degrees = 0 }
    if ($Degrees -gt 180) { $Degrees = 180 }
    $pulseMs = $MinMs + ($Degrees/180.0)*($MaxMs-$MinMs)
    $pin = [byte](1-shl $AcbusPin)
    $hi  = [byte[]](0x82,$pin,0xFF)
    $lo  = [byte[]](0x82,0x00,0xFF)
    $w   = 0
    for ($i=0;$i -lt $Cycles;$i++) {
        $rawFtdi.Write($hi,3,[ref]$w) | Out-Null; Start-Sleep -Milliseconds $pulseMs
        $rawFtdi.Write($lo,3,[ref]$w) | Out-Null; Start-Sleep -Milliseconds (20-$pulseMs)
    }
}

try {
    Set-Servo -Degrees 90   # center
    Set-Servo -Degrees 0    # min
    Set-Servo -Degrees 180  # max
    Set-Servo -Degrees 90   # center
} finally {
    [Win32.WinTimer]::timeEndPeriod(1)
    $w=0; $rawFtdi.Write([byte[]](0x82,0x00,0xFF),3,[ref]$w) | Out-Null
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

Two servos on ACBUS0 (pan) and ACBUS1 (tilt) position a laser pointer.

```powershell
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1

Add-Type -MemberDefinition '
    [DllImport("winmm.dll")] public static extern int timeBeginPeriod(int t);
    [DllImport("winmm.dll")] public static extern int timeEndPeriod(int t);
' -Name 'WinTimer' -Namespace 'Win32' -ErrorAction SilentlyContinue

$dev     = New-PsGadgetFtdi -Index 0
$rawFtdi = $dev._connection.Device
[Win32.WinTimer]::timeBeginPeriod(1)

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

    # Both servos share the SAME 20 ms pulse period
    # Use the larger of the two pulse widths to size the HIGH window per pin
    $panPulseMs  = $MinMs + ($PanDeg  / 180.0) * ($MaxMs - $MinMs)
    $tiltPulseMs = $MinMs + ($TiltDeg / 180.0) * ($MaxMs - $MinMs)

    # Round to nearest 1 ms increment (OS timer limit)
    $panMs  = [math]::Round($panPulseMs)
    $tiltMs = [math]::Round($tiltPulseMs)

    $w = 0
    for ($i = 0; $i -lt $Cycles; $i++) {
        # Both pins start HIGH simultaneously
        $rawFtdi.Write([byte[]](0x82, 0x03, 0xFF), 3, [ref]$w) | Out-Null
        # After shorter pulse ends, drop that pin
        $shortMs = [math]::Min($panMs, $tiltMs)
        $longMs  = [math]::Max($panMs, $tiltMs)
        $dropBit = if ($panMs -le $tiltMs) { 0x01 } else { 0x02 }
        $keepBit = if ($panMs -le $tiltMs) { 0x02 } else { 0x01 }

        Start-Sleep -Milliseconds $shortMs
        $rawFtdi.Write([byte[]](0x82, $keepBit, 0xFF), 3, [ref]$w) | Out-Null
        Start-Sleep -Milliseconds ($longMs - $shortMs)
        $rawFtdi.Write([byte[]](0x82, 0x00,     0xFF), 3, [ref]$w) | Out-Null
        Start-Sleep -Milliseconds (20 - $longMs)
    }
}

function Invoke-Fire {
    Write-Host "  FIRE"
    # Pulse ACBUS2 HIGH for 200 ms if laser trigger is wired there:
    # $rawFtdi.Write([byte[]](0x82, 0x04, 0xFF), 3, [ref]$w) | Out-Null
    # Start-Sleep -Milliseconds 200
    # $rawFtdi.Write([byte[]](0x82, 0x00, 0xFF), 3, [ref]$w) | Out-Null
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
    [Win32.WinTimer]::timeEndPeriod(1)
    $w = 0
    $rawFtdi.Write([byte[]](0x82, 0x00, 0xFF), 3, [ref]$w) | Out-Null
    $dev.Close()
}
```

> **Beginner**: pan is left-right rotation; tilt is up-down angle. ACBUS0
> controls the pan servo; ACBUS1 controls the tilt servo. Each call to
> `Set-TwoServos` moves both servos simultaneously to the requested position
> and holds for `$Cycles` pulses (50 cycles = 1 second at 50 Hz).

> **Scripter**: both pins share the same 20 ms frame, but different pulse
> widths. The function sends them both HIGH at the start of each period,
> then drops the shorter one after its pulse ends and keeps the longer one
> HIGH until its own pulse ends. This gives each servo an accurate
> independent pulse within the same period without needing two separate
> hardware timers.

> **Engineer**: at 1 ms timer resolution, pulse widths of 1, 1.5, and 2 ms
> give 3 reliable positions per servo = 9 pan/tilt combinations. For more
> positions, switch to async bit-bang with `Build-ServoPwmBuffer`
> (from the Speeding Up section) using bits 0 and 1 for pan and tilt.

> **Pro**: `Set-TwoServos` is blocking — it occupies the PowerShell thread
> for the duration of `$Cycles * 20 ms`. For a real aiming rig with real-time
> position updates, move the streaming loop into a background `RunspacePool`
> thread and use a `[System.Collections.Concurrent.ConcurrentQueue]` to
> pass new degree targets to it. The async bit-bang buffer approach is cleaner
> for that use case since you rebuild and re-stream from the worker thread on
> each position change.

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