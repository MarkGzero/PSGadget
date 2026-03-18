# Set-PsGadgetFtdiEeprom.ps1
# Unified EEPROM write function for FT232H and FT232R devices.

#Requires -Version 5.1

function Set-PsGadgetFtdiEeprom {
    <#
    .SYNOPSIS
    Writes EEPROM settings for an FT232H or FT232R device.

    .DESCRIPTION
    Single command for all EEPROM-level configuration changes across supported FTDI
    chips. Dispatches to the correct EEPROM writer based on device type.

    FT232H capabilities:
      -DisableVcp    Clears the IsVCP flag so the chip enumerates as D2XX-only.
                     Eliminates the duplicate COM port that prevents MPSSE from
                     getting exclusive control of the device.  [Most common usage]
      -EnableVcp     Re-enables the VCP COM port if you need serial access again.
      -CbusPins      Hashtable of ACBUS pin number (0-9) -> mode name. Useful for
                     configuring ACBUS pins as GPIO (FT_CBUS_IOMODE), clock outputs,
                     LED indicators, etc.
      -ACDriveCurrent / -ADDriveCurrent
                     Override ACBUS/ADBUS output drive strength (4, 8, 12, or 16 mA).

    FT232R capabilities:
      -CbusPins      Hashtable of CBUS pin number (0-3) -> mode name. The most common
                     use is setting pins to FT_CBUS_IOMODE to enable GPIO bit-bang.
                     Note: -CbusPins on FT232R maps to Set-FtdiFt232rCbusPinMode
                     internally; same end result as Set-PsGadgetFt232rCbusMode.
      -DisableVcp    Sets the RIsD2XX flag to $true (D2XX-only enumeration).
      -EnableVcp     Sets the RIsD2XX flag to $false (VCP COM port visible).

    After writing, the function prompts to cycle the USB port automatically.
    Accepting is equivalent to physically unplugging and replugging the cable.

    Quick recovery: if MPSSE does not work due to a VCP driver conflict, the fix is:
        Set-PsGadgetFtdiEeprom -Index 0 -DisableVcp

    .PARAMETER Index
    Zero-based device index (as shown by Get-PsGadgetFtdi).

    .PARAMETER SerialNumber
    Alternative to Index: identify the device by serial number string.

    .PARAMETER PsGadget
    A PsGadgetFtdi object. The device must NOT be open when running EEPROM writes.
    Call $dev.Close() before running this command.

    .PARAMETER DisableVcp
    FT232H: clear IsVCP (device enumerates as D2XX-only, no COM port).
    FT232R: set RIsD2XX = $true (same effect).
    After replug, the duplicate COM port will be gone.

    .PARAMETER EnableVcp
    FT232H: set IsVCP = $true (re-enables the COM port).
    FT232R: set RIsD2XX = $false.

    .PARAMETER CbusPins
    Hashtable mapping pin numbers to mode names to write into EEPROM.

    FT232H pin numbers: 0-9 (ACBUS0-ACBUS9)
    Valid mode names for FT232H:
        FT_CBUS_TRISTATE     High-Z / unused [factory default]
        FT_CBUS_IOMODE       GPIO bit-bang
        FT_CBUS_TXLED        Tx LED indicator
        FT_CBUS_RXLED        Rx LED indicator
        FT_CBUS_TXRXLED      Tx/Rx LED indicator
        FT_CBUS_PWREN        Power-on signal (active low)
        FT_CBUS_SLEEP        Sleep indicator
        FT_CBUS_DRIVE_0      Drive output LOW
        FT_CBUS_DRIVE_1      Drive output HIGH
        FT_CBUS_TXDEN        Tx Data Enable
        FT_CBUS_CLK30        30 MHz clock output
        FT_CBUS_CLK15        15 MHz clock output
        FT_CBUS_CLK7_5       7.5 MHz clock output

    FT232R pin numbers: 0-3 (CBUS0-CBUS3)
    Valid mode names for FT232R:
        FT_CBUS_IOMODE       GPIO bit-bang  [use this to enable Set-PsGadgetGpio]
        FT_CBUS_TXLED        Tx LED
        FT_CBUS_RXLED        Rx LED
        FT_CBUS_TXRXLED      Tx/Rx LED
        FT_CBUS_PWREN        Power-on signal
        FT_CBUS_SLEEP        Sleep indicator
        FT_CBUS_CLK48        48 MHz clock
        FT_CBUS_CLK24        24 MHz clock
        FT_CBUS_CLK12        12 MHz clock
        FT_CBUS_CLK6         6 MHz clock
        FT_CBUS_TXDEN        Tx Data Enable

    .PARAMETER ACDriveCurrent
    FT232H only. Set ACBUS output drive current (4, 8, 12, or 16 mA). Default 4 mA.

    .PARAMETER ADDriveCurrent
    FT232H only. Set ADBUS output drive current (4, 8, 12, or 16 mA). Default 4 mA.

    .EXAMPLE
    # FT232H: disable the VCP COM port so MPSSE can get exclusive control
    Set-PsGadgetFtdiEeprom -Index 0 -DisableVcp

    .EXAMPLE
    # FT232H: identify by serial number
    Set-PsGadgetFtdiEeprom -SerialNumber FTAXBFCQ -DisableVcp

    .EXAMPLE
    # FT232H: disable VCP and configure ACBUS5 as GPIO in one EEPROM write
    Set-PsGadgetFtdiEeprom -Index 0 -DisableVcp -CbusPins @{ 5 = 'FT_CBUS_IOMODE' }

    .EXAMPLE
    # FT232R: configure CBUS0-CBUS3 for GPIO bit-bang (one-time setup)
    Set-PsGadgetFtdiEeprom -Index 1 -CbusPins @{ 0='FT_CBUS_IOMODE'; 1='FT_CBUS_IOMODE'; 2='FT_CBUS_IOMODE'; 3='FT_CBUS_IOMODE' }

    .EXAMPLE
    # FT232R: disable VCP enumeration (use D2XX only)
    Set-PsGadgetFtdiEeprom -Index 1 -DisableVcp

    .NOTES
    - Device must NOT have an open handle when running this command. If $dev is open,
      call $dev.Close() first. Otherwise D2XX returns FT_DEVICE_NOT_OPENED.
    - EEPROM changes require a USB replug (or CyclePort) to take effect.
    - Use Get-PsGadgetFtdiEeprom before and after to verify the change.
    - This function requires Windows with the D2XX driver loaded.
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

        [Parameter(Mandatory = $false)]
        [switch]$DisableVcp,

        [Parameter(Mandatory = $false)]
        [switch]$EnableVcp,

        [Parameter(Mandatory = $false)]
        [hashtable]$CbusPins,

        [Parameter(Mandatory = $false)]
        [ValidateSet(4, 8, 12, 16)]
        [System.Nullable[int]]$ACDriveCurrent,

        [Parameter(Mandatory = $false)]
        [ValidateSet(4, 8, 12, 16)]
        [System.Nullable[int]]$ADDriveCurrent
    )

    try {
        if ($DisableVcp -and $EnableVcp) {
            throw "-DisableVcp and -EnableVcp cannot both be specified."
        }

        # Resolve device index and type
        $targetIndex = $Index
        $targetDev   = $null

        if ($PSCmdlet.ParameterSetName -eq 'BySerial') {
            $devices = Get-FtdiDeviceList
            $targetDev = $devices | Where-Object { $_.SerialNumber -eq $SerialNumber } | Select-Object -First 1
            if (-not $targetDev) {
                throw "No FTDI device found with serial number '$SerialNumber'"
            }
            $targetIndex = $targetDev.Index
        } elseif ($PSCmdlet.ParameterSetName -eq 'PsGadget') {
            $targetIndex = $PsGadget.Index
        }

        if (-not $targetDev) {
            $deviceList = Get-FtdiDeviceList
            foreach ($d in @($deviceList)) {
                if ($d.Index -eq $targetIndex) { $targetDev = $d; break }
            }
        }

        if (-not $targetDev) {
            throw "Device at index $targetIndex not found. Run Get-PsGadgetFtdi to check available devices."
        }

        Write-Verbose "Target: $($targetDev.Type) - $($targetDev.Description) ($($targetDev.SerialNumber))"

        # --- FT232H path ---
        if ($targetDev.Type -match '^FT232H$') {
            # Map -DisableVcp/-EnableVcp to IsVCP nullable
            $vcpFlag = $null
            if ($DisableVcp) { $vcpFlag = $false }
            if ($EnableVcp)  { $vcpFlag = $true  }

            if (-not $PSCmdlet.ShouldProcess(
                "$($targetDev.Description) ($($targetDev.SerialNumber))",
                "Write FT232H EEPROM$(if ($null -ne $vcpFlag) { ': IsVCP=' + $vcpFlag })$(if ($CbusPins) { ' + CbusPins' })")) {
                return $null
            }

            $result = Set-FtdiFt232hEepromMode `
                -Index $targetIndex `
                -SerialNumber $targetDev.SerialNumber `
                -IsVCP $vcpFlag `
                -CbusPins $CbusPins `
                -ACDriveCurrent $ACDriveCurrent `
                -ADDriveCurrent $ADDriveCurrent `
                -Confirm:$false

            if ($result -and $result.Success) {
                Invoke-FtdiEepromReplugPrompt -TargetDev $targetDev -TargetIndex $targetIndex
            }
            return $result
        }

        # --- FT232R path ---
        if ($targetDev.Type -match '^FT232R(L|NL)?$') {
            # Map -DisableVcp/-EnableVcp to RIsD2XX
            $rIsD2XX = $null
            if ($DisableVcp) { $rIsD2XX = $true }
            if ($EnableVcp)  { $rIsD2XX = $false }

            # Translate CbusPins hashtable to Pins array + Mode string for FT232R backend
            # FT232R only supports a single mode applied to all requested pins
            $pins = @(0, 1, 2, 3)
            $mode = 'FT_CBUS_IOMODE'

            if ($CbusPins -and $CbusPins.Count -gt 0) {
                $pins = @($CbusPins.Keys | ForEach-Object { [int]$_ })
                # Use the mode from the first entry (all must be the same for FT232R backend)
                $firstMode = ($CbusPins.GetEnumerator() | Select-Object -First 1).Value
                if ($firstMode) { $mode = $firstMode }
                # Check all values are the same mode; warn if mixed
                $uniqueModes = ($CbusPins.Values | Sort-Object -Unique)
                if ($uniqueModes.Count -gt 1) {
                    Write-Warning (
                        "FT232R EEPROM write: multiple different modes in -CbusPins. " +
                        "FT232R supports one mode call per write; each mode will be applied in a separate write."
                    )
                    # Write each mode group separately
                    $modeGroups = @{}
                    foreach ($entry in $CbusPins.GetEnumerator()) {
                        $m = $entry.Value
                        if (-not $modeGroups.ContainsKey($m)) { $modeGroups[$m] = @() }
                        $modeGroups[$m] += [int]$entry.Key
                    }
                    foreach ($mg in $modeGroups.GetEnumerator()) {
                        if (-not $PSCmdlet.ShouldProcess(
                            "$($targetDev.Description) ($($targetDev.SerialNumber))",
                            "Write FT232R EEPROM: CBUS$($mg.Value -join ',CBUS') -> $($mg.Key)")) {
                            continue
                        }
                        Set-FtdiFt232rCbusPinMode `
                            -Index $targetIndex `
                            -Pins $mg.Value `
                            -Mode $mg.Key `
                            -SerialNumber $targetDev.SerialNumber `
                            -RIsD2XX $rIsD2XX `
                            -Confirm:$false | Out-Null
                        $rIsD2XX = $null  # only write once
                    }
                    $result = [PSCustomObject]@{ Success = $true; DeviceIndex = $targetIndex; Message = "FT232R EEPROM written (multi-mode). Replug device to activate." }
                    Invoke-FtdiEepromReplugPrompt -TargetDev $targetDev -TargetIndex $targetIndex
                    return $result
                }
            }

            if (-not $PSCmdlet.ShouldProcess(
                "$($targetDev.Description) ($($targetDev.SerialNumber))",
                "Write FT232R EEPROM: CBUS$($pins -join ',CBUS') -> $mode$(if ($null -ne $rIsD2XX) { ' RIsD2XX=' + $rIsD2XX })")) {
                return $null
            }

            $result = Set-FtdiFt232rCbusPinMode `
                -Index $targetIndex `
                -Pins $pins `
                -Mode $mode `
                -SerialNumber $targetDev.SerialNumber `
                -RIsD2XX $rIsD2XX `
                -Confirm:$false

            if ($result -and $result.Success) {
                Invoke-FtdiEepromReplugPrompt -TargetDev $targetDev -TargetIndex $targetIndex
            }
            return $result
        }

        # Unsupported type
        Write-Warning "Set-PsGadgetFtdiEeprom: EEPROM write for '$($targetDev.Type)' is not yet supported. Supported: FT232H, FT232R / FT232RL / FT232RNL."
        return $null

    } catch {
        Write-Error "Set-PsGadgetFtdiEeprom failed: $_"
        return $null
    }
}

function Invoke-FtdiEepromReplugPrompt {
    <#
    .SYNOPSIS
    Internal helper: prompt to cycle USB port after EEPROM write.
    #>
    param(
        [Parameter(Mandatory)]$TargetDev,
        [Parameter(Mandatory)][int]$TargetIndex
    )

    Write-Host ""
    Write-Host "EEPROM written successfully."
    Write-Host "Changes will not take effect until the device re-enumerates on the USB bus."
    Write-Host ""
    Write-Host "  [Y] Cycle USB port automatically (no cable unplug needed)"
    Write-Host "  [N] Unplug and replug the USB cable manually"
    Write-Host ""

    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Cycle port now.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&No',  'I will replug manually.')
    )
    $choice = $Host.UI.PromptForChoice('Apply EEPROM Changes', 'Cycle USB port now?', $choices, 0)

    if ($choice -eq 0) {
        Write-Host "Cycling USB port on $($TargetDev.Description) ($($TargetDev.SerialNumber))..."
        try {
            $cycleDevice = [PsGadgetFtdi]::new([int]$TargetIndex)
            $cycleDevice.Connect()
            $cycleDevice.CyclePort()
            Write-Host "Port cycled. Device has re-enumerated with the new EEPROM settings."
            Write-Host "Verify with: Get-PsGadgetFtdiEeprom -Index $TargetIndex"
        } catch {
            Write-Warning "CyclePort failed: $_"
            Write-Warning "Please unplug and replug the USB cable manually."
        }
    } else {
        Write-Host ""
        Write-Host "ACTION REQUIRED: Unplug and replug the USB cable to apply the new settings."
        Write-Host "Verify with: Get-PsGadgetFtdiEeprom -Index $TargetIndex"
        Write-Host ""
    }
}
