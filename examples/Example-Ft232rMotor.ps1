# Example-Ft232rMotor.ps1
# DC motor control via FT232R CBUS0 bit-bang GPIO.
#
# Hardware wiring:
#   CBUS0  -> motor terminal +
#   GND    -> motor terminal -
#
# NOTE: FT232R CBUS pins supply ~4 mA max. This is suitable for small pager/
#       coin vibration motors. For larger motors, drive a transistor or motor
#       driver IC (e.g. DRV8833) from CBUS0 instead of wiring the motor directly.
#
# One-time EEPROM setup (run once per device, then replug USB):
#   Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0)
#
# After EEPROM setup and replug, run this script normally.

#Requires -Version 5.1

Import-Module "$PSScriptRoot/../PSGadget.psd1" -Force

# ── 0. Enumerate devices ──────────────────────────────────────────────────

Write-Host "Connected FTDI devices:"
List-PsGadgetFtdi | Format-Table Index, Type, SerialNumber, GpioMethod, HasMpsse

# ── 1. EEPROM setup check ─────────────────────────────────────────────────
# Read EEPROM and verify CBUS0 is already set to FT_CBUS_IOMODE.
# If not, offer to program it automatically.

$DeviceIndex = 0
$eeprom = Get-PsGadgetFtdiEeprom -Index $DeviceIndex

Write-Host ""
Write-Host "EEPROM CBUS pin modes:"
Write-Host "  CBUS0: $($eeprom.Cbus0)"
Write-Host "  CBUS1: $($eeprom.Cbus1)"
Write-Host "  CBUS2: $($eeprom.Cbus2)"
Write-Host "  CBUS3: $($eeprom.Cbus3)"
Write-Host ""

if ($eeprom.Cbus0 -ne 'FT_CBUS_IOMODE') {
    Write-Warning "CBUS0 is '$($eeprom.Cbus0)', not FT_CBUS_IOMODE."
    Write-Warning "EEPROM setup is required before motor control will work."
    Write-Host ""
    Write-Host "Run this command to configure CBUS0 as GPIO, then replug the USB cable:"
    Write-Host "  Set-PsGadgetFt232rCbusMode -Index $DeviceIndex -Pins @(0)"
    Write-Host ""
    $ans = Read-Host "Program EEPROM now? [y/N]"
    if ($ans -match '^[Yy]') {
        Set-PsGadgetFt232rCbusMode -Index $DeviceIndex -Pins @(0)
        Write-Host ""
        Write-Host "[ACTION REQUIRED] Disconnect and reconnect the USB cable, then run this script again."
    } else {
        Write-Host "Aborting. Replug device after running Set-PsGadgetFt232rCbusMode."
    }
    return
}

Write-Host "CBUS0 is FT_CBUS_IOMODE - ready for GPIO control."
Write-Host ""

# ── 2. Open connection once ───────────────────────────────────────────────

$conn = Connect-PsGadgetFtdi -Index $DeviceIndex
if (-not $conn) {
    Write-Error "Failed to open device $DeviceIndex."
    return
}

try {
    # ── 3. Simple ON/OFF demo ─────────────────────────────────────────────

    Write-Host "--- Demo 1: Motor ON for 2 seconds ---"
    Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH
    Start-Sleep -Milliseconds 2000
    Set-PsGadgetGpio -Connection $conn -Pins @(0) -State LOW
    Write-Host "Motor stopped."
    Start-Sleep -Milliseconds 1000

    # ── 4. Pulse pattern: 3 short bursts ────────────────────────────────

    Write-Host "--- Demo 2: 3 short pulses ---"
    for ($i = 0; $i -lt 3; $i++) {
        Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH
        Start-Sleep -Milliseconds 300
        Set-PsGadgetGpio -Connection $conn -Pins @(0) -State LOW
        Start-Sleep -Milliseconds 400
    }
    Write-Host "Pulses done."
    Start-Sleep -Milliseconds 500

    # ── 5. Soft-PWM speed ramp (approximate - limited by PS/D2XX latency) ─
    #
    # True PWM is not possible via CBUS bit-bang (no hardware timer), but a
    # rough software PWM can give an impression of varying speed on small motors.
    # Period ~20 ms, duty cycle sweeps 10% -> 90% -> 10%.

    Write-Host "--- Demo 3: Soft-PWM speed ramp (10% -> 90% -> 10%) ---"
    Write-Host "(Note: actual frequency is limited by USB latency; effect is approximate)"

    $periodMs = 20
    $steps    = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4, 3, 2, 1)  # duty tenths

    foreach ($duty in $steps) {
        $onMs  = [int]($periodMs * $duty / 10)
        $offMs = $periodMs - $onMs

        # Run each duty step for ~300 ms worth of cycles
        $cycles = [int](300 / $periodMs)
        for ($c = 0; $c -lt $cycles; $c++) {
            Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH
            Start-Sleep -Milliseconds $onMs
            Set-PsGadgetGpio -Connection $conn -Pins @(0) -State LOW
            if ($offMs -gt 0) { Start-Sleep -Milliseconds $offMs }
        }
    }

    Write-Host "Ramp done. Motor off."
    Set-PsGadgetGpio -Connection $conn -Pins @(0) -State LOW

} finally {
    $conn.Close()
    Write-Host "Connection closed."
}
