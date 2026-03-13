#Requires -Version 5.1

function Get-PsGadgetPca9685Frequency {
    <#
    .SYNOPSIS
    Gets the current PWM frequency of a PCA9685 device.

    .DESCRIPTION
    Returns the current operating frequency in Hz for the PCA9685.

    .PARAMETER PsGadget
    The PsGadgetPca9685 instance (from Connect-PsGadgetPca9685).

    .EXAMPLE
    # Get the current frequency
    $freq = Get-PsGadgetPca9685Frequency -PsGadget $pca

    .NOTES
    Returns an integer representing the frequency in Hz.
    #>

    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [PsGadgetPca9685]$PsGadget
    )

    return $PsGadget.GetFrequency()
}
