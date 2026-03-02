# Ftdi.Cbus.ps1
# CBUS bit-bang GPIO and EEPROM configuration helpers for FT232R / FT231X / FT230X devices.
#
# How FT232R CBUS GPIO works (two-step process):
#   Step 1 (one-time): Program EEPROM so the desired CBUS pins are set to FT_CBUS_IOMODE.
#                      Use Set-FtdiFt232rCbusPinMode (or the public Set-PsGadgetFt232rCbusMode).
#                      Reconnect USB after writing EEPROM for the change to take effect.
#   Step 2 (runtime):  Call SetBitMode(mask, 0x20) to drive those pins HIGH/LOW.
#                      Use Set-FtdiCbusBits (called by Set-PsGadgetGpio for CBUS devices).
#
# CBUS bit-bang mask byte layout (FTDI D2XX Programmer's Guide, section 5.3):
#   Bit 7 = CBUS3 direction  (1=output, 0=input)
#   Bit 6 = CBUS2 direction
#   Bit 5 = CBUS1 direction
#   Bit 4 = CBUS0 direction
#   Bit 3 = CBUS3 output value
#   Bit 2 = CBUS2 output value
#   Bit 1 = CBUS1 output value
#   Bit 0 = CBUS0 output value
#   mask = (direction_nibble << 4) | value_nibble
#
# Notes:
#   - Only CBUS0-CBUS3 are available for bit-bang (not CBUS4).
#   - Only pins programmed as FT_CBUS_IOMODE in EEPROM can be driven; others are ignored.
#   - SetBitMode for CBUS (0x20) sets direction AND value in a single call.

#Requires -Version 5.1

# FT_CBUS_OPTIONS integer-to-name and name-to-integer lookup tables.
# Values match the FTD2XX_NET FT_CBUS_OPTIONS enum (net48 and netstandard20).
# Reference: FTD2XX_NET source + confirmed by ReadFT232REEPROM on FT232R with
# CBUS0/1 programmed to I/O MODE via FT_Prog (returns byte 10 = FT_CBUS_IOMODE).
$script:FT_CBUS_NAMES = @{
    0  = 'FT_CBUS_TXDEN'
    1  = 'FT_CBUS_PWREN'
    2  = 'FT_CBUS_RXLED'
    3  = 'FT_CBUS_TXLED'
    4  = 'FT_CBUS_TXRXLED'
    5  = 'FT_CBUS_SLEEP'
    6  = 'FT_CBUS_CLK48'
    7  = 'FT_CBUS_CLK24'
    8  = 'FT_CBUS_CLK12'
    9  = 'FT_CBUS_CLK6'
    10 = 'FT_CBUS_IOMODE'
    11 = 'FT_CBUS_BITBANG_WR'
    12 = 'FT_CBUS_BITBANG_RD'
}
$script:FT_CBUS_VALUES = @{}
foreach ($k in $script:FT_CBUS_NAMES.Keys) {
    $script:FT_CBUS_VALUES[$script:FT_CBUS_NAMES[$k]] = [byte]$k
}

