# Set-PsGadgetServo.ps1
# Sets a servo position on a PCA9685 channel using FT232H MPSSE I2C

#Requires -Version 5.1

function Set-PsGadgetServo {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
[PsGadgetFtdi]$PsGadget,

        [Parameter(Mandatory)]
        [ValidateRange(0,15)]
        [int]$Channel,

        [Parameter(Mandatory)]
        [ValidateRange(0,180)]
        [int]$Angle,

        [Parameter()]
        [byte]$Address = 0x40
    )

    # Servo pulse limits for MG90S style servos
    # 50Hz PWM (20ms period) -> PCA9685 counts 0-4095
    # ~1ms -> ~205 counts
    # ~2ms -> ~410 counts

    $minPulse = 205
    $maxPulse = 410

    # Convert angle (0-180) to pulse count
    $pulse = [int]($minPulse + (($maxPulse - $minPulse) * $Angle / 180))

    # Calculate base register for this channel
    $baseRegister = 0x06 + ($Channel * 4)

    # PCA9685 expects:
    # ON_L, ON_H, OFF_L, OFF_H
    # Typical servo: ON = 0

    $on_l  = 0x00
    $on_h  = 0x00
    $off_l = $pulse -band 0xFF
    $off_h = ($pulse -shr 8) -band 0x0F

    $data = @(
        $baseRegister,
        $on_l,
        $on_h,
        $off_l,
        $off_h
    )

    Send-PsGadgetI2CWrite `
        -PsGadget $PsGadget `
        -Address $Address `
        -Data $data
}

$dev = New-PsGadgetFtdi -Index 0
Set-PsGadgetFtdiMode -PsGadget $dev -Mode MpsseI2c

Import-Module .\PSGadget.psd1 -Force
Invoke-PsGadgetI2CScan -PsGadget $dev | Format-Table -AutoSize

$dev.close()