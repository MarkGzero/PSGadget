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
    A PsGadgetFtdi object (from New-PsGadgetFtdi). Device is NOT closed after the call.

    .PARAMETER Index
    FTDI device index (0-based). Device is opened, scanned, then closed automatically.

    .PARAMETER SerialNumber
    FTDI device serial number. Device is opened, scanned, then closed automatically.

    .PARAMETER ClockFrequency
    I2C SCL frequency in Hz. Default 100000 (standard mode).

    .EXAMPLE
    Invoke-PsGadgetI2CScan -Index 0

    .EXAMPLE
    $dev = New-PsGadgetFtdi -Index 0
    Invoke-PsGadgetI2CScan -PsGadget $dev
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByDevice')]
    [OutputType([System.Int32[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByDevice')]
        [ValidateNotNull()]
        [object]$PsGadget,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByIndex')]
        [ValidateRange(0, 127)]
        [int]$Index,

        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1000, 400000)]
        [int]$ClockFrequency = 100000
    )

    $ownsDevice = $PSCmdlet.ParameterSetName -ne 'ByDevice'
    $ftdi = $null
    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByDevice') {
            $ftdi = $PsGadget
            if (-not $ftdi.IsOpen -or -not $ftdi._connection) {
                throw "PsGadgetFtdi is not open. Call New-PsGadgetFtdi first."
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'BySerial') {
            Write-Verbose "Opening FTDI device serial '$SerialNumber' for I2C scan"
            $ftdi = New-PsGadgetFtdi -SerialNumber $SerialNumber
        } else {
            Write-Verbose "Opening FTDI device index $Index for I2C scan"
            $ftdi = New-PsGadgetFtdi -Index $Index
        }

        if (-not $ftdi -or -not $ftdi.IsOpen) {
            throw "Failed to open FTDI device"
        }

        Set-PsGadgetFtdiMode -PsGadget $ftdi -Mode MpsseI2c | Out-Null
        Invoke-FtdiI2CScan -Connection $ftdi._connection -ClockFrequency $ClockFrequency
    } finally {
        if ($ownsDevice -and $ftdi -and $ftdi.IsOpen) {
            Write-Verbose "Closing FTDI device"
            $ftdi.Close()
        }
    }
}
