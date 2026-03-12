# Invoke-PsGadgetI2CScan.ps1
# Public wrapper over Invoke-FtdiI2CScan for I2C bus scanning via FT232H MPSSE.

#Requires -Version 5.1

function Invoke-PsGadgetI2CScan {
    <#
    .SYNOPSIS
    Scans the I2C bus for connected devices via FT232H MPSSE.

    .DESCRIPTION
    Probes all standard 7-bit I2C addresses (0x08-0x77) and returns an object
    for each address that ACKs. Device must be in MpsseI2c mode first.

    .PARAMETER PsGadget
    A PsGadgetFtdi object in MpsseI2c mode (from New-PsGadgetFtdi).

    .PARAMETER ClockFrequency
    I2C SCL frequency in Hz. Default 100000 (standard mode).

    .EXAMPLE
    $dev = New-PsGadgetFtdi -Index 0
    Set-PsGadgetFtdiMode -PsGadget $dev -Mode MpsseI2c
    Invoke-PsGadgetI2CScan -PsGadget $dev
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [object]$PsGadget,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1000, 400000)]
        [int]$ClockFrequency = 100000
    )

    if (-not $PsGadget.IsOpen -or -not $PsGadget._connection) {
        throw "PsGadgetFtdi is not open. Call New-PsGadgetFtdi first."
    }

    Invoke-FtdiI2CScan -Connection $PsGadget._connection -ClockFrequency $ClockFrequency
}
