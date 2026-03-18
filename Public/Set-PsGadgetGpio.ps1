# Set-PsGadgetGpio.ps1
# Public GPIO control function for FTDI devices

function Set-PsGadgetGpio {
    <#
    .SYNOPSIS
    Controls GPIO pins on connected FTDI devices.
    
    .DESCRIPTION
    Sets GPIO pins on FTDI devices to HIGH or LOW states. Supports both MPSSE-
    capable devices (FT232H, FT2232H, FT4232H) using ACBUS0-7, and CBUS bit-bang
    devices (FT232R / FT232RL / FT232RNL) using CBUS0-3.

    For FT232R CBUS GPIO, the CBUS pins must first be programmed in the device
    EEPROM as FT_CBUS_IOMODE. Run Set-PsGadgetFt232rCbusMode once per device,
    replug the USB device, then use this function normally.

    Supports timing control and multiple pin operations.
    
    .PARAMETER Index
    Index of the FTDI device to control (from Get-PsGadgetFtdi)
    
    .PARAMETER Pins
    For MPSSE devices (FT232H, FT2232H, FT4232H): ACBUS pin numbers 0-7
      ACBUS0=pin21, ACBUS1=pin25, ACBUS2=pin26, ACBUS3=pin27
      ACBUS4=pin28, ACBUS5=pin29, ACBUS6=pin30, ACBUS7=pin31 (FT232H)
    For CBUS devices (FT232R): CBUS pin numbers 0-3 only
      (Pins outside 0-3 are rejected for CBUS devices)
    
    .PARAMETER State
    Pin state: HIGH/H/1 or LOW/L/0
    
    .PARAMETER DurationMs
    Optional duration to hold the pin state in milliseconds
    
    .PARAMETER SerialNumber
    Alternative to Index - specify device by serial number

    .PARAMETER Connection
    An already-open connection object returned by Connect-PsGadgetFtdi.
    When using this parameter set the caller is responsible for closing the connection.
    
    .EXAMPLE
    # FT232H / MPSSE device - control ACBUS pins
    Set-PsGadgetGpio -Index 0 -Pins @(2, 4) -State HIGH
    
    .EXAMPLE
    # FT232R CBUS GPIO (after running Set-PsGadgetFt232rCbusMode -Index 1 once)
    Set-PsGadgetGpio -Index 1 -Pins @(0, 1) -State HIGH
    
    .EXAMPLE
    # Pulse ACBUS0 LOW for 500ms
    Set-PsGadgetGpio -SerialNumber "ABC123" -Pins @(0) -State LOW -DurationMs 500

    .EXAMPLE
    # Connect once, call GPIO multiple times, close when done
    $conn = Connect-PsGadgetFtdi -SerialNumber "BG01X3GX"
    Set-PsGadgetGpio -Connection $conn -Pins @(0) -State HIGH   # LED on
    Set-PsGadgetGpio -Connection $conn -Pins @(1) -State HIGH
    Set-PsGadgetGpio -Connection $conn -Pins @(0, 1) -State LOW  # Both off
    $conn.Close()

    .EXAMPLE
    # OOP style via New-PsGadgetFtdi
    $dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"   # connected immediately
    $dev.SetPin(0, "HIGH")
    $dev.SetPin(0, "LOW")
    $dev.Close()
    
    .EXAMPLE
    # LED Control Example (FT232H)
    Set-PsGadgetGpio -Index 0 -Pins @(2) -State HIGH   # Red LED on
    Set-PsGadgetGpio -Index 0 -Pins @(4) -State HIGH   # Green LED on
    Set-PsGadgetGpio -Index 0 -Pins @(2, 4) -State LOW  # Both off
    
    .NOTES
    Requires FTDI D2XX drivers and FTD2XX_NET.dll assembly.
    FT232H MPSSE: ACBUS0-7 = physical pins 21,25-31.
    FT232R CBUS: CBUS0-3 require prior EEPROM configuration via Set-PsGadgetFt232rCbusMode.
    Use Get-PsGadgetFtdi to see available devices.
    #>
    
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
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
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60000)]
        [int]$DurationMs
    )
    
    try {
        # Track whether this function opened the connection (must close it in finally)
        $ownsConnection = $true

        if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            # Caller provides an already-open connection - use it directly, do not close on exit
            $ownsConnection = $false
            if (-not $Connection.IsOpen) {
                throw "The supplied connection is not open. Call Connect-PsGadgetFtdi or New-PsGadgetFtdi first."
            }
            Write-Verbose "Using caller-supplied connection: $($Connection.Description) ($($Connection.SerialNumber))"
        } elseif ($PSCmdlet.ParameterSetName -eq 'PsGadget') {
            # Caller provides a PsGadgetFtdi class instance - unwrap its internal connection
            $ownsConnection = $false
            if (-not $PsGadget.IsOpen -or -not $PsGadget._connection) {
                throw "PsGadgetFtdi is not open. Use New-PsGadgetFtdi, which connects automatically."
            }
            $Connection = $PsGadget._connection
            Write-Verbose "Using PsGadgetFtdi connection: $($Connection.Description) ($($Connection.SerialNumber))"
        } else {
            # Get available devices
            $devices = Get-FtdiDeviceList
            if (-not $devices -or $devices.Count -eq 0) {
                throw "No FTDI devices found. Run Get-PsGadgetFtdi to check available devices."
            }
            
            # Find target device
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
            
            Write-Verbose "Targeting device: $($targetDevice.Description) ($($targetDevice.SerialNumber))"
            
            # Check if device is available
            if ($targetDevice.IsOpen) {
                Write-Warning "Device $($targetDevice.SerialNumber) appears to be in use by another application"
            }
            
            # Open device connection
            $Connection = Connect-PsGadgetFtdi -Index $targetDevice.Index
            if (-not $Connection) {
                throw "Failed to connect to FTDI device"
            }
        }
        
        try {
            # Determine GPIO method - dispatch to the appropriate backend
            $gpioMethod = if ($Connection.PSObject.Properties['GpioMethod']) {
                $Connection.GpioMethod
            } else {
                'Unknown'
            }

            Write-Verbose "Device $($Connection.Type): GpioMethod=$gpioMethod, pins=[$($Pins -join ',')], state=$State"

            $success = $false
            $pinLabel = ''

            switch ($gpioMethod) {
                'MPSSE' {
                    # FT232H / FT2232H / FT4232H - ACBUS control via MPSSE command 0x82
                    $params = @{
                        DeviceHandle = $Connection
                        Pins         = $Pins
                        Direction    = $State
                    }
                    if ($DurationMs) { $params.DurationMs = $DurationMs }

                    $success  = Set-FtdiGpioPins @params
                    $pinLabel = "ACBUS pins [$($Pins -join ', ')]"
                }

                'IoT' {
                    # FT232H via .NET IoT GpioController (PS 7.4+ / .NET 8+ backend)
                    # PsGadget ACBUS pin 0-7 -> IoT GpioController pin 8-15 (C0-C7)
                    if (-not $Connection.GpioController) {
                        throw "IoT connection is missing GpioController. Re-open the device with Connect-PsGadgetFtdi."
                    }
                    $iotParams = @{
                        GpioController = $Connection.GpioController
                        Pins           = $Pins
                        State          = $State
                    }
                    if ($DurationMs) { $iotParams.DurationMs = $DurationMs }

                    $success  = Set-FtdiIotGpioPins @iotParams
                    $pinLabel = "ACBUS pins [$($Pins -join ', ')] (IoT)"
                }

                'CBUS' {
                    # FT232R / FT231X / FT230X - CBUS bit-bang via SetBitMode 0x20
                    # Validate pin range - CBUS bit-bang only supports CBUS0-3
                    $badPins = $Pins | Where-Object { $_ -gt 3 }
                    if ($badPins) {
                        throw (
                            "Pin(s) [$($badPins -join ', ')] are out of range for CBUS bit-bang. " +
                            "$($Connection.Type) CBUS GPIO supports CBUS0-3 only (pins 0-3)."
                        )
                    }

                    $cbusParams = @{
                        Connection = $Connection
                        Pins       = $Pins
                        State      = $State
                    }
                    if ($DurationMs) { $cbusParams.DurationMs = $DurationMs }

                    $success  = Set-FtdiCbusBits @cbusParams
                    $pinLabel = "CBUS pins [$($Pins -join ', ')]"
                }

                'AsyncBitBang' {
                    # Async bit-bang on ADBUS0-7 (UART data pins). This mode must be
                    # enabled beforehand via Set-PsGadgetFtdiMode -Mode AsyncBitBang
                    # with an appropriate direction mask (default 0xFF).
                    # We simply write a byte with the requested pin states to the
                    # device; higher-level sequence streaming is handled by user
                    # scripts (see example StepperMotor.md).
                    $badPins = $Pins | Where-Object { $_ -lt 0 -or $_ -gt 7 }
                    if ($badPins) {
                        throw "Pin(s) [$($badPins -join ', ')] are out of range for async bit-bang. ADBUS GPIO supports pins 0-7."
                    }
                    # build output byte
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
                        # clear outputs after duration
                        $Connection.Write([byte[]]@(0), 1, [ref]$written) | Out-Null
                    }
                    $pinLabel = "ADBUS pins [$($Pins -join ', ')]"
                    $success = $true
                }

                default {
                    # Unknown or unsupported type - attempt MPSSE as last resort
                    Write-Warning "Unknown GpioMethod '$gpioMethod' for device '$($Connection.Type)'. Attempting MPSSE fallback."
                    $params = @{
                        DeviceHandle = $Connection
                        Pins         = $Pins
                        Direction    = $State
                    }
                    if ($DurationMs) { $params.DurationMs = $DurationMs }
                    $success  = Set-FtdiGpioPins @params
                    $pinLabel = "pins [$($Pins -join ', ')]"
                }
            }

            if (-not $success) {
                throw "GPIO operation failed"
            }
            
        } finally {
            # Only close the connection if this function opened it
            if ($ownsConnection -and $Connection -and $Connection.Close) {
                try {
                    $Connection.Close()
                } catch {
                    Write-Warning "Failed to close device connection: $_"
                }
            }
        }
        
    } catch {
        Write-Error "GPIO control failed: $_"
        throw
    }
}