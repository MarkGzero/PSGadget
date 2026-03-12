# Set-PsGadgetFtdiMode.ps1
# Unified device mode selection for FT232H, FT232R, and compatible FTDI chips.

#Requires -Version 5.1

function Set-PsGadgetFtdiMode {
    <#
    .SYNOPSIS
    Sets the operating mode of an FTDI device.

    .DESCRIPTION
    Provides a single command to switch an FTDI device between its supported
    operating modes. Dispatches to the correct backend automatically based on
    the device type stored in the PsGadgetFtdi object.

    Mode summary:

        MPSSE          Multi-Protocol Synchronous Serial Engine - required for SPI,
                       I2C, JTAG, and ACBUS GPIO on FT232H / FT2232H / FT4232H.
                       This is set automatically when Connect-PsGadgetFtdi opens an
                       MPSSE-capable device, so you only need this when switching
                       back from another mode.

        CBUS           CBUS bit-bang GPIO for FT232R / FT232RL / FT232RNL.
                       Writes the device EEPROM (one-time setup) so CBUS0-3 can be
                       driven HIGH/LOW at runtime via Set-PsGadgetGpio.
                       The USB device must be replugged after this operation.
                       Internally delegates to Set-PsGadgetFt232rCbusMode.

        AsyncBitBang   Asynchronous bit-bang on ADBUS0-7 (the UART data lines).
                       Supported on FT232R, FT232H, and most FTDI chips.
                       No EEPROM change required.

        SyncBitBang    Synchronous bit-bang on ADBUS0-7.
                       Supported on FT2232C, FT232R, FT245R.

        UART           Resets the device to its default UART / serial mode.

    .PARAMETER PsGadget
    A PsGadgetFtdi object (from New-PsGadgetFtdi or Connect-PsGadgetFtdi).

    .PARAMETER Mode
    Target operating mode. Tab-completable.

    .PARAMETER Mask
    Output direction mask byte for bit-bang modes (AsyncBitBang, SyncBitBang).
    Each bit corresponds to one ADBUS pin: 1 = output, 0 = input.
    Defaults to 0xFF (all outputs). Ignored for MPSSE, CBUS, and UART modes.

    .PARAMETER Pins
    CBUS pin numbers to configure in EEPROM when Mode is CBUS (FT232R only).
    Defaults to @(0,1,2,3). Ignored for all other modes.

    .EXAMPLE
    # FT232H - switch to MPSSE for SPI/I2C/GPIO
    $dev = New-PsGadgetFtdi -Index 0
    Set-PsGadgetFtdiMode -PsGadget $dev -Mode MPSSE

    .EXAMPLE
    # FT232R - one-time EEPROM setup to enable CBUS GPIO
    $r1 = New-PsGadgetFtdi -Index 1
    Set-PsGadgetFtdiMode -PsGadget $r1 -Mode CBUS
    # Replug USB, then use Set-PsGadgetGpio normally.

    .EXAMPLE
    # FT232R - async bit-bang on ADBUS (UART data pins), no EEPROM needed
    $r1 = New-PsGadgetFtdi -Index 1   # connected immediately
    Set-PsGadgetFtdiMode -PsGadget $r1 -Mode AsyncBitBang

    .EXAMPLE
    # Return any device to normal UART/serial mode
    Set-PsGadgetFtdiMode -PsGadget $dev -Mode UART

    .NOTES
    CBUS mode on FT232R writes to EEPROM and requires a USB replug to take effect.
    All other modes take effect immediately on the open connection.
    The connection is opened automatically if not already open (except CBUS, which
    must be called before Connect for first-time EEPROM setup).
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [PsGadgetFtdi]$PsGadget,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateSet('MPSSE', 'MpsseI2c', 'CBUS', 'AsyncBitBang', 'SyncBitBang', 'UART')]
        [string]$Mode,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 255)]
        [int]$Mask = 0xFF,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 4)]
        [int[]]$Pins = @(0, 1, 2, 3)
    )

    # Map friendly mode name to D2XX SetBitMode byte
    $modeTable = @{
        'UART'         = 0x00
        'AsyncBitBang' = 0x01
        'MPSSE'        = 0x02
        'MpsseI2c'     = 0x02   # MPSSE mode byte; I2C init follows SetBitMode
        'SyncBitBang'  = 0x04
        'CBUS'         = 0x20
    }

    $log = $PsGadget.Logger

    try {
        $log.WriteInfo("Set-PsGadgetFtdiMode: $($PsGadget.Description) ($($PsGadget.SerialNumber)) -> $Mode")

        # CBUS on FT232R: EEPROM path - delegate to Set-PsGadgetFt232rCbusMode
        if ($Mode -eq 'CBUS') {
            if ($PsGadget.Type -and $PsGadget.Type -notmatch '^FT232R(L|NL)?$') {
                $msg = "Mode 'CBUS' is only valid for FT232R devices. This device is '$($PsGadget.Type)'. Use 'AsyncBitBang' or 'MPSSE' instead."
                $log.WriteError($msg)
                throw $msg
            }

            $log.WriteDebug("CBUS EEPROM path: Pins=@($($Pins -join ','))")

            if (-not $PSCmdlet.ShouldProcess(
                "$($PsGadget.Description) ($($PsGadget.SerialNumber))",
                "Write EEPROM: set CBUS$($Pins -join ', CBUS') to FT_CBUS_IOMODE")) {
                $log.WriteTrace("ShouldProcess returned false - EEPROM write skipped")
                return $null
            }

            $result = Set-PsGadgetFt232rCbusMode -PsGadget $PsGadget -Pins $Pins
            if ($result -and $result.Success) {
                $log.WriteInfo("CBUS EEPROM write succeeded. USB replug required.")
            } else {
                $log.WriteError("CBUS EEPROM write returned no success result")
            }
            return $result
        }

        # Runtime mode: device must be open
        if (-not $PsGadget.IsOpen) {
            $log.WriteTrace("Device not open - auto-connecting before SetBitMode")
            $PsGadget.Connect()
        }

        $conn = $PsGadget._connection
        if (-not $conn -or -not $conn.Device) {
            $msg = "No active connection object on PsGadgetFtdi. Call Connect() first."
            $log.WriteError($msg)
            throw $msg
        }

        $modeByte = $modeTable[$Mode]

        # MPSSE and UART ignore the mask (direction managed by MPSSE engine / reset)
        $effectiveMask = if ($Mode -eq 'MPSSE' -or $Mode -eq 'MpsseI2c' -or $Mode -eq 'UART') { 0x00 } else { [byte]$Mask }

        $log.WriteDebug("SetBitMode: mode=$Mode (0x$($modeByte.ToString('X2'))) mask=0x$($effectiveMask.ToString('X2'))")

        if (-not $PSCmdlet.ShouldProcess(
            "$($PsGadget.Description) ($($PsGadget.SerialNumber))",
            "SetBitMode mask=0x$($effectiveMask.ToString('X2')) mode=0x$($modeByte.ToString('X2')) ($Mode)")) {
            $log.WriteTrace("ShouldProcess returned false - SetBitMode skipped")
            return $null
        }

        try {
            $status = $conn.Device.SetBitMode([byte]$effectiveMask, [byte]$modeByte)
            $ftdi_ok = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK
            if ($status -ne $ftdi_ok) {
                throw "D2XX SetBitMode returned: $status"
            }
            # Update connection record so callers can see the active mode
            if ($conn.PSObject.Properties['ActiveMode']) {
                $conn.ActiveMode = $Mode
            } else {
                $conn | Add-Member -MemberType NoteProperty -Name ActiveMode -Value $Mode -Force
            }
            # Save original GpioMethod on first mode switch so UART can restore it
            if (-not $conn.PSObject.Properties['OriginalGpioMethod']) {
                $conn | Add-Member -MemberType NoteProperty -Name OriginalGpioMethod -Value $conn.GpioMethod -Force
            }
            # Sync GpioMethod so Set-PsGadgetGpio dispatches to the correct handler
            switch ($Mode) {
                'AsyncBitBang' { $conn.GpioMethod = 'AsyncBitBang' }
                'SyncBitBang'  { $conn.GpioMethod = 'SyncBitBang'  }
                'MPSSE'        { $conn.GpioMethod = 'MPSSE' }
                'MpsseI2c'     { $conn.GpioMethod = 'MpsseI2c' }
                'UART'         {
                    if ($conn.PSObject.Properties['OriginalGpioMethod']) {
                        $conn.GpioMethod = $conn.OriginalGpioMethod
                    }
                }
            }
            # For MpsseI2c: run I2C idle-state and clock setup on top of base MPSSE
            if ($Mode -eq 'MpsseI2c') {
                Initialize-MpsseI2C -DeviceHandle $conn | Out-Null
            }
            $log.WriteInfo("SetBitMode OK: $($PsGadget.SerialNumber) is now in $Mode mode (GpioMethod=$($conn.GpioMethod))")
            return [PSCustomObject]@{
                Success    = $true
                Mode       = $Mode
                ModeByte   = "0x$($modeByte.ToString('X2'))"
                MaskByte   = "0x$($effectiveMask.ToString('X2'))"
                Device     = "$($PsGadget.Description) ($($PsGadget.SerialNumber))"
            }
        } catch [System.Management.Automation.RuntimeException] {
            # FTD2XX type not loaded (stub/Unix environment)
            $log.WriteTrace("FTDI assembly not loaded - stub mode, SetBitMode not executed")
            return [PSCustomObject]@{
                Success    = $false
                Mode       = $Mode
                ModeByte   = "0x$($modeByte.ToString('X2'))"
                MaskByte   = "0x$($effectiveMask.ToString('X2'))"
                Device     = "$($PsGadget.Description) ($($PsGadget.SerialNumber))"
                Note       = 'STUB - no hardware'
            }
        }

    } catch {
        $log.WriteError("Set-PsGadgetFtdiMode failed: $_")
        Write-Error "Set-PsGadgetFtdiMode failed: $_"
        return $null
    }
}