function Get-FtdiFt232rEeprom {
    <#
    .SYNOPSIS
    Reads the FT232R EEPROM and returns a rich object with all fields.

    .DESCRIPTION
    Opens the FT232R device by index via D2XX, reads the FT232R_EEPROM_STRUCTURE,
    and returns a PSCustomObject with common USB descriptor fields plus all FT232R-
    specific fields (CBUS pin modes, signal inversion, driver load mode, etc.).

    The device must not already be opened by another handle.

    .PARAMETER Index
    Zero-based device index (from List-PsGadgetFtdi).

    .EXAMPLE
    Get-FtdiFt232rEeprom -Index 0

    .OUTPUTS
    PSCustomObject with EEPROM fields. CbusN properties hold the FT_CBUS_OPTIONS
    enum value name (e.g. 'FT_CBUS_IOMODE', 'FT_CBUS_TXLED', etc.).
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index,

        # Optional serial number used as fallback when OpenByIndex fails (e.g. device in VCP mode)
        [Parameter(Mandatory = $false)]
        [string]$SerialNumber = ''
    )

    try {
        if (-not $script:FtdiInitialized) {
            throw [System.NotImplementedException]::new("FTDI assembly not loaded")
        }

        $ftdi   = [FTD2XX_NET.FTDI]::new()
        $status = $ftdi.OpenByIndex([uint32]$Index)

        # VCP-mode devices (shown as COM ports) cause OpenByIndex to return FT_DEVICE_NOT_FOUND.
        # Fall back to OpenBySerialNumber which works regardless of driver mode.
        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK -and $SerialNumber -ne '') {
            Write-Verbose "OpenByIndex($Index) -> $status; retrying via OpenBySerialNumber('$SerialNumber')"
            $ftdi.Close() | Out-Null
            $ftdi   = [FTD2XX_NET.FTDI]::new()
            $status = $ftdi.OpenBySerialNumber($SerialNumber)
        }

        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            $ftdi.Close() | Out-Null
            $openMethod = if ($SerialNumber -ne '') { "OpenByIndex($Index) and OpenBySerialNumber('$SerialNumber')" } else { "OpenByIndex($Index)" }
            # FT_DEVICE_NOT_OPENED (3) when trying to open usually means another handle is already open.
            # The D2XX library will not allow a second handle on the same device.
            if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_DEVICE_NOT_OPENED) {
                throw ("Device is already open - close the existing connection first. " +
                       "If you have a `$dev or `$conn variable, call .Close() on it. " +
                       "Otherwise restart the PowerShell session to release all handles.")
            }
            throw "Failed to open device via $openMethod : $status"
        }

        $eeprom = [FTD2XX_NET.FTDI+FT232R_EEPROM_STRUCTURE]::new()
        $status = $ftdi.ReadFT232REEPROM($eeprom)
        $ftdi.Close() | Out-Null

        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            throw "ReadFT232REEPROM failed: $status"
        }

        return [PSCustomObject]@{
            # USB descriptor fields (FT_EEPROM_DATA base)
            VendorID        = '0x{0:X4}' -f $eeprom.VendorID
            ProductID       = '0x{0:X4}' -f $eeprom.ProductID
            Manufacturer    = $eeprom.Manufacturer
            ManufacturerID  = $eeprom.ManufacturerID
            Description     = $eeprom.Description
            SerialNumber    = $eeprom.SerialNumber
            MaxPower        = $eeprom.MaxPower
            SelfPowered     = $eeprom.SelfPowered
            RemoteWakeup    = $eeprom.RemoteWakeup
            # FT232R-specific fields
            UseExtOsc       = $eeprom.UseExtOsc
            HighDriveIOs    = $eeprom.HighDriveIOs
            EndpointSize    = $eeprom.EndpointSize
            PullDownEnable  = $eeprom.PullDownEnable
            SerNumEnable    = $eeprom.SerNumEnable
            InvertTXD       = $eeprom.InvertTXD
            InvertRXD       = $eeprom.InvertRXD
            InvertRTS       = $eeprom.InvertRTS
            InvertCTS       = $eeprom.InvertCTS
            InvertDTR       = $eeprom.InvertDTR
            InvertDSR       = $eeprom.InvertDSR
            InvertDCD       = $eeprom.InvertDCD
            InvertRI        = $eeprom.InvertRI
            # CBUS pin mode assignments - use lookup table; Cbus0-4 may be plain bytes
            # in some FTD2XX_NET builds, making enum reflection unreliable.
            Cbus0           = if ($script:FT_CBUS_NAMES.ContainsKey([int]$eeprom.Cbus0)) { $script:FT_CBUS_NAMES[[int]$eeprom.Cbus0] } else { "UNKNOWN($($eeprom.Cbus0))" }
            Cbus1           = if ($script:FT_CBUS_NAMES.ContainsKey([int]$eeprom.Cbus1)) { $script:FT_CBUS_NAMES[[int]$eeprom.Cbus1] } else { "UNKNOWN($($eeprom.Cbus1))" }
            Cbus2           = if ($script:FT_CBUS_NAMES.ContainsKey([int]$eeprom.Cbus2)) { $script:FT_CBUS_NAMES[[int]$eeprom.Cbus2] } else { "UNKNOWN($($eeprom.Cbus2))" }
            Cbus3           = if ($script:FT_CBUS_NAMES.ContainsKey([int]$eeprom.Cbus3)) { $script:FT_CBUS_NAMES[[int]$eeprom.Cbus3] } else { "UNKNOWN($($eeprom.Cbus3))" }
            Cbus4           = if ($script:FT_CBUS_NAMES.ContainsKey([int]$eeprom.Cbus4)) { $script:FT_CBUS_NAMES[[int]$eeprom.Cbus4] } else { "UNKNOWN($($eeprom.Cbus4))" }
            # Flag: driver mode (true = D2XX, false = VCP)
            RIsD2XX         = $eeprom.RIsD2XX
        }

    } catch [System.NotImplementedException] {
        $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
        if ($isWindows) {
            Write-Verbose "EEPROM read: FTD2XX_NET assembly not loaded - returning stub EEPROM data"
        } else {
            Write-Warning (
                "Get-PsGadgetFtdiEeprom is not supported on Linux.`n" +
                "FTD2XX_NET.dll uses kernel32.dll P/Invoke (Windows-only) and cannot be loaded on Linux.`n" +
                "EEPROM read (and CBUS pin mode programming) require a Windows machine or VM."
            )
            return $null
        }
        return [PSCustomObject]@{
            VendorID       = '0x0403'
            ProductID      = '0x6001'
            Manufacturer   = 'FTDI'
            ManufacturerID = 'FT'
            Description    = 'FT232R USB UART (STUB)'
            SerialNumber   = "STUB$Index"
            MaxPower       = 90
            SelfPowered    = $false
            RemoteWakeup   = $false
            UseExtOsc      = $false
            HighDriveIOs   = $false
            EndpointSize   = 64
            PullDownEnable = $false
            SerNumEnable   = $true
            InvertTXD      = $false
            InvertRXD      = $false
            InvertRTS      = $false
            InvertCTS      = $false
            InvertDTR      = $false
            InvertDSR      = $false
            InvertDCD      = $false
            InvertRI       = $false
            Cbus0          = 'FT_CBUS_TXLED'
            Cbus1          = 'FT_CBUS_RXLED'
            Cbus2          = 'FT_CBUS_TXDEN'
            Cbus3          = 'FT_CBUS_PWREN'
            Cbus4          = 'FT_CBUS_SLEEP'
            RIsD2XX        = $false
        }
    } catch {
        Write-Error "Get-FtdiFt232rEeprom failed: $_"
        return $null
    }
}

