#Requires -Version 5.1
# Get-FtdiEeprom.ps1
# Read FTDI device EEPROM by index or serial number (no live connection required).

function Get-FtdiEeprom {
    <#
    .SYNOPSIS
    Reads the EEPROM of an FTDI device by index or serial number.

    .DESCRIPTION
    Reads the device-specific EEPROM via the FTD2XX_NET library and returns a
    structured object containing USB descriptor fields and chip-specific settings
    such as CBUS pin function assignments, signal inversion flags, and driver mode.

    The device must NOT be open (no active New-PsGadgetFtdi connection) when this
    is called. To read EEPROM from a connected device object, use Get-PsGadgetFtdiEeprom.

    Supported device types: FT232R / FT232RL / FT232RNL / FT232H

    .PARAMETER Index
    Zero-based index of the device to read (as shown by Get-FtdiDevice).

    .PARAMETER SerialNumber
    Alternative to Index: identify the target device by its serial number string.

    .EXAMPLE
    # Show EEPROM for the first connected FTDI device
    Get-FtdiEeprom -Index 0

    .EXAMPLE
    # Read EEPROM for a specific device and inspect CBUS modes
    $ee = Get-FtdiEeprom -Index 1
    $ee | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

    .EXAMPLE
    # Check whether CBUS pins are already configured for GPIO
    $ee = Get-FtdiEeprom -SerialNumber "BG01X3AK"
    if ($ee.Cbus0 -ne 'FT_CBUS_IOMODE') {
        Write-Host "Run Set-PsGadgetFt232rCbusMode to enable CBUS GPIO"
    }

    .OUTPUTS
    PSCustomObject with EEPROM fields, or $null on failure.
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIndex', Position = 0)]
        [int]$Index,

        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [string]$SerialNumber
    )

    try {
        $devices = Get-FtdiDeviceList
        $targetDev = $null

        if ($PSCmdlet.ParameterSetName -eq 'BySerial') {
            $targetDev = $devices | Where-Object { $_.SerialNumber -eq $SerialNumber } | Select-Object -First 1
            if (-not $targetDev) {
                throw "No FTDI device found with serial number '$SerialNumber'"
            }
        } else {
            $targetDev = $devices | Where-Object { $_.Index -eq $Index } | Select-Object -First 1
            if (-not $targetDev) {
                throw "Device at index $Index not found. Run Get-FtdiDevice to check available devices."
            }
        }

        Write-Verbose "Reading EEPROM for $($targetDev.Type) - $($targetDev.Description) ($($targetDev.SerialNumber))"

        switch -Regex ($targetDev.Type) {
            '^FT232R(L|NL)?$' {
                return Get-FtdiFt232rEeprom -Index $targetDev.Index -SerialNumber $targetDev.SerialNumber
            }
            '^FT232H$' {
                return Get-FtdiFt232hEeprom -Index $targetDev.Index -SerialNumber $targetDev.SerialNumber
            }
            default {
                Write-Warning (
                    "EEPROM read for '$($targetDev.Type)' is not yet implemented. " +
                    "Currently supported: FT232R / FT232RL / FT232RNL / FT232H."
                )
                return $null
            }
        }

    } catch {
        Write-Error "Get-FtdiEeprom failed: $_"
        return $null
    }
}
