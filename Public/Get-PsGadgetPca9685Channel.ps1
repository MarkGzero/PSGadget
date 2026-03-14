#Requires -Version 5.1
# DEPRECATED - use Invoke-PsGadgetI2C -I2CModule PCA9685 instead.
# This file remains loaded as a private helper for internal use.

function Get-PsGadgetPca9685Channel {
    <#
    .SYNOPSIS
    Gets the current servo angle for a PCA9685 channel.

    .DESCRIPTION
    Returns the last known servo angle (in degrees) that was set on the specified channel.
    This reads from the local cache; it does not query the device.

    .PARAMETER PsGadget
    The PsGadgetPca9685 instance (from Connect-PsGadgetPca9685).

    .PARAMETER Channel
    The channel number to read (0-15).

    .EXAMPLE
    # Get current angle for channel 0
    $angle = Get-PsGadgetPca9685Channel -PsGadget $pca -Channel 0

    .NOTES
    Returns an integer (0-180 degrees) representing the last known position.
    #>

    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [PsGadgetPca9685]$PsGadget,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(0, 15)]
        [int]$Channel
    )

    return $PsGadget.GetChannel($Channel)
}
