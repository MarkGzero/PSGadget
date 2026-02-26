# Example-Ft232rMotor.ps1
# DC motor control via FT232R CBUS0 bit-bang GPIO.
#
# Tested with: FT232 breakout board (FT232R / FT232RNL)
#
# Hardware wiring:
#   CBUS0  -> motor terminal +
#   GND    -> motor terminal -
#
# IMPORTANT - board VCCIO voltage selection:
#   Many FT232 breakout boards ship with VCCIO set to 3.3V, causing CBUS pins to
#   output only 3.3V - not enough to drive most motors.
#
#   Boards with a 3-pin "5V | VCCIO | 3V3" jumper header:
#     Place a jumper cap bridging 5V and VCCIO to select 5V output.
#
#   Waveshare USB-TO-TTL-FT232:
#     Move the SMD solder jumper on the back from 3.3V to 5V.
#
#   After changing the jumper, replug the USB cable.
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

# ── 1. Create device object ───────────────────────────────────────────────

$DeviceIndex = 1   # change to match your device index (see List-PsGadgetFtdi output)
$dev = New-PsGadgetFtdi -Index $DeviceIndex

# ── 2. EEPROM setup check ─────────────────────────────────────────────────
# Read EEPROM and verify CBUS0 is already set to FT_CBUS_IOMODE.
# If not, offer to program it automatically.

$eeprom = Get-PsGadgetFtdiEeprom -PsGadget $dev

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
    $ans = Read-Host "Program EEPROM now? [y/N]"
    if ($ans -match '^[Yy]') {
        Set-PsGadgetFt232rCbusMode -PsGadget $dev -Pins @(0)
        Write-Host ""
        Write-Host "Cycling USB port to apply EEPROM changes (no manual replug needed)..."
        $dev.Connect()
        $dev.CyclePort()
        $dev.Close()
        Write-Host "Port cycled. Re-run this script to continue."
    } else {
        Write-Host "Aborting. Replug device after running Set-PsGadgetFt232rCbusMode."
    }
    return
}

Write-Host "CBUS0 is FT_CBUS_IOMODE - ready for GPIO control."
Write-Host ""

# ── 3. Connect and run motor test ────────────────────────────────────────

$dev.Connect()

try {
    Write-Host "--- Test: CBUS0 HIGH for 3 seconds ---"
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0) -State HIGH
    Write-Host "CBUS0 set HIGH. Motor should be running..."
    Start-Sleep -Seconds 3
    Set-PsGadgetGpio -PsGadget $dev -Pins @(0) -State LOW
    Write-Host "CBUS0 set LOW. Motor stopped."

} finally {
    $dev.Close()
    Write-Host "Connection closed."
}
