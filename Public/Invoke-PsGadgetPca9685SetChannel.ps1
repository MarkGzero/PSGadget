#Requires -Version 5.1

function Invoke-PsGadgetPca9685SetChannel {
    <#
    .SYNOPSIS
    Sets a PCA9685 servo channel to a specific angle.

    .DESCRIPTION
    Sends an I2C command to set a single PWM channel on the PCA9685 to the desired
    servo angle. The angle is converted to the appropriate pulse width (1.0-2.0 ms)
    and PWM counts.

    .PARAMETER PsGadget
    The PsGadgetPca9685 instance (from Connect-PsGadgetPca9685).

    .PARAMETER Channel
    The channel number to set (0-15).

    .PARAMETER Degrees
    The servo angle in degrees (0-180). Values outside this range are clamped.

    .EXAMPLE
    # Set channel 0 to 90 degrees (center position)
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 0 -Degrees 90

    .EXAMPLE
    # Set channel 3 to 45 degrees (quarter travel, counterclockwise)
    Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel 3 -Degrees 45

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
        [ValidateRange(0, 15)]
        [int]$Channel,

        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateRange(0, 180)]
        [int]$Degrees
    )

    return $PsGadget.SetChannel($Channel, $Degrees)
}
