# Set-PsGadgetFt232rCbusMode.ps1
# Public function to program FT232R CBUS pin functions via EEPROM.

#Requires -Version 5.1

function Set-PsGadgetFt232rCbusMode {
    <#
    .SYNOPSIS
    Programs the FT232R EEPROM to configure CBUS pins for GPIO bit-bang mode.

    .DESCRIPTION
    Writes the FT232R device EEPROM to assign the specified CBUS pins to
    FT_CBUS_IOMODE (or any other supported FT_CBUS_OPTIONS function).

    This is a one-time setup step that replaces the need for FTDI's FT_PROG tool.
    After writing, you must disconnect and reconnect the USB device for the new
    EEPROM settings to take effect.

    Once CBUS pins are set to FT_CBUS_IOMODE, Set-PsGadgetGpio can control them
    directly without any additional EEPROM changes.

    Workflow:
        1. Run Set-PsGadgetFt232rCbusMode once per device to enable GPIO on CBUS pins.
        2. Reconnect the USB device.
        3. Use Set-PsGadgetGpio -DeviceIndex N -Pins @(0..3) -State HIGH/LOW freely.

    Available -Mode values:
        FT_CBUS_IOMODE       GPIO / bit-bang  [DEFAULT - enables Set-PsGadgetGpio]
        FT_CBUS_TXLED        Pulses on Tx data
        FT_CBUS_RXLED        Pulses on Rx data
        FT_CBUS_TXRXLED      Pulses on Tx or Rx data
        FT_CBUS_PWREN        Power-on signal (PWREN#, active low)
        FT_CBUS_SLEEP        Sleep indicator
        FT_CBUS_CLK48        48 MHz clock output
        FT_CBUS_CLK24        24 MHz clock output
        FT_CBUS_CLK12        12 MHz clock output
        FT_CBUS_CLK6         6 MHz clock output
        FT_CBUS_TXDEN        Tx Data Enable
        FT_CBUS_BITBANG_WR   Bit-bang write strobe
        FT_CBUS_BITBANG_RD   Bit-bang read strobe

    .PARAMETER Index
    Zero-based device index (from List-PsGadgetFtdi).

    .PARAMETER SerialNumber
    Alternative to Index: specify the target device by serial number string.

    .PARAMETER Pins
    The CBUS pin numbers to reconfigure (0-3). Defaults to @(0,1,2,3) so all four
    CBUS bit-bang pins are enabled in one call.

    .PARAMETER Mode
    The FT_CBUS_OPTIONS mode name to write. Defaults to FT_CBUS_IOMODE (GPIO).

    .PARAMETER WhatIf
    Shows what EEPROM change would be made without writing anything.

    .EXAMPLE
    # Configure all four CBUS pins as GPIO on device 0 (most common usage):
    Set-PsGadgetFt232rCbusMode -Index 0

    .EXAMPLE
    # Configure only CBUS0 and CBUS1 as GPIO; leave CBUS2/3 unchanged:
    Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0, 1)

    .EXAMPLE
    # Set CBUS0 to Rx LED instead of GPIO:
    Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0) -Mode FT_CBUS_RXLED

    .EXAMPLE
    # Preview what would change without writing:
    Set-PsGadgetFt232rCbusMode -Index 0 -WhatIf

    .NOTES
    - Only CBUS pins 0-3 are configurable. CBUS4 is a special-purpose pin.
    - The EEPROM change does NOT take effect until the USB device is replugged.
    - To verify the EEPROM after replugging, use Get-PsGadgetFtdiEeprom.
    - This function only works on Windows with the D2XX driver loaded.
    #>

    [CmdletBinding(
        DefaultParameterSetName = 'ByIndex',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIndex', Position = 0)]
        [int]$Index,

        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [string]$SerialNumber,

        [Parameter(Mandatory = $true, ParameterSetName = 'PsGadget', Position = 0)]
        [ValidateNotNull()]
        [PsGadgetFtdi]$PsGadget,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(0, 4)]
        [int[]]$Pins = @(0, 1, 2, 3),

        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateSet(
            'FT_CBUS_TXDEN','FT_CBUS_PWREN','FT_CBUS_RXLED','FT_CBUS_TXLED',
            'FT_CBUS_TXRXLED','FT_CBUS_SLEEP','FT_CBUS_CLK48','FT_CBUS_CLK24',
            'FT_CBUS_CLK12','FT_CBUS_CLK6','FT_CBUS_IOMODE',
            'FT_CBUS_BITBANG_WR','FT_CBUS_BITBANG_RD'
        )]
        [string]$Mode = 'FT_CBUS_IOMODE'
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

        # Validate that the target is an FT232R family device
        $deviceList = Get-FtdiDeviceList
        $targetDev  = $null
        foreach ($d in @($deviceList)) {
            if ($d.Index -eq $targetIndex) {
                $targetDev = $d
                break
            }
        }

        if (-not $targetDev) {
            throw "Device at index $targetIndex not found. Run List-PsGadgetFtdi to check available devices."
        }

        if ($targetDev.Type -notmatch '^FT232R(L|NL)?$') {
            throw (
                "Device '$($targetDev.Type)' ($($targetDev.SerialNumber)) is not an FT232R family device. " +
                "Set-PsGadgetFt232rCbusMode only supports FT232R / FT232RL / FT232RNL."
            )
        }

        # Show current EEPROM state for context
        Write-Verbose "Reading current EEPROM for $($targetDev.Description) ($($targetDev.SerialNumber))..."
        $current = Get-FtdiFt232rEeprom -Index $targetIndex -SerialNumber $targetDev.SerialNumber
        if ($current) {
            $pinLines = $Pins | ForEach-Object {
                $cur = $current."Cbus$_"
                "  CBUS$_ : $cur -> $Mode"
            }
            Write-Verbose "EEPROM changes planned:`n$($pinLines -join "`n")"
        }

        # Confirm and write
        $pinNames  = ($Pins | ForEach-Object { "CBUS$_" }) -join ', '
        $operation = "Write FT232R EEPROM: set $pinNames to $Mode"

        if (-not $PSCmdlet.ShouldProcess("$($targetDev.Description) ($($targetDev.SerialNumber))", $operation)) {
            return $null
        }

        $result = Set-FtdiFt232rCbusPinMode -Index $targetIndex -Pins $Pins -Mode $Mode -SerialNumber $targetDev.SerialNumber

        if ($result.Success) {
            Write-Host "FT232R EEPROM updated: $pinNames set to $Mode." -ForegroundColor Green
            Write-Host "ACTION REQUIRED: Disconnect and reconnect the USB device for changes to take effect." -ForegroundColor Yellow
        }

        return $result

    } catch {
        Write-Error "Set-PsGadgetFt232rCbusMode failed: $_"
        return $null
    }
}
