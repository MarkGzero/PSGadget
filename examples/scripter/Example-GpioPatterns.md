# Scripter Example: GPIO Control Script Pattern

**Purpose**: Demonstrate the idiomatic PSGadget scripting pattern -- environment
check, connect by serial number, use try/finally, return structured output.

> **Scripter (Jordan)**: You know PowerShell. This example shows the clean
> scripting pattern: structured environment check, OOP device interface, and
> try/finally cleanup. Hardware concepts are explained inline.

---

## Hardware concepts (for scripters)

An FT232H is a USB breakout board with 8 GPIO pins labeled ACBUS0-7.
"GPIO" just means pins you can set HIGH (3.3 V) or LOW (0 V) in software.
No driver code needed -- PSGadget handles the D2XX API layer.

The FTDI D2XX driver must be installed on Windows. On Linux, `libftd2xx.so`
must be present. `Test-PsGadgetEnvironment` checks all of this and returns a
structured object you can use in scripts.

---

## Pattern 1: environment guard at script start

```powershell
#Requires -Version 5.1

Import-Module PSGadget

function Assert-PsGadgetReady {
    $result = Test-PsGadgetEnvironment
    if ($result.Status -ne 'OK') {
        throw "PSGadget not ready: $($result.Reason). Fix: $($result.NextStep)"
    }
    return $result
}

$env = Assert-PsGadgetReady
Write-Host "Backend: $($env.Backend)  Devices: $($env.DeviceCount)"
```

---

## Pattern 2: connect by serial number (stable across reboots)

```powershell
# Serial numbers survive USB port changes and reboots
# Find yours with: Get-PsGadgetFtdi | Select-Object SerialNumber, Type
$dev = New-PsGadgetFtdi -SerialNumber 'BG01X3GX'

try {
    $dev.SetPin(0, 'HIGH')
    Start-Sleep -Milliseconds 200
    $dev.SetPin(0, 'LOW')
} finally {
    $dev.Close()    # always runs, even if SetPin throws
}
```

---

## Pattern 3: select device by type in a script

```powershell
$devices = Get-PsGadgetFtdi
$target  = $devices | Where-Object { $_.Type -match 'FT232H' } | Select-Object -First 1

if (-not $target) {
    Write-Warning 'No FT232H found. Connect one and retry.'
    return
}

$dev = New-PsGadgetFtdi -SerialNumber $target.SerialNumber
try {
    # your work here
    $dev.SetPins(@(0, 1, 2), 'HIGH')
    Start-Sleep -Milliseconds 500
    $dev.SetPins(@(0, 1, 2), 'LOW')
} finally {
    $dev.Close()
}
```

---

## Pattern 4: I2C scan and structured output

```powershell
$dev       = New-PsGadgetFtdi -Index 0
$addresses = $null

try {
    $addresses = $dev.Scan()
} finally {
    $dev.Close()
}

# Returns an array of int addresses. Pipe to output or check values.
$addresses | ForEach-Object { Write-Host ("I2C device at 0x{0:X2}" -f $_) }

# Check for known device
if ($addresses -contains 0x3C) {
    Write-Host 'SSD1306 display found at 0x3C'
}
```

---

## Pattern 5: wrap PSGadget in a reusable function

```powershell
function Invoke-GpioSequence {
    [CmdletBinding()]
    param(
        [string]$SerialNumber,
        [int[]]$Pins,
        [int]$BlinkCount = 3,
        [int]$IntervalMs = 200
    )

    $dev = New-PsGadgetFtdi -SerialNumber $SerialNumber
    try {
        for ($i = 0; $i -lt $BlinkCount; $i++) {
            $dev.SetPins($Pins, 'HIGH')
            Start-Sleep -Milliseconds $IntervalMs
            $dev.SetPins($Pins, 'LOW')
            Start-Sleep -Milliseconds $IntervalMs
        }
        return [PSCustomObject]@{ SerialNumber = $SerialNumber; Blinks = $BlinkCount; Status = 'OK' }
    } catch {
        return [PSCustomObject]@{ SerialNumber = $SerialNumber; Blinks = 0; Status = $_.Exception.Message }
    } finally {
        $dev.Close()
    }
}

Invoke-GpioSequence -SerialNumber 'BG01X3GX' -Pins @(0, 1) -BlinkCount 5
```

---

## Quick reference

| Task | Code |
|------|------|
| Structured env check | `$e = Test-PsGadgetEnvironment; $e.Status` |
| Connect by SN | `New-PsGadgetFtdi -SerialNumber 'ABC'` |
| Connect by index | `New-PsGadgetFtdi -Index 0` |
| Single pin | `$dev.SetPin(0, 'HIGH')` |
| Multi pin | `$dev.SetPins(@(0,1), 'LOW')` |
| Pulse | `$dev.PulsePin(0, 'HIGH', 500)` |
| I2C scan | `$dev.Scan()` |
| Always close | `try { ... } finally { $dev.Close() }` |
