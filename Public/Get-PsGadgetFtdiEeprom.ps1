# Get-PsGadgetFtdiEeprom.ps1
# Public function to read and display FTDI device EEPROM contents.

#Requires -Version 5.1

function Get-PsGadgetFtdiEeprom {
    <#
    .SYNOPSIS
    Reads and returns the EEPROM contents of a connected FTDI device.

    .DESCRIPTION
    Reads the device-specific EEPROM via the FTD2XX_NET library and returns a
    structured object containing USB descriptor fields and chip-specific settings
    such as CBUS pin function assignments, signal inversion flags, and driver mode.

    This is useful for:
      - Inspecting current CBUS pin assignments on FT232R boards before using GPIO
      - Verifying serial number, description, and USB power settings
      - Confirming driver mode (D2XX vs VCP) on FT232R

    Supported device types:  FT232R / FT232RL / FT232RNL
    (Support for FT232H, FT2232H, FT4232H, and X-Series will be added in a future release.)

    .PARAMETER Index
    Zero-based index of the device to read (as shown by List-PsGadgetFtdi).

    .PARAMETER SerialNumber
    Alternative to Index: identify the target device by its serial number string.

    .EXAMPLE
    # Show EEPROM for the first connected FTDI device
    Get-PsGadgetFtdiEeprom -Index 0

    .EXAMPLE
    # Read EEPROM for a specific device and inspect CBUS modes
    $ee = Get-PsGadgetFtdiEeprom -Index 0
    $ee | Select-Object Cbus0, Cbus1, Cbus2, Cbus3

    .EXAMPLE
    # Check whether CBUS pins are already configured for GPIO
    $ee = Get-PsGadgetFtdiEeprom -Index 0
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
        [string]$SerialNumber,

        [Parameter(Mandatory = $true, ParameterSetName = 'PsGadget', Position = 0)]
        [ValidateNotNull()]
        [PsGadgetFtdi]$PsGadget
    )

    try {
        # Resolve device index
        $targetIndex = $Index
        if ($PSCmdlet.ParameterSetName -eq 'BySerial') {
            $devices = Get-FtdiDeviceList
            $match   = $devices | Where-Object { $_.SerialNumber -eq $SerialNumber }
            if (-not $match) {
                throw "No FTDI device found with serial number '$SerialNumber'"
            }
            $targetIndex = $match.Index
        } elseif ($PSCmdlet.ParameterSetName -eq 'PsGadget') {
            $targetIndex = $PsGadget.Index
        }

        # Identify device type so we can call the right EEPROM reader
        $devices    = Get-FtdiDeviceList
        $targetDev  = $null
        foreach ($d in @($devices)) {
            if ($d.Index -eq $targetIndex) {
                $targetDev = $d
                break
            }
        }

        if (-not $targetDev) {
            throw "Device at index $targetIndex not found. Run List-PsGadgetFtdi to check available devices."
        }

        Write-Verbose "Reading EEPROM for $($targetDev.Type) - $($targetDev.Description) ($($targetDev.SerialNumber))"

        # Dispatch to device-type-specific reader
        switch -Regex ($targetDev.Type) {
            '^FT232R(L|NL)?$' {
                return Get-FtdiFt232rEeprom -Index $targetIndex -SerialNumber $targetDev.SerialNumber
            }
            default {
                Write-Warning (
                    "EEPROM read for '$($targetDev.Type)' is not yet implemented. " +
                    "Currently supported: FT232R / FT232RL / FT232RNL."
                )
                return $null
            }
        }

    } catch {
        Write-Error "Get-PsGadgetFtdiEeprom failed: $_"
        return $null
    }
}
