# Send-PsGadgetI2CWrite.ps1
# Public thin wrapper over Send-MpsseI2CWrite for MPSSE I2C writes.

#Requires -Version 5.1

function Send-PsGadgetI2CWrite {
    <#
    .SYNOPSIS
    Writes bytes to an I2C device via FT232H MPSSE.

    .DESCRIPTION
    Sends a START, 7-bit address (write), one or more data bytes, and STOP
    over the MPSSE I2C bus.  The device must already be in MpsseI2c mode
    (call Set-PsGadgetFtdiMode -Mode MpsseI2c once before using this).

    .PARAMETER PsGadget
    A PsGadgetFtdi object in MpsseI2c mode (from New-PsGadgetFtdi).

    .PARAMETER Address
    7-bit I2C slave address (e.g. 0x40 for PCA9685, 0x3C for SSD1306).

    .PARAMETER Data
    One or more bytes to write after the address byte.

    .PARAMETER ByteDump
    When specified, logs each transmitted byte and its ACK status to Verbose.

    .EXAMPLE
    # Write register 0x00 = 0x10 to PCA9685 at 0x40
    Send-PsGadgetI2CWrite -PsGadget $dev -Address 0x40 -Data @(0x00, 0x10)

    .EXAMPLE
    # 5-byte register write (PCA9685 channel 0 OFF count)
    Send-PsGadgetI2CWrite -PsGadget $dev -Address 0x40 -Data @(0x06, 0,0,150,0)

    .NOTES
    Wraps Send-MpsseI2CWrite from Private/Ftdi.Mpsse.ps1.
    Wire D0->SCL, D1->SDA with 4.7k pull-ups on both lines.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [PsGadgetFtdi]$PsGadget,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(0, 127)]
        [byte]$Address,

        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Data,

        [Parameter(Mandatory = $false)]
        [switch]$ByteDump
    )

    if (-not $PsGadget.IsOpen -or -not $PsGadget._connection) {
        throw "PsGadgetFtdi is not open. Call New-PsGadgetFtdi first."
    }

    if ($PsGadget._connection.GpioMethod -ne 'MpsseI2c') {
        throw "Device not in MpsseI2c mode. Run Set-PsGadgetFtdiMode -Mode MpsseI2c first."
    }

    Send-MpsseI2CWrite -DeviceHandle $PsGadget._connection `
                       -Address $Address `
                       -Data $Data `
                       -ByteDump:$ByteDump
}
