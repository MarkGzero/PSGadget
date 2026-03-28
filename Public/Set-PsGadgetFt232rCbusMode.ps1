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
    After writing, the function will prompt you to either cycle the USB port
    automatically (no cable unplug required) or replug the cable manually.

    Once CBUS pins are set to FT_CBUS_IOMODE, Set-PsGadgetGpio can control them
    directly without any additional EEPROM changes.

    Workflow:
        1. Run Set-PsGadgetFt232rCbusMode once per device to enable GPIO on CBUS pins.
        2. Accept the prompt to cycle the port, or unplug and replug the USB cable.
        3. Use Set-PsGadgetGpio -Index N -Pins @(0..3) -State HIGH/LOW freely.

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
    Zero-based device index (from Get-FtdiDevice).

    .PARAMETER SerialNumber
    Alternative to Index: specify the target device by serial number string.

    .PARAMETER Pins
    The CBUS pin numbers to reconfigure (0-3). Defaults to @(0,1,2,3) so all four
    CBUS bit-bang pins are enabled in one call.

    .PARAMETER Mode
    The FT_CBUS_OPTIONS mode name to write. Defaults to FT_CBUS_IOMODE (GPIO).

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

    .PARAMETER HighDriveIOs
    Override the ftdi.highDriveIOs config setting for this call.
    When omitted, the value from Get-PsGadgetConfig is used (default: $false).
    $true doubles CBUS drive strength from 4 mA to 8 mA.

    .PARAMETER PullDownEnable
    Override the ftdi.pullDownEnable config setting for this call.
    When omitted, the value from Get-PsGadgetConfig is used (default: $false).
    $true adds weak pull-downs on all I/O pins during USB suspend.

    .PARAMETER RIsD2XX
    Override the ftdi.rIsD2XX config setting for this call.
    When omitted, the value from Get-PsGadgetConfig is used (default: $false).
    $true makes the device enumerate as D2XX-only (no duplicate COM port).

    .NOTES
    - Only CBUS pins 0-3 are configurable. CBUS4 is a special-purpose pin.
    - After a successful write, the function prompts to cycle the USB port
      automatically. Accepting is equivalent to physically unplugging and replugging.
    - The result object includes a PortCycled property indicating whether the port
      was cycled automatically (True) or left for manual replug (False).
    - HighDriveIOs, PullDownEnable, and RIsD2XX default to the values in
      ~/.psgadget/config.json (see Get-Help about_PsGadgetConfig).
    - To verify the EEPROM after cycling/replugging, use Get-PsGadgetFtdiEeprom.
    - This function requires Windows with the D2XX driver loaded.
      On Linux, use an FT232H device instead -- it has MPSSE and is fully supported
      via the IoT backend without any EEPROM pre-programming step.
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
        [string]$Mode = 'FT_CBUS_IOMODE',

        # EEPROM flag overrides -- when omitted the value from config.json is used.
        [Parameter(Mandatory = $false)]
        [System.Nullable[bool]]$HighDriveIOs,

        [Parameter(Mandatory = $false)]
        [System.Nullable[bool]]$PullDownEnable,

        [Parameter(Mandatory = $false)]
        [System.Nullable[bool]]$RIsD2XX
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
            throw "Device at index $targetIndex not found. Run Get-FtdiDevice to check available devices."
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

        # Resolve EEPROM flags: explicit param wins over config default
        $cfg = $script:PsGadgetConfig
        $resolvedHighDriveIOs   = if ($null -ne $HighDriveIOs)   { [bool]$HighDriveIOs }   else { $cfg.ftdi.highDriveIOs }
        $resolvedPullDownEnable = if ($null -ne $PullDownEnable)  { [bool]$PullDownEnable }  else { $cfg.ftdi.pullDownEnable }
        $resolvedRIsD2XX        = if ($null -ne $RIsD2XX)         { [bool]$RIsD2XX }         else { $cfg.ftdi.rIsD2XX }

        $result = Set-FtdiFt232rCbusPinMode -Index $targetIndex -Pins $Pins -Mode $Mode `
            -SerialNumber $targetDev.SerialNumber `
            -HighDriveIOs $resolvedHighDriveIOs `
            -PullDownEnable $resolvedPullDownEnable `
            -RIsD2XX $resolvedRIsD2XX

        if ($result.Success) {
            Write-Verbose "FT232R EEPROM updated: $pinNames set to $Mode."

            # Inform the user and offer automatic port cycling.
            Write-Host ""
            Write-Host "EEPROM written successfully."
            Write-Host "The new CBUS pin settings will not take effect until the device re-enumerates on the USB bus."
            Write-Host ""
            Write-Host "You have two options:"
            Write-Host "  [Y] Cycle the USB port automatically right now (no cable unplug needed)"
            Write-Host "  [N] Unplug and replug the USB cable manually, then continue"
            Write-Host ""

            $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
                [System.Management.Automation.Host.ChoiceDescription]::new(
                    '&Yes',
                    'Cycle the USB port now. The device will briefly disconnect and reconnect automatically without needing to physically unplug the cable.'
                )
                [System.Management.Automation.Host.ChoiceDescription]::new(
                    '&No',
                    'Skip automatic cycling. Unplug and replug the USB cable manually, then continue.'
                )
            )

            $choice = $Host.UI.PromptForChoice(
                'Apply EEPROM Changes',
                'Cycle the USB port now to apply the new settings?',
                $choices,
                0   # default = Yes
            )

            if ($choice -eq 0) {
                Write-Host ""
                Write-Host "Cycling USB port on $($targetDev.Description) ($($targetDev.SerialNumber))..."
                try {
                    $cycleDevice = [PsGadgetFtdi]::new([int]$targetIndex)
                    $cycleDevice.Connect()
                    $cycleDevice.CyclePort()

                    Write-Host ""
                    Write-Host "Port cycled successfully. The device has re-enumerated with the new EEPROM settings."
                    Write-Host "You can now use Set-PsGadgetGpio or Connect-PsGadgetFtdi immediately."
                    Write-Host ""
                    Write-Host "To verify the new settings:"
                    Write-Host "  Get-PsGadgetFtdiEeprom -Index $targetIndex | Select-Object Cbus0, Cbus1, Cbus2, Cbus3"

                    $result | Add-Member -MemberType NoteProperty -Name 'PortCycled' -Value $true -Force
                } catch {
                    Write-Warning "CyclePort failed: $_"
                    Write-Warning "Please unplug and replug the USB cable manually to apply the new EEPROM settings."
                    $result | Add-Member -MemberType NoteProperty -Name 'PortCycled' -Value $false -Force
                }
            } else {
                Write-Host ""
                Write-Host "ACTION REQUIRED: Unplug and replug the USB cable to activate the new EEPROM settings."
                Write-Host ""
                Write-Host "After replugging, verify the change with:"
                Write-Host "  Get-PsGadgetFtdiEeprom -Index $targetIndex | Select-Object Cbus0, Cbus1, Cbus2, Cbus3"
                Write-Host ""
                $result | Add-Member -MemberType NoteProperty -Name 'PortCycled' -Value $false -Force
            }
        }

        return $result

    } catch {
        Write-Error "Set-PsGadgetFt232rCbusMode failed: $_"
        return $null
    }
}
