#Requires -Version 5.1
# DEPRECATED - use Invoke-PsGadgetI2C -I2CModule PCA9685 -ServoAngle @(@(ch,deg),...) instead.
# This file remains loaded as a private helper for internal use.

function Invoke-PsGadgetPca9685SetChannels {
    <#
    .SYNOPSIS
    Sets multiple PCA9685 servo channels to specific angles.

    .DESCRIPTION
    Sends I2C commands to set multiple PWM channels on the PCA9685 to the desired
    servo angles in rapid succession.

    .PARAMETER PsGadget
    The PsGadgetPca9685 instance (from Connect-PsGadgetPca9685).

    .PARAMETER Degrees
    An array of servo angles (0-180, one per channel). The array can be shorter
    than 16 channels; only the provided values are set.

    .EXAMPLE
    # Set channels 0-3 to different angles
    Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees @(0, 45, 90, 135)

    .EXAMPLE
    # Set all 4 servos on a pan-tilt rig to different positions
    $positions = @(45, 70, 45, 70)   # Pan L, Tilt Down, Pan L, Tilt Down (example)
    Invoke-PsGadgetPca9685SetChannels -PsGadget $pca -Degrees $positions

    .NOTES
    Returns $true on success, $false on failure. Errors are logged but not thrown.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [PsGadgetPca9685]$PsGadget,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [int[]]$Degrees
    )

    return $PsGadget.SetChannels($Degrees)
}