function Set-FtdiFt232rCbusPinMode {
    <#
    .SYNOPSIS
    Programs FT232R EEPROM to set specified CBUS pins to a given functional mode.

    .DESCRIPTION
    Reads the current FT232R EEPROM, sets the Cbus0-Cbus3 entries for the specified
    pin numbers to the chosen FT_CBUS_OPTIONS mode (default: FT_CBUS_IOMODE which
    enables bit-bang GPIO control), then writes the modified EEPROM back.

    IMPORTANT: The EEPROM change takes effect only after the USB device is
    disconnected and reconnected (power cycle or USB replug).

    Available mode names (FT_CBUS_OPTIONS enum):
        FT_CBUS_IOMODE       - GPIO bit-bang (needed for Set-PsGadgetGpio / CBUS control)
        FT_CBUS_TXLED        - Tx LED (pulses on transmit)
        FT_CBUS_RXLED        - Rx LED (pulses on receive)
        FT_CBUS_TXRXLED      - Tx/Rx LED
        FT_CBUS_PWREN        - Power-on signal (PWREN#, active low)
        FT_CBUS_SLEEP        - Sleep indicator
        FT_CBUS_CLK48        - 48 MHz clock output
        FT_CBUS_CLK24        - 24 MHz clock output
        FT_CBUS_CLK12        - 12 MHz clock output
        FT_CBUS_CLK6         - 6 MHz clock output
        FT_CBUS_TXDEN        - Tx Data Enable
        FT_CBUS_BITBANG_WR   - Bit-bang write strobe
        FT_CBUS_BITBANG_RD   - Bit-bang read strobe

    .PARAMETER Index
    Zero-based device index (from List-PsGadgetFtdi).

    .PARAMETER Pins
    One or more CBUS pin numbers to reconfigure (0-3). CBUS4 is not available for
    bit-bang and is not accepted.

    .PARAMETER Mode
    Name of the FT_CBUS_OPTIONS enum value to assign. Defaults to FT_CBUS_IOMODE.

    .EXAMPLE
    # Configure CBUS0-3 as GPIO on device 0 (one-time setup):
    Set-FtdiFt232rCbusPinMode -Index 0 -Pins @(0,1,2,3)

    .EXAMPLE
    # Set CBUS0 to Rx LED, keep others unchanged:
    Set-FtdiFt232rCbusPinMode -Index 0 -Pins @(0) -Mode FT_CBUS_RXLED
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 4)]
        [int[]]$Pins,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
            'FT_CBUS_TXDEN','FT_CBUS_PWREN','FT_CBUS_RXLED','FT_CBUS_TXLED',
            'FT_CBUS_TXRXLED','FT_CBUS_SLEEP','FT_CBUS_CLK48','FT_CBUS_CLK24',
            'FT_CBUS_CLK12','FT_CBUS_CLK6','FT_CBUS_IOMODE',
            'FT_CBUS_BITBANG_WR','FT_CBUS_BITBANG_RD'
        )]
        [string]$Mode = 'FT_CBUS_IOMODE',

        # Optional serial number used as fallback when OpenByIndex fails (e.g. device in VCP mode)
        [Parameter(Mandatory = $false)]
        [string]$SerialNumber = '',

        # Additional EEPROM fields to write alongside the CBUS pin modes.
        # Pass $null (default) to leave the existing EEPROM value unchanged.
        [Parameter(Mandatory = $false)]
        [System.Nullable[bool]]$HighDriveIOs = $null,

        [Parameter(Mandatory = $false)]
        [System.Nullable[bool]]$PullDownEnable = $null,

        [Parameter(Mandatory = $false)]
        [System.Nullable[bool]]$RIsD2XX = $null
    )

    try {
        if (-not $script:FtdiInitialized) {
            throw [System.NotImplementedException]::new("FTDI assembly not loaded")
        }

        $ftdi   = [FTD2XX_NET.FTDI]::new()
        $status = $ftdi.OpenByIndex([uint32]$Index)

        # VCP-mode devices (shown as COM ports) cause OpenByIndex to return FT_DEVICE_NOT_FOUND.
        # Fall back to OpenBySerialNumber which works regardless of driver mode.
        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK -and $SerialNumber -ne '') {
            Write-Verbose "OpenByIndex($Index) -> $status; retrying via OpenBySerialNumber('$SerialNumber')"
            $ftdi.Close() | Out-Null
            $ftdi   = [FTD2XX_NET.FTDI]::new()
            $status = $ftdi.OpenBySerialNumber($SerialNumber)
        }

        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            $ftdi.Close() | Out-Null
            $openMethod = if ($SerialNumber -ne '') { "OpenByIndex($Index) and OpenBySerialNumber('$SerialNumber')" } else { "OpenByIndex($Index)" }
            # FT_DEVICE_NOT_OPENED (3) when trying to open usually means another handle is already open.
            if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_DEVICE_NOT_OPENED) {
                throw ("Device is already open - close the existing connection first. " +
                       "If you have a `$dev or `$conn variable, call .Close() on it. " +
                       "Otherwise restart the PowerShell session to release all handles.")
            }
            throw "Failed to open device via $openMethod : $status"
        }

        # Read current EEPROM - preserve all fields, only modify requested CBUS pins
        $eeprom = [FTD2XX_NET.FTDI+FT232R_EEPROM_STRUCTURE]::new()
        $status = $ftdi.ReadFT232REEPROM($eeprom)
        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            $ftdi.Close() | Out-Null
            throw "ReadFT232REEPROM failed: $status"
        }

        # Resolve FT_CBUS_OPTIONS value by name using lookup table.
        # Cbus0-4 may be plain bytes in some FTD2XX_NET builds; avoid enum reflection.
        if (-not $script:FT_CBUS_VALUES.ContainsKey($Mode)) {
            $ftdi.Close() | Out-Null
            throw "Unknown CBUS mode '$Mode'. Valid values: $($script:FT_CBUS_VALUES.Keys -join ', ')"
        }
        $targetMode = $script:FT_CBUS_VALUES[$Mode]

        $pinNames = $Pins | ForEach-Object { "CBUS$_" }
        $action   = "Set $($pinNames -join ', ') to $Mode on device index $Index"

        if (-not $PSCmdlet.ShouldProcess("FT232R EEPROM (device $Index)", $action)) {
            $ftdi.Close() | Out-Null
            return
        }

        foreach ($pin in $Pins) {
            switch ($pin) {
                0 { $eeprom.Cbus0 = $targetMode }
                1 { $eeprom.Cbus1 = $targetMode }
                2 { $eeprom.Cbus2 = $targetMode }
                3 { $eeprom.Cbus3 = $targetMode }
                4 { $eeprom.Cbus4 = $targetMode }  # EEPROM-configurable; not runtime bit-bangable
            }
        }

        # Apply additional EEPROM fields sourced from config (or explicit param overrides)
        if ($null -ne $HighDriveIOs)   { $eeprom.HighDriveIOs   = [bool]$HighDriveIOs }
        if ($null -ne $PullDownEnable)  { $eeprom.PullDownEnable  = [bool]$PullDownEnable }
        if ($null -ne $RIsD2XX)         { $eeprom.RIsD2XX         = [bool]$RIsD2XX }

        $status = $ftdi.WriteFT232REEPROM($eeprom)
        $ftdi.Close() | Out-Null

        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            throw "WriteFT232REEPROM failed: $status"
        }

        Write-Verbose "EEPROM updated: $action"
        Write-Warning "EEPROM written. Disconnect and reconnect the USB device for the changes to take effect."

        return [PSCustomObject]@{
            Success        = $true
            DeviceIndex    = $Index
            PinsChanged    = $Pins
            NewMode        = $Mode
            HighDriveIOs   = $eeprom.HighDriveIOs
            PullDownEnable = $eeprom.PullDownEnable
            RIsD2XX        = $eeprom.RIsD2XX
            Message        = "EEPROM written. Replug device to activate."
        }

    } catch [System.NotImplementedException] {
        $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
        if (-not $isWindows) {
            Write-Warning (
                "Set-PsGadgetFt232rCbusMode is not supported on Linux.`n" +
                "FTD2XX_NET.dll uses kernel32.dll P/Invoke (Windows-only) and cannot be loaded on Linux.`n" +
                "EEPROM programming requires a Windows machine or VM."
            )
            return [PSCustomObject]@{ Success = $false; Error = "Not supported on Linux" }
        }
        Write-Verbose "Set-FtdiFt232rCbusPinMode: FTDI assembly not loaded - stub mode (no EEPROM written)"
        return [PSCustomObject]@{
            Success        = $true
            DeviceIndex    = $Index
            PinsChanged    = $Pins
            NewMode        = $Mode
            HighDriveIOs   = if ($null -ne $HighDriveIOs)   { [bool]$HighDriveIOs }   else { $false }
            PullDownEnable = if ($null -ne $PullDownEnable)  { [bool]$PullDownEnable }  else { $false }
            RIsD2XX        = if ($null -ne $RIsD2XX)         { [bool]$RIsD2XX }         else { $false }
            Message        = "STUB: EEPROM write simulated (assembly not loaded)"
        }
    } catch {
        Write-Error "Set-FtdiFt232rCbusPinMode failed: $_"
        return [PSCustomObject]@{
            Success  = $false
            Error    = $_.Exception.Message
        }
    }
}

