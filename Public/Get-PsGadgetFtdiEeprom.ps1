#Requires -Version 5.1
# Get-PsGadgetFtdiEeprom.ps1
# Read FTDI EEPROM from a connected PsGadgetFtdi device object.

function Get-PsGadgetFtdiEeprom {
    <#
    .SYNOPSIS
    Reads the EEPROM of a connected PsGadgetFtdi device object.

    .DESCRIPTION
    Delegates to Get-FtdiEeprom using the index from the connected device.
    The device must be open (created via New-PsGadgetFtdi).

    To read EEPROM without a live connection, use Get-FtdiEeprom -Index or -SerialNumber.

    .PARAMETER PsGadget
    A connected PsGadgetFtdi object (from New-PsGadgetFtdi).

    .EXAMPLE
    $ft1 = New-PsGadgetFtdi -Index 0
    Get-PsGadgetFtdiEeprom -PsGadget $ft1

    .EXAMPLE
    $ft1 = New-PsGadgetFtdi -Index 0
    $ft1 | Get-PsGadgetFtdiEeprom

    .OUTPUTS
    PSCustomObject with EEPROM fields, or $null on failure.
    #>

    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [PsGadgetFtdi]$PsGadget
    )

    Get-FtdiEeprom -Index $PsGadget.Index
}
