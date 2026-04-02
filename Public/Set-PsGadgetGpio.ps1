#Requires -Version 5.1
# Set-PsGadgetGpio.ps1
# Public GPIO control function for FTDI devices

function Set-PsGadgetGpio {
    <#
    .SYNOPSIS
    Controls GPIO pins on connected FTDI devices.

    .DESCRIPTION
    Sets GPIO pins on FTDI devices to HIGH or LOW states. Supports MPSSE-capable
    devices (FT232H, FT2232H, FT4232H) using ACBUS0-7, and CBUS bit-bang devices
    (FT232R) using CBUS0-3.

    For FT232R CBUS GPIO, the CBUS pins must first be programmed in the device
    EEPROM as FT_CBUS_IOMODE. Run Set-PsGadgetFt232rCbusMode once per device,
    replug the USB device, then use this function normally.

    .PARAMETER Index
    Zero-based index of the FTDI device (from Get-FtdiDevice).

    .PARAMETER SerialNumber
    FTDI device serial number. Preferred over Index -- stable across USB replug.

    .PARAMETER Connection
    An already-open raw connection object from Connect-PsGadgetFtdi or a
    PsGadgetFtdi wrapper from New-PsGadgetFtdi. The caller is responsible for
    closing the connection.

    .PARAMETER PsGadget
    A PsGadgetFtdi instance from New-PsGadgetFtdi. The caller is responsible for
    closing it.

    .PARAMETER Pins
    Pin numbers to drive. Range depends on device type:
      CBUS (FT232R):         0-3  (CBUS0-CBUS3)
      MPSSE (FT232H, etc.):  0-7  (ACBUS0-ACBUS7)
      AsyncBitBang:          0-7  (ADBUS0-ADBUS7)

    .PARAMETER State
    Pin state: HIGH, H, 1 or LOW, L, 0.

    .PARAMETER LowPins
    CBUS only. Pins to drive LOW in the same SetBitMode call as -Pins/-State HIGH.
    Allows atomic mixed-state writes without two round-trips to the device.
    Example: -Pins @(0,2) -State HIGH -LowPins @(1,3)  sets 0,2=HIGH and 1,3=LOW.

    .PARAMETER DurationMs
    Hold the pin state for this many milliseconds, then invert (pulse mode).

    .PARAMETER PassThru
    Return a PSCustomObject describing the operation. By default no output.

    .EXAMPLE
    # FT232R CBUS -- set all four pins HIGH (after EEPROM programming)
    Set-PsGadgetGpio -Index 0 -Pins @(0..3) -State HIGH

    .EXAMPLE
    # FT232R CBUS -- mixed states in one call
    Set-PsGadgetGpio -Index 0 -Pins @(0,2) -State HIGH -LowPins @(1,3)

    .EXAMPLE
    # FT232H MPSSE -- control ACBUS pins
    Set-PsGadgetGpio -Index 0 -Pins @(2,4) -State HIGH

    .EXAMPLE
    # Pulse ACBUS0 LOW for 500ms
    Set-PsGadgetGpio -SerialNumber "ABC123" -Pins @(0) -State LOW -DurationMs 500

    .EXAMPLE
    # Persistent connection -- open once, drive multiple times, close when done
    $conn = Connect-PsGadgetFtdi -SerialNumber "BG01X3AK"
    Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH
    Set-PsGadgetGpio -Connection $conn -Pins @(0) -State LOW
    $conn.Close()

    .EXAMPLE
    # OOP style via New-PsGadgetFtdi
    $dev = New-PsGadgetFtdi -Index 0
    $dev.SetPin(0, "HIGH")
    $dev.SetPin(0, "LOW")
    $dev.Close()

    .NOTES
    Requires FTDI D2XX drivers and FTD2XX_NET.dll.
    FT232R CBUS pins require prior EEPROM programming via Set-PsGadgetFt232rCbusMode.
    FT232H MPSSE: ACBUS0-7 map to physical pins 21, 25-31.
    Use Get-FtdiDevice to list available devices and their serial numbers.
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByIndex', SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIndex', Position = 0)]
        [int]$Index,

        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [string]$SerialNumber,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByConnection', Position = 0)]
        [ValidateNotNull()]
        [object]$Connection,

        [Parameter(Mandatory = $true, ParameterSetName = 'PsGadget', Position = 0)]
        [ValidateNotNull()]
        [PsGadgetFtdi]$PsGadget,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(0, 7)]
        [int[]]$Pins,

        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateSet('HIGH', 'LOW', 'H', 'L', '1', '0')]
        [string]$State,

        [Parameter()]
        [ValidateRange(0, 3)]
        [int[]]$LowPins,

        [Parameter()]
        [ValidateRange(0, 7)]
        [int[]]$InputPins,

        [Parameter()]
        [ValidateRange(1, 60000)]
        [int]$DurationMs,

        [Parameter()]
        [switch]$PassThru
    )

    try {
        # Track whether this function opened the connection (must close it in finally)
        $ownsConnection = $true

        if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            $ownsConnection = $false
            # Unwrap PsGadgetFtdi wrapper if the caller passed one via -Connection
            if ($Connection.GetType().Name -eq 'PsGadgetFtdi') {
                if (-not $Connection._connection) {
                    throw "PsGadgetFtdi internal connection is null. Device may not be connected."
                }
                $Connection = $Connection._connection
            }
            if (-not $Connection.IsOpen) {
                throw "The supplied connection is not open. Call Connect-PsGadgetFtdi or New-PsGadgetFtdi first."
            }
            Write-Debug "Using caller-supplied connection: $($Connection.Description) ($($Connection.SerialNumber))"
        } elseif ($PSCmdlet.ParameterSetName -eq 'PsGadget') {
            $ownsConnection = $false
            if (-not $PsGadget.IsOpen -or -not $PsGadget._connection) {
                throw "PsGadgetFtdi is not open. Use New-PsGadgetFtdi, which connects automatically."
            }
            $Connection = $PsGadget._connection
            Write-Debug "Using PsGadgetFtdi connection: $($Connection.Description) ($($Connection.SerialNumber))"
        } else {
            $devices = Get-FtdiDeviceList
            if (-not $devices -or $devices.Count -eq 0) {
                throw "No FTDI devices found. Run Get-FtdiDevice to check available devices."
            }

            $targetDevice = $null
            if ($PSCmdlet.ParameterSetName -eq 'ByIndex') {
                if ($Index -lt 0 -or $Index -ge $devices.Count) {
                    throw "Device index $Index is out of range. Available devices: 0-$($devices.Count - 1)"
                }
                $targetDevice = $devices[$Index]
            } else {
                $targetDevice = $devices | Where-Object { $_.SerialNumber -eq $SerialNumber }
                if (-not $targetDevice) {
                    throw "No device found with serial number '$SerialNumber'"
                }
            }

            Write-Debug "Targeting device: $($targetDevice.Description) ($($targetDevice.SerialNumber))"

            if ($targetDevice.IsOpen) {
                $deviceRef = if ($targetDevice.SerialNumber) { "'$($targetDevice.SerialNumber)'" } else { "at index $($targetDevice.Index)" }
                throw "Device $deviceRef is already open. Run Get-ConnectedPsGadget to find the open handle and call .Close() on it."
            }

            $Connection = Connect-PsGadgetFtdi -Index $targetDevice.Index
            if (-not $Connection) {
                throw "Failed to connect to FTDI device"
            }
        }

        try {
            $gpioMethod = if ($Connection.PSObject.Properties['GpioMethod']) {
                $Connection.GpioMethod
            } else {
                'Unknown'
            }

            Write-Verbose "Device $($Connection.Type): GpioMethod=$gpioMethod, pins=[$($Pins -join ',')], state=$State"

            if (-not $PSCmdlet.ShouldProcess("$($Connection.Type) pins [$($Pins -join ',')]", "Set $State")) {
                return
            }

            $success = $false

            switch ($gpioMethod) {
                'MPSSE' {
                    $params = @{
                        DeviceHandle = $Connection
                        Pins         = $Pins
                        Direction    = $State
                    }
                    if ($DurationMs)  { $params.DurationMs  = $DurationMs }
                    if ($InputPins)   { $params.InputPins   = $InputPins }
                    $success = Set-FtdiGpioPins @params
                }

                'IoT' {
                    if (-not $Connection.GpioController) {
                        throw "IoT connection is missing GpioController. Re-open the device with Connect-PsGadgetFtdi."
                    }
                    $iotParams = @{
                        GpioController = $Connection.GpioController
                        Pins           = $Pins
                        State          = $State
                    }
                    if ($DurationMs) { $iotParams.DurationMs = $DurationMs }
                    $success = Set-FtdiIotGpioPins @iotParams
                }

                'CBUS' {
                    $badPins = $Pins | Where-Object { $_ -gt 3 }
                    if ($badPins) {
                        throw "Pin(s) [$($badPins -join ', ')] are out of range for CBUS bit-bang. $($Connection.Type) supports CBUS0-3 only."
                    }
                    $cbusParams = @{
                        Connection = $Connection
                        Pins       = $Pins
                        State      = $State
                    }
                    if ($LowPins)   { $cbusParams.LowPins   = $LowPins }
                    if ($DurationMs){ $cbusParams.DurationMs = $DurationMs }
                    $success = Set-FtdiCbusBits @cbusParams
                }

                'AsyncBitBang' {
                    $badPins = $Pins | Where-Object { $_ -lt 0 -or $_ -gt 7 }
                    if ($badPins) {
                        throw "Pin(s) [$($badPins -join ', ')] are out of range for async bit-bang. ADBUS supports pins 0-7."
                    }
                    [int]$outByte = 0
                    foreach ($p in $Pins) {
                        if ($State -in @('HIGH','H','1')) {
                            $outByte = $outByte -bor (1 -shl $p)
                        }
                    }
                    $written = 0
                    $Connection.Write([byte[]]@($outByte), 1, [ref]$written) | Out-Null
                    if ($DurationMs) {
                        Start-Sleep -Milliseconds $DurationMs
                        $Connection.Write([byte[]]@(0), 1, [ref]$written) | Out-Null
                    }
                    $success = $true
                }

                default {
                    Write-Warning "Unknown GpioMethod '$gpioMethod' for device '$($Connection.Type)'. Attempting MPSSE fallback."
                    $params = @{
                        DeviceHandle = $Connection
                        Pins         = $Pins
                        Direction    = $State
                    }
                    if ($DurationMs) { $params.DurationMs = $DurationMs }
                    $success = Set-FtdiGpioPins @params
                }
            }

            if (-not $success) {
                throw "GPIO operation failed"
            }

            foreach ($p in $Pins) {
                Write-Verbose "  pin $p -> $State"
            }

        } finally {
            if ($ownsConnection -and $Connection -and $Connection.Close) {
                try {
                    $Connection.Close()
                } catch {
                    Write-Warning "Failed to close device connection: $_"
                }
            }
        }

        if ($PassThru) {
            $resolvedSerial = ''
            if ($PSBoundParameters.ContainsKey('Connection')) {
                $resolvedSerial = 'via-connection'
            } elseif ($PSBoundParameters.ContainsKey('SerialNumber')) {
                $resolvedSerial = $SerialNumber
            }
            [PSCustomObject]@{
                Index        = if ($PSBoundParameters.ContainsKey('Index')) { $Index } else { -1 }
                SerialNumber = $resolvedSerial
                Pins         = $Pins
                State        = $State
                DurationMs   = if ($PSBoundParameters.ContainsKey('DurationMs')) { $DurationMs } else { 0 }
                Timestamp    = [datetime]::UtcNow
            }
        }

    } catch {
        throw
    }
}
