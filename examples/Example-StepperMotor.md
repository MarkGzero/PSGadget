# Example: Stepper Motor Control with FT232H (ACBUS/MPSSE) or FT232RNL (CBUS)

Drive a 5V geared stepper (28BYJ-48 or similar) via a KS0327/ULN2003 driver
board using an FTDI USB adapter. Two hardware paths are covered:

- **FT232H / MPSSE** — ACBUS0-3 output; no EEPROM programming required.
  This is the recommended path and is what most PSGadget kit builds use.
- **FT232RNL / CBUS** — CBUS0-3 output; requires a one-time EEPROM write.

Both paths use the same `Set-PsGadgetGpio` cmdlet at runtime.

---

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [What You Need](#what-you-need)
- [Hardware Background](#hardware-background)
  - [Wiring - FT232H ACBUS (recommended)](#wiring---ft232h-acbus-recommended)
  - [Wiring - FT232RNL CBUS](#wiring---ft232rnl-cbus)
  - [Coil sequencing](#coil-sequencing)
  - [Power considerations](#power-considerations)
- [Step 1 - Install Drivers and Verify Detection](#step-1---install-drivers-and-verify-detection)
- [Step 2 - Program CBUS EEPROM (one-time, FT232R only)](#step-2---program-cbus-eeprom-one-time-ft232r-only)
- [Step 3 - Verify GPIO Availability](#step-3---verify-gpio-availability)
- [Step 4 - Smoke Test](#step-4---smoke-test)
  - [FT232H / MPSSE path](#ft232h--mpsse-path)
  - [FT232R / CBUS path](#ft232r--cbus-path)
- [Step 5 - Precise Motion Script](#step-5---precise-motion-script)
  - [Half-step function](#half-step-function)
  - [Rotate by degrees](#rotate-by-degrees)
- [Timing and Debugging](#timing-and-debugging)
- [Troubleshooting](#troubleshooting)
  - [Motor does not move](#motor-does-not-move)
  - [Only one coil energizes](#only-one-coil-energizes)
  - [Stepper shudders or stalls](#stepper-shudders-or-stalls)
- [Quick Reference (Pro)](#quick-reference-pro)
- [Speeding Up](#speeding-up)
- [Exploring PSGadget Objects](#exploring-psgadget-objects)
- [Practical Example: Laser Aiming Rig](#practical-example-laser-aiming-rig)

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

### Wiring - FT232H ACBUS (recommended)

Connect ACBUS0-3 directly to ULN2003 IN1-IN4. No EEPROM programming needed.

| FT232H pin | ACBUS signal | ULN2003 input | Coil      |
|-----------|--------------|---------------|-----------|
| ACBUS0    | `ACBUS0`     | `IN1`         | Coil A    |
| ACBUS1    | `ACBUS1`     | `IN2`         | Coil A'   |
| ACBUS2    | `ACBUS2`     | `IN3`         | Coil B    |
| ACBUS3    | `ACBUS3`     | `IN4`         | Coil B'   |
| 5 V USB   |              | `5 V`         | Motor supply |
| GND       |              | `GND`         | Common ground |

> **Engineer**: ACBUS0-3 are driven by the MPSSE engine's high-byte port
> (`0x82` command). All four bits are set atomically in a single 3-byte USB
> transfer, which is what gives the FT232H path its clean step timing.

### Wiring - FT232RNL CBUS

| FT232RNL pin | CBUS signal | ULN2003 input | Coil      |
|-------------|-------------|---------------|-----------|
| CBUS0        | `CBUS0`     | `IN1`         | Coil A    |
| CBUS1        | `CBUS1`     | `IN2`         | Coil A'   |
| CBUS2        | `CBUS2`     | `IN3`         | Coil B    |
| CBUS3        | `CBUS3`     | `IN4`         | Coil B'   |
| 5 V USB      |             | `5 V`         | Motor supply |
| GND          |             | `GND`         | Common ground |

> **Beginner**: do **not** connect the motor wires directly to the FTDI
> board. The ULN2003 board handles the high current and provides built-in
> flyback diodes. Just connect the four control pins as shown above.

### Coil sequencing

The 28BYJ‑48 is a unipolar stepper with a 64‑step internal cycle and a 64:1
gearbox (4096 half-steps per output revolution in half-step mode). We will use the standard
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

## Step 2 - Program CBUS EEPROM (one-time, FT232R only)

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

## Step 4 - Smoke Test

### FT232H / MPSSE path

The recommended approach. `New-PsGadgetFtdi` opens the device and acquires the
D2XX MPSSE handle automatically. The half-step HIGH/LOW pairs are precomputed
so no array math runs inside the 4096-step loop.

```powershell
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1

$dev = New-PsGadgetFtdi -Index 0

# Pre-computed half-step table: each entry is @(highPins, lowPins)
# Avoids Where-Object filtering in the hot loop
$steps = @(
    @(@(0),   @(1,2,3)),
    @(@(0,1), @(2,3)),
    @(@(1),   @(0,2,3)),
    @(@(1,2), @(0,3)),
    @(@(2),   @(0,1,3)),
    @(@(2,3), @(0,1)),
    @(@(3),   @(0,1,2)),
    @(@(0,3), @(1,2))
)

try {
    for ($i = 0; $i -lt 4096; $i++) {
        $step = $steps[$i % 8]
        Set-PsGadgetGpio -PsGadget $dev -Pins $step[0] -State HIGH
        Set-PsGadgetGpio -PsGadget $dev -Pins $step[1] -State LOW
        Start-Sleep -Milliseconds 3
    }
} finally {
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0,1,2,3) -State LOW
    $dev.Close()
}
```

> **Engineer**: `Set-PsGadgetGpio` uses a cached ACBUS state value — the HIGH
> call sets the active bits, the LOW call clears the rest, both using the cache
> for read-modify-write without USB round-trips. Each step generates two
> 3-byte MPSSE writes (6 bytes total) over USB.

> **Scripter**: if you see the driver board LEDs blinking but the shaft just
> pulsing without rotation, the most common causes are console output overhead
> adding timing jitter (already eliminated in this version) and a seized
> gearbox. See Troubleshooting below.

### FT232R / CBUS path

Requires the EEPROM step from Step 2 first.

```powershell
$seq = @( @(1,0,0,0), @(1,1,0,0), @(0,1,0,0), @(0,1,1,0),
          @(0,0,1,0), @(0,0,1,1), @(0,0,0,1), @(1,0,0,1) )
$conn = Connect-PsGadgetFtdi -Index 0
for ($i=0; $i -lt 4096; $i++) {
    $pattern = $seq[$i % 8]
    for ($pin=0; $pin -lt 4; $pin++) {
        $state = if ($pattern[$pin] -eq 1) { 'HIGH' } else { 'LOW' }
        Set-PsGadgetGpio -Connection $conn -Pins @($pin) -State $state
    }
    Start-Sleep -Milliseconds 3
}
Set-PsGadgetGpio -Connection $conn -Pins @(0..3) -State LOW
$conn.Close()
```

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

Here is an example using the PSGadget API to enable async bit-bang and stream
bytes:

```powershell
# connect and switch to async bit-bang mode (ADBUS0-3 as outputs, mask 0x0F)
$dev = New-PsGadgetFtdi -Index 0
Set-PsGadgetFtdiMode -PsGadget $dev -Mode AsyncBitBang -Mask 0x0F
# baud rate controls step rate: 9600 baud = 9600 half-steps/sec
$dev.SetBaudRate(9600)

# half-step byte sequence (bits 0-3 map to IN1-IN4 on the ULN2003)
$seq = [byte[]](0x01, 0x03, 0x02, 0x06, 0x04, 0x0C, 0x08, 0x09)

# build 4096-step buffer (1 full output revolution)
$buf = [System.Collections.Generic.List[byte]]::new()
for ($i = 0; $i -lt 4096; $i++) { $buf.Add($seq[$i % 8]) }

# stream the entire sequence in one bulk write;
# the FTDI chip clocks each byte out at the programmed baud rate
$written = 0
$dev._connection.Write($buf.ToArray(), $buf.Count, [ref]$written)

# de-energize and return to UART mode
$dev._connection.Write([byte[]](0x00), 1, [ref]$written)
Set-PsGadgetFtdiMode -PsGadget $dev -Mode UART
$dev.Close()
```

For step-by-step control at slower rates, `Set-PsGadgetGpio` works once async
mode is active. After `Set-PsGadgetFtdiMode` the cmdlet dispatches to the
async bit-bang handler automatically. Specify only the HIGH pins each step;
unspecified pins are implicitly driven LOW:

```powershell
# half-step sequence expressed as the set of HIGH pins per step
$seqPins = @(
    @(0),    # 0x01 - IN1
    @(0,1),  # 0x03 - IN1+IN2
    @(1),    # 0x02 - IN2
    @(1,2),  # 0x06 - IN2+IN3
    @(2),    # 0x04 - IN3
    @(2,3),  # 0x0C - IN3+IN4
    @(3),    # 0x08 - IN4
    @(0,3)   # 0x09 - IN1+IN4
)
for ($i = 0; $i -lt 512; $i++) {
    Set-PsGadgetGpio -PsGadget $dev -Pins $seqPins[$i % 8] -State HIGH
    Start-Sleep -Milliseconds 2
}
# de-energize
Set-PsGadgetGpio -PsGadget $dev -Pins @(0,1,2,3) -State LOW
```

> **Performance tip:** the bulk-write path (`$dev._connection.Write`) sends the
> entire sequence in a single USB transfer and the FTDI chip clocks bytes out
> at the programmed baud rate. This produces a perfectly timed step stream
> with smooth acceleration ramps and thousands of steps/sec — without host CPU
> jitter or per-step USB round trips.

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
    # 4096 half-steps per 360° (half-step mode)
    $steps = [math]::Round(4096 * ($Degrees / 360))
    for ($i=0; $i -lt $steps; $i++) {
        Invoke-StepperHalfStep -Connection $Connection -Direction $Direction
    }
}

# Usage example:
$conn = Connect-PsGadgetFtdi -Index 0
Invoke-StepperRotate -Connection $conn -Degrees 90   # quarter turn
Invoke-StepperRotate -Connection $conn -Degrees 45  -Direction -1  # back
Set-PsGadgetGpio -Connection $conn -Pins @(0..3) -State LOW
$conn.Close()
```

Adjust `Start-Sleep` delays in `Invoke-StepperHalfStep` to trade speed vs.
stalling.

---

## Timing and Debugging

**Measure actual step rate with a Stopwatch:**

```powershell
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 4096; $i++) {
    $step = $steps[$i % 8]
    Set-PsGadgetGpio -PsGadget $dev -Pins $step[0] -State HIGH
    Set-PsGadgetGpio -PsGadget $dev -Pins $step[1] -State LOW
    Start-Sleep -Milliseconds 3
}
$sw.Stop()
Write-Host ("4096 steps in {0:F1}s ({1:F2}ms/step avg)" -f $sw.Elapsed.TotalSeconds, ($sw.ElapsedMilliseconds / 4096.0))
```

Expected: ~12-13 s total, ~3.1 ms/step. If you see 10+ ms/step the module is
adding overhead; see the notes below.

**Sample every N steps (lightweight progress without jitter):**

```powershell
for ($i = 0; $i -lt 4096; $i++) {
    if ($i % 512 -eq 0) { Write-Host "Step $i / 4096" }
    $step = $steps[$i % 8]
    Set-PsGadgetGpio -PsGadget $dev -Pins $step[0] -State HIGH
    Set-PsGadgetGpio -PsGadget $dev -Pins $step[1] -State LOW
    Start-Sleep -Milliseconds 3
}
```

**Single-call inspection with `-Verbose`:**

```powershell
# -Verbose on a single call is fine; avoid it inside the 4096-step loop
Set-PsGadgetGpio -PsGadget $dev -Pins @(0,1) -State HIGH -Verbose
```

> **Scripter**: `Write-Host` (or any console output) inside a tight loop adds
> several milliseconds of jitter per call because PowerShell must format and
> flush the host buffer synchronously. The PSGadget module suppresses all
> per-call success messages in the GPIO path for this reason.

> **Engineer**: The D2XX ACBUS state is cached on the connection object after
> every write, so the read-modify-write inside `Set-FtdiGpioPins` never issues
> a USB `0x83` read command during normal operation. Removing the USB read
> round-trip was the main fix that allowed the 28BYJ-48 to build rotational
> momentum at 3 ms/step.

---

## Speeding Up

With the default `Set-PsGadgetGpio` loop and `Start-Sleep -Milliseconds 3`,
a full revolution takes roughly **60 seconds** on Windows. Two independent
causes account for nearly all of that gap.

### Cause 1: Windows timer resolution (biggest impact)

On Windows, `Start-Sleep -Milliseconds 3` actually sleeps **~15 ms** by
default. The Windows multimedia timer runs at 15.625 ms resolution unless a
process explicitly requests finer granularity. At 4096 steps the result is
~61 s per revolution instead of ~12 s.

Fix it once per script with a two-line P/Invoke call:

```powershell
Add-Type -MemberDefinition '
    [DllImport("winmm.dll")] public static extern int timeBeginPeriod(int t);
    [DllImport("winmm.dll")] public static extern int timeEndPeriod(int t);
' -Name 'WinTimer' -Namespace 'Win32'

[Win32.WinTimer]::timeBeginPeriod(1)   # 1 ms resolution for this process
try {
    for ($i = 0; $i -lt 4096; $i++) {
        $step = $steps[$i % 8]
        Set-PsGadgetGpio -PsGadget $dev -Pins $step[0] -State HIGH
        Set-PsGadgetGpio -PsGadget $dev -Pins $step[1] -State LOW
        Start-Sleep -Milliseconds 2
    }
} finally {
    [Win32.WinTimer]::timeEndPeriod(1)
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0,1,2,3) -State LOW
}
```

Expected after fix: ~4096 x 2 ms = **~8-9 s per revolution**.

> **Scripter**: call `timeBeginPeriod(1)` once at the top of your script and
> `timeEndPeriod(1)` in the `finally` block. The effect applies to the entire
> process for the duration; there is no per-loop overhead.

### Cause 2: PowerShell cmdlet overhead per step

Each `Set-PsGadgetGpio` call involves PowerShell parameter binding and a
three-level function dispatch (public wrapper -> private backend -> MPSSE
helper). Two calls per step adds ~3-6 ms of interpreter overhead before the
`Start-Sleep` even runs.

Bypass this entirely by writing the 3-byte MPSSE `0x82` command directly to
the raw FTD2XX_NET device handle:

```powershell
# ACBUS byte for each half-step phase - bits 0-3 map to ACBUS0-3 / ULN2003 IN1-IN4
$acbusSeq = [byte[]](0x01, 0x03, 0x02, 0x06, 0x04, 0x0C, 0x08, 0x09)
$written  = 0
$rawFtdi  = $dev._connection.Device   # FTD2XX_NET.FTDI handle

[Win32.WinTimer]::timeBeginPeriod(1)
try {
    for ($i = 0; $i -lt 4096; $i++) {
        $rawFtdi.Write([byte[]](0x82, $acbusSeq[$i % 8], 0xFF), 3, [ref]$written) | Out-Null
        Start-Sleep -Milliseconds 2
    }
} finally {
    [Win32.WinTimer]::timeEndPeriod(1)
    $rawFtdi.Write([byte[]](0x82, 0x00, 0xFF), 3, [ref]$written) | Out-Null
}
```

Expected: ~4096 x 2 ms = **~8 s per revolution**, with no cmdlet overhead.

> **Engineer**: `0x82` is the MPSSE "Set Data Bits High Byte" (ACBUS)
> command. Byte 1 is the 8-bit output value; byte 2 is the direction mask
> (0xFF = all ACBUS pins as outputs). One 3-byte USB write per step, no
> read round-trip.

> **Pro**: At 2 ms/step the motor is near its pull-in limit. If steps are
> skipping under load, increase to 3 ms. Do NOT send all 4096 MPSSE commands
> in a single bulk `Write()` without inter-step delays -- the MPSSE engine
> will execute all phases in microseconds, which will stall the motor.

---

## Exploring PSGadget Objects

The speed section accesses `$dev._connection.Device` directly. This section
explains how to find that path yourself on any PSGadget or PowerShell object.

### Why this works

Every value in PowerShell is a .NET object. `PSCustomObject` is a property bag
that can hold any .NET object as a `NoteProperty`. The dot operator `.` just
accesses a property or field — it doesn't care whether the object is a
PowerShell class, a `PSCustomObject`, or a .NET class from an assembly.

```
$dev                          PsGadgetFtdi class
  ._connection                PSCustomObject (connection bag)
    .Device                   FTD2XX_NET.FTDI (.NET object from DLL)
      .Write(bytes, len, ref) actual USB write to FTDI chip
```

Each `.` dereferences the object returned by the previous step.

### How to interrogate any object

**Standard members (what you normally see):**
```powershell
$dev | Get-Member
```

**Include hidden properties** (`hidden` in a PowerShell class suppresses
tab-completion and `Format-*` output but does NOT prevent access):
```powershell
$dev | Get-Member -Force
```

**All members including inherited .NET base class members:**
```powershell
$dev | Get-Member -Force -View All
```

**Inspect a PSCustomObject's NoteProperties** (including type of each value):
```powershell
$dev._connection.PSObject.Properties | Select-Object Name, MemberType, TypeNameOfValue, Value
```

**Full .NET reflection** -- lists every method and property the underlying
.NET type exposes, including non-public and inherited members:
```powershell
# All public methods
$dev.GetType().GetMethods() | Select-Object Name, IsStatic | Sort-Object Name

# All public properties
$dev.GetType().GetProperties() | Select-Object Name, PropertyType

# Everything: public + non-public + static + instance
$dev.GetType().GetMembers(
    [System.Reflection.BindingFlags]'Public,NonPublic,Instance,Static'
) | Select-Object Name, MemberType | Sort-Object MemberType, Name
```

**What type is this object? Where does it come from?**
```powershell
$dev.GetType().FullName      # PsGadgetFtdi
$dev._connection.Device.GetType().FullName   # FTD2XX_NET.FTDI
$dev._connection.Device.GetType().Assembly   # shows which DLL loaded it
```

**Quick reference table:**

| Goal | Command |
|------|---------|
| Normal members | `$obj \| gm` |
| Include hidden | `$obj \| gm -Force` |
| All views | `$obj \| gm -Force -View All` |
| PSCustomObject props | `$obj.PSObject.Properties` |
| .NET reflection | `$obj.GetType().GetMembers(...)` |
| What type is it? | `$obj.GetType().FullName` |
| What assembly? | `$obj.GetType().Assembly` |
| Dump as JSON | `$obj \| ConvertTo-Json -Depth 5` |

> **Beginner**: `Get-Member` (alias `gm`) is the first tool to reach for any
> time you have an object and don't know what you can do with it. Run
> `$dev | gm` immediately after connecting to see all available methods.

> **Scripter**: `hidden` in a PowerShell class definition is cosmetic. It
> removes the property from tab-completion and default display, but
> `$obj.HiddenProperty` still works. Use `Get-Member -Force` to see hidden
> members.

> **Engineer**: The entire .NET Base Class Library is available in every
> PowerShell session without any imports. `[System.IO.File]`,
> `[System.Diagnostics.Stopwatch]`, `[System.Net.Sockets.TcpClient]` — all
> accessible directly. Cmdlets are wrappers on top of .NET; once you know
> how to reach past them you can call any .NET API directly.

> **Pro**: Use `BindingFlags` in `.GetMembers()` to expose private fields if
> you need to inspect or interact with internal state of a third-party .NET
> class (e.g. `FTD2XX_NET.FTDI`). Combine with `.GetValue()` /
> `.SetValue()` on `FieldInfo` objects to read/write private fields at
> runtime — useful for diagnostics, not production code.

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

- **LEDs flash but shaft only pulses** — the most common cause is timing jitter
  from overhead between steps, not a wiring problem. Verify the module is not
  printing per-step output (`Write-Host` inside the loop) and that the step
  table is precomputed (no `Where-Object` filter inside the loop).
- **USB read round-trips** — if you're on an older version of the module, `Get-FtdiGpioPins`
  may issue an `0x83` read command before every write (adds ~2 ms of USB latency
  per step). The current module caches ACBUS state and skips the read. Confirm
  you are on dev1 with the latest `Ftdi.Mpsse.ps1`.
- Increase `Start-Sleep -Milliseconds` (try 5 ms or 10 ms) if the motor stalls under load.
- Reduce supply voltage if the motor overheats; the gearbox is fragile.
- Use full-step sequence (`-FullStep` switch) for more consistent torque and smoother
  motion -- on the 28BYJ-48 full-step is smoother than half-step in practice.

---

## Quick Reference (Pro)

```powershell
# FT232H / MPSSE path - ACBUS0-3 to ULN2003 IN1-IN4 - no EEPROM step required
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1
$dev   = New-PsGadgetFtdi -Index 0
$steps = @(
    @(@(0),@(1,2,3)), @(@(0,1),@(2,3)), @(@(1),@(0,2,3)), @(@(1,2),@(0,3)),
    @(@(2),@(0,1,3)), @(@(2,3),@(0,1)), @(@(3),@(0,1,2)), @(@(0,3),@(1,2))
)
try {
    for ($i=0;$i -lt 4096;$i++) {
        $s=$steps[$i%8]
        Set-PsGadgetGpio -PsGadget $dev -Pins $s[0] -State HIGH
        Set-PsGadgetGpio -PsGadget $dev -Pins $s[1] -State LOW
        Start-Sleep -Milliseconds 3
    }
} finally {
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0,1,2,3) -State LOW
    $dev.Close()
}
```

```powershell
# FT232H - measure timing
$sw=[System.Diagnostics.Stopwatch]::StartNew()
# ... loop ...
$sw.Stop(); Write-Host ("{0:F2}ms/step avg" -f ($sw.ElapsedMilliseconds/4096.0))
```

```powershell
# FT232R / CBUS path - one-time EEPROM setup
Set-PsGadgetFt232rCbusMode -Index 0   # run once per device; replug USB after

$seq=@(@(1,0,0,0),@(1,1,0,0),@(0,1,0,0),@(0,1,1,0),@(0,0,1,0),@(0,0,1,1),@(0,0,0,1),@(1,0,0,1))
$conn=Connect-PsGadgetFtdi -Index 0
for($i=0;$i -lt 4096;$i++){ $p=$seq[$i%8];for($pin=0;$pin -lt 4;$pin++){$st=if($p[$pin]){'HIGH'}else{'LOW'};Set-PsGadgetGpio -Connection $conn -Pins @($pin) -State $st};Start-Sleep -Milliseconds 3}
Set-PsGadgetGpio -Connection $conn -Pins @(0..3) -State LOW
$conn.Close()
```

```powershell
# Async bit-bang path (FT232R, no EEPROM change) - highest throughput
# Wire ADBUS0-3 (TX/RX/RTS/CTS pins) to ULN2003 IN1-IN4 instead of CBUS pins
$dev = New-PsGadgetFtdi -Index 0
Set-PsGadgetFtdiMode -PsGadget $dev -Mode AsyncBitBang -Mask 0x0F
$dev.SetBaudRate(9600)   # 9600 half-steps/sec
$seq=[byte[]](0x01,0x03,0x02,0x06,0x04,0x0C,0x08,0x09)
$buf=[System.Collections.Generic.List[byte]]::new(); for($i=0;$i -lt 4096;$i++){$buf.Add($seq[$i%8])}
$w=0; $dev._connection.Write($buf.ToArray(),$buf.Count,[ref]$w)
$dev._connection.Write([byte[]](0x00),1,[ref]$w)   # de-energize
Set-PsGadgetFtdiMode -PsGadget $dev -Mode UART
$dev.Close()
```

---

## Practical Example: Laser Aiming Rig

The stepper positions a laser pointer (or camera, sensor, etc.) along a
horizontal axis. Use `Move-Stepper` with a degree count, direction, and
optional step mode:

```powershell
Move-Stepper -HalfStep -Degrees 45 -Direction left   # finer resolution, slight hesitation
Move-Stepper -FullStep -Degrees 90 -Direction right  # faster, smoother feel, consistent torque
Move-Stepper 45 left                                 # positional shorthand (default: half-step)
```

**Choosing a mode:**

| | Half-step | Full-step |
|--|---------------------|-----------|
| Steps/rev | 4096 | 2048 |
| Speed at 2ms/step | ~8s/rev | ~4s/rev |
| Torque per phase | Varies (1-coil / 2-coil alternating) | Consistent (always 2 coils) |
| Feel on 28BYJ-48 | Slight hesitation on 1-coil phases | Smooth, consistent pull |
| Best for | fine angular resolution | smooth motion, heavy load |

> **Note**: textbooks say half-step is smoother, but on the 28BYJ-48 at
> USB-controlled speeds, **full-step feels smoother** in practice. Half-step
> alternates between 1-coil and 2-coil phases; the rotor hesitates slightly
> on every 1-coil phase because torque is lower. Full-step always energizes
> 2 coils, giving consistent torque on every step. You can also see this on
> the ULN2003 driver board: in half-step mode the LEDs flash visibly as coils
> alternate; in full-step mode the LEDs appear almost steady because 2 coils
> are always on and steps happen twice as fast.

Use `-HalfStep` when you need finer angular resolution (4096 steps vs 2048).
Use `-FullStep` for smoother feel or when the motor stalls under load.

A common technique is to start with full-step to overcome static friction,
then switch to half-step for the fine-positioning move:

> **Beginner**: "degrees" here means real output-shaft degrees, not motor
> internal degrees. The gearbox is already accounted for (4096 half-steps =
> one full 360 degree output revolution).

> **Engineer**: 4096 half-steps / 360 degrees = 11.378 steps/degree (half-step),
> 2048 / 360 = 5.689 steps/degree (full-step). The
> `[math]::Round` keeps integer step counts. Accumulated rounding error over
> many small moves is ~0.09 degrees worst-case per move in half-step mode; reset
> to a home switch if absolute accuracy is required.

```powershell
Import-Module G:\PSSummit2026\psgadget\PSGadget.psm1

$dev = New-PsGadgetFtdi -Index 0

# Tracks current step position so relative moves accumulate correctly
$script:HalfStepPos = 0
$script:FullStepPos = 0

# Half-step sequence: 8 phases, alternates 1-coil / 2-coil (finer resolution, 4096 steps/rev)
$halfSeq = [byte[]](0x01, 0x03, 0x02, 0x06, 0x04, 0x0C, 0x08, 0x09)
# Full-step sequence: 4 phases, always 2 coils (more torque, 2048 steps/rev)
$fullSeq = [byte[]](0x03, 0x06, 0x0C, 0x09)

$rawFtdi  = $dev._connection.Device   # FTD2XX_NET.FTDI handle - bypass cmdlet overhead

# Set 1 ms Windows timer resolution once (fixes Start-Sleep granularity 15ms->1ms)
Add-Type -MemberDefinition '
    [DllImport("winmm.dll")] public static extern int timeBeginPeriod(int t);
    [DllImport("winmm.dll")] public static extern int timeEndPeriod(int t);
' -Name 'WinTimer' -Namespace 'Win32' -ErrorAction SilentlyContinue
[Win32.WinTimer]::timeBeginPeriod(1)

function Move-Stepper {
    param(
        [Parameter(Mandatory, Position = 0)]
        [double]$Degrees,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('left', 'right')]
        [string]$Direction,

        # Step mode switches - omit for default half-step
        [switch]$HalfStep,
        [switch]$FullStep,

        [int]$DelayMs = 2
    )

    # Full-step if -FullStep specified OR if neither is specified default to half-step
    $useFullStep = $FullStep.IsPresent -and -not $HalfStep.IsPresent

    if ($useFullStep) {
        $seq        = $fullSeq
        $seqLen     = 4
        $stepsPerRev = 2048
    } else {
        $seq        = $halfSeq
        $seqLen     = 8
        $stepsPerRev = 4096
    }

    $nSteps = [math]::Abs([math]::Round($stepsPerRev * ($Degrees / 360)))
    $dir    = if ($Direction -eq 'right') { 1 } else { -1 }
    $w      = 0

    if ($useFullStep) {
        for ($i = 0; $i -lt $nSteps; $i++) {
            $script:FullStepPos = (($script:FullStepPos + $dir) % $seqLen + $seqLen) % $seqLen
            $rawFtdi.Write([byte[]](0x82, $seq[$script:FullStepPos], 0xFF), 3, [ref]$w) | Out-Null
            Start-Sleep -Milliseconds $DelayMs
        }
    } else {
        for ($i = 0; $i -lt $nSteps; $i++) {
            $script:HalfStepPos = (($script:HalfStepPos + $dir) % $seqLen + $seqLen) % $seqLen
            $rawFtdi.Write([byte[]](0x82, $seq[$script:HalfStepPos], 0xFF), 3, [ref]$w) | Out-Null
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    $mode = if ($useFullStep) { 'full-step' } else { 'half-step' }
    Write-Host ("Moved $Degrees deg $Direction ($nSteps steps, $mode)")
}

function Stop-Stepper {
    $w = 0
    $rawFtdi.Write([byte[]](0x82, 0x00, 0xFF), 3, [ref]$w) | Out-Null
}

function Invoke-Fire {
    # Replace this body with actual laser/camera trigger logic.
    # Example: pulse ACBUS4 HIGH for 200 ms if your trigger is wired there.
    Write-Host "  FIRE at current position"
    # Set-PsGadgetGpio -PsGadget $dev -Pins @(4) -State HIGH -DurationMs 200
}

try {
    Stop-Stepper
    Start-Sleep -Milliseconds 100

    # Full-step to overcome static friction, then half-step for precision
    Move-Stepper -FullStep  -Degrees 5  -Direction left    # quick start
    Move-Stepper -HalfStep  -Degrees 5  -Direction right   # fine-tune back
    Invoke-Fire

    Move-Stepper -HalfStep  -Degrees 27 -Direction right
    Invoke-Fire

    Move-Stepper -FullStep  -Degrees 10 -Direction left
    Invoke-Fire

} finally {
    [Win32.WinTimer]::timeEndPeriod(1)
    Stop-Stepper
    $dev.Close()
}
```

**Degree-to-step reference:**

| Degrees | Half-steps (4096/rev) | Full-steps (2048/rev) |
|---------|-----------------------|-----------------------|
| 1       | 11                    | 6                     |
| 5       | 57                    | 28                    |
| 10      | 114                   | 57                    |
| 27      | 307                   | 154                   |
| 45      | 512                   | 256                   |
| 90      | 1024                  | 512                   |
| 180     | 2048                  | 1024                  |
| 360     | 4096                  | 2048                  |

> **Scripter**: `Move-Stepper` calls chain from the current shaft position.
> `-HalfStep` and `-FullStep` each maintain their own position counter
> internally, so you can mix modes freely without losing track of where the
> shaft is.

> **Pro**: The default `DelayMs = 2` works for light loads in half-step mode.
> Full-step at 2 ms/step is near the pull-in limit (~1000 steps/sec at 2 ms);
> increase to 3 ms if steps skip under load. For a ramp-up pattern, call
> `Move-Stepper -FullStep` first to overcome static friction, then
> `Move-Stepper -HalfStep` for the precision portion of the move.

---

*End of stepper example.*