function Set-FtdiCbusBits {
    <#
    .SYNOPSIS
    Drives FT232R CBUS pins via CBUS bit-bang mode (SetBitMode 0x20).

    .DESCRIPTION
    Calls SetBitMode on an already-open D2XX connection with mode 0x20 (CBUS bit-bang).
    The mask byte encodes both direction and value:
        Bits 7-4: direction for CBUS3-CBUS0 (1=output)
        Bits 3-0: output value for CBUS3-CBUS0

    Prerequisites:
      - The target CBUS pins must be programmed as FT_CBUS_IOMODE in the device EEPROM.
        If they are not, run Set-FtdiFt232rCbusPinMode (public: Set-PsGadgetFt232rCbusMode)
        once, replug the device, then retry.
      - The connection must be open (from Connect-PsGadgetFtdi or Invoke-FtdiWindowsOpen).

    .PARAMETER Connection
    Open FTDI connection object (returned by Connect-PsGadgetFtdi / Invoke-FtdiWindowsOpen).

    .PARAMETER Pins
    One or more CBUS pin numbers to control (0-3).

    .PARAMETER State
    Target state for the specified pins: HIGH/H/1 or LOW/L/0.

    .PARAMETER OutputPins
    Which CBUS pins (0-3) to configure as outputs in this call.
    Defaults to the same set as Pins. Pins not listed are configured as inputs.

    .PARAMETER DurationMs
    If specified, hold the state for this many milliseconds then invert the pins.

    .EXAMPLE
    Set-FtdiCbusBits -Connection $conn -Pins @(0,1) -State HIGH
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$Connection,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 3)]
        [int[]]$Pins,

        [Parameter(Mandatory = $true)]
        [ValidateSet('HIGH', 'LOW', 'H', 'L', '1', '0')]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3)]
        [int[]]$OutputPins,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60000)]
        [int]$DurationMs
    )

    try {
        if (-not $Connection -or -not $Connection.IsOpen) {
            throw "Connection is not open"
        }

        $isHigh = $State -in @('HIGH', 'H', '1')

        # Build output pin set - default to the same pins being driven
        $outputSet = if ($OutputPins) { $OutputPins } else { $Pins }

        # Build direction nibble (bits 3-0 of the upper nibble in the mask)
        $dirNibble = 0
        foreach ($p in $outputSet) {
            $dirNibble = $dirNibble -bor (1 -shl $p)
        }

        # Build value nibble
        $valNibble = 0
        if ($isHigh) {
            foreach ($p in $Pins) {
                $valNibble = $valNibble -bor (1 -shl $p)
            }
        }

        # Combined mask: upper nibble = direction, lower nibble = value
        [byte]$mask = (($dirNibble -band 0x0F) -shl 4) -bor ($valNibble -band 0x0F)

        Write-Verbose ("CBUS bit-bang: pins=[{0}] state={1} dir=0x{2:X1} val=0x{3:X1} mask=0x{4:X2}" -f
            ($Pins -join ','), $State, $dirNibble, $valNibble, $mask)

        if ($script:FtdiInitialized -and $null -ne $Connection.Device) {
            $status = $Connection.Device.SetBitMode($mask, 0x20)

            if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
                # Provide targeted help if CBUS pins are not configured
                if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OTHER_ERROR) {
                    Write-Warning (
                        "CBUS bit-bang failed. Ensure CBUS pins are programmed as FT_CBUS_IOMODE " +
                        "in the device EEPROM. Run: Set-PsGadgetFt232rCbusMode -Index <n> " +
                        "-Pins @($($Pins -join ',')) then replug the device."
                    )
                }
                throw "SetBitMode(CBUS bit-bang) failed: $status"
            }

            if ($DurationMs) {
                Start-Sleep -Milliseconds $DurationMs

                # Invert value nibble to pulse
                [byte]$invertMask = (($dirNibble -band 0x0F) -shl 4) -bor ((-bnot $valNibble) -band $dirNibble -band 0x0F)
                $Connection.Device.SetBitMode($invertMask, 0x20) | Out-Null
            }
        } else {
            Write-Verbose ("CBUS bit-bang (STUB): mask=0x{0:X2}" -f $mask)

            if ($DurationMs) {
                Start-Sleep -Milliseconds $DurationMs
            }
        }

        return $true

    } catch {
        Write-Error "Set-FtdiCbusBits failed: $_"
        return $false
    }
}
