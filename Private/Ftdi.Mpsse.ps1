# Ftdi.Mpsse.ps1
# MPSSE (Multi-Protocol Synchronous Serial Engine) GPIO control functions

function Set-FtdiGpioPins {
    <#
    .SYNOPSIS
    Controls FTDI GPIO pins via MPSSE commands.
    
    .DESCRIPTION
    Sets ACBUS pins on FTDI devices using MPSSE command 0x82.
    Supports individual pin control with direction and value settings.
    
    .PARAMETER DeviceHandle
    Handle to the opened FTDI device
    
    .PARAMETER Pins
    Array of pin numbers to control (0-7 for ACBUS0-ACBUS7)
    
    .PARAMETER Direction
    Pin direction: HIGH/H/1 or LOW/L/0
    
    .PARAMETER DurationMs
    Optional duration to hold the pin state in milliseconds
    
    .PARAMETER PreserveOtherPins
    If specified, preserve the state of other pins not being set
    
    .EXAMPLE
    Set-FtdiGpioPins -DeviceHandle $handle -Pins @(2,4) -Direction HIGH
    
    .EXAMPLE
    Set-FtdiGpioPins -DeviceHandle $handle -Pins @(0) -Direction LOW -DurationMs 500
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 7)]
        [int[]]$Pins,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('HIGH', 'LOW', 'H', 'L', '1', '0')]
        [string]$Direction = 'LOW',
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60000)]
        [int]$DurationMs,
        
        [Parameter(Mandatory = $false)]
        [switch]$PreserveOtherPins
    )
    
    try {
        # Validate device handle
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or device is not open"
        }
        
        # Normalize direction to boolean
        $isHigh = $Direction -in @('HIGH', 'H', '1')
        
        # Calculate bitmask for specified pins
        $pinMask = 0
        foreach ($pin in $Pins) {
            $pinMask = $pinMask -bor (1 -shl $pin)
        }
        
        Write-Verbose ("Setting pins {0} to {1} (mask: 0x{2:X2})" -f ($Pins -join ','), $Direction, $pinMask)
        
        # MPSSE ACBUS control values
        $directionMask = 0xFF  # All pins as outputs by default
        $outputValue = if ($isHigh) { $pinMask } else { 0 }
        
        # Send MPSSE command 0x82: Set ACBUS pins
        $success = Send-MpsseAcbusCommand -DeviceHandle $DeviceHandle -Value $outputValue -DirectionMask $directionMask
        
        if (-not $success) {
            throw "Failed to send MPSSE ACBUS command"
        }
        
        # Handle duration if specified
        if ($DurationMs) {
            Write-Verbose "Holding pin state for $DurationMs ms..."
            Start-Sleep -Milliseconds $DurationMs
            
            # Optionally reset pins after duration
            $resetValue = if ($isHigh) { 0 } else { $pinMask }
            Send-MpsseAcbusCommand -DeviceHandle $DeviceHandle -Value $resetValue -DirectionMask $directionMask | Out-Null
        }
        
        return $true
        
    } catch {
        Write-Error "Failed to set FTDI GPIO pins: $_"
        return $false
    }
}

function Send-MpsseAcbusCommand {
    <#
    .SYNOPSIS
    Sends MPSSE command to control ACBUS pins.
    
    .DESCRIPTION
    Sends the low-level MPSSE command 0x82 to set ACBUS pin values and directions.
    
    .PARAMETER DeviceHandle
    Handle to the opened FTDI device
    
    .PARAMETER Value
    8-bit value for pin states (bit 0 = ACBUS0, bit 1 = ACBUS1, etc.)
    
    .PARAMETER DirectionMask
    8-bit direction mask (1 = output, 0 = input)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 255)]
        [byte]$Value,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 255)]
        [byte]$DirectionMask
    )
    
    try {
        # MPSSE command structure for ACBUS control:
        # Byte 0: 0x82 (Set data bits high byte - ACBUS)
        # Byte 1: Value (pin states)
        # Byte 2: Direction mask (1=output, 0=input)
        [byte[]]$command = @(0x82, $Value, $DirectionMask)
        
        Write-Verbose ("MPSSE command: 0x{0:X2} 0x{1:X2} 0x{2:X2}" -f $command[0], $command[1], $command[2])
        
        # Check if we have real FTDI capabilities or are in stub mode
        if ($script:FtdiInitialized -and $DeviceHandle.GetType().Name -eq 'FTDI') {
            # Real FTDI device - send actual command
            [uint32]$bytesWritten = 0
            $status = $DeviceHandle.Write($command, $command.Length, [ref]$bytesWritten)
            
            if ($status -eq $script:FTDI_OK -and $bytesWritten -eq $command.Length) {
                Write-Verbose "MPSSE command sent successfully ($bytesWritten bytes)"
                return $true
            } else {
                Write-Warning "MPSSE command failed: Status=$status, BytesWritten=$bytesWritten"
                return $false
            }
        } else {
            # Stub mode - simulate successful operation
            Write-Verbose "MPSSE command sent successfully (STUB MODE)"
            return $true
        }
        
    } catch {
        Write-Error "Failed to send MPSSE ACBUS command: $_"
        return $false
    }
}

function Get-FtdiGpioPins {
    <#
    .SYNOPSIS
    Reads the current state of FTDI GPIO pins.
    
    .DESCRIPTION
    Uses MPSSE command 0x83 to read ACBUS pin states.
    
    .PARAMETER DeviceHandle
    Handle to the opened FTDI device
    
    .EXAMPLE
    $pinStates = Get-FtdiGpioPins -DeviceHandle $handle
    #>
    [CmdletBinding()]
    [OutputType([byte])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle
    )
    
    try {
        # Validate device handle
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or device is not open"
        }
        
        # MPSSE command 0x83: Read ACBUS pins
        [byte[]]$command = @(0x83)
        
        if ($script:FtdiInitialized -and $DeviceHandle.GetType().Name -eq 'FTDI') {
            # Real FTDI device
            [uint32]$bytesWritten = 0
            $status = $DeviceHandle.Write($command, $command.Length, [ref]$bytesWritten)
            
            if ($status -ne $script:FTDI_OK) {
                throw "Failed to send read command: $status"
            }
            
            # Read response
            [byte[]]$buffer = New-Object byte[] 1
            [uint32]$bytesRead = 0
            $status = $DeviceHandle.Read($buffer, 1, [ref]$bytesRead)
            
            if ($status -eq $script:FTDI_OK -and $bytesRead -eq 1) {
                Write-Verbose ("ACBUS pin states: 0x{0:X2}" -f $buffer[0])
                return $buffer[0]
            } else {
                throw "Failed to read pin states: Status=$status, BytesRead=$bytesRead"
            }
        } else {
            # Stub mode - return simulated pin states
            $stubValue = 0x55  # Alternating pattern for testing
            Write-Verbose ("ACBUS pin states: 0x{0:X2} (STUB MODE)" -f $stubValue)
            return [byte]$stubValue
        }
        
    } catch {
        Write-Error "Failed to read FTDI GPIO pins: $_"
        return [byte]0
    }
}

function Initialize-MpsseI2C {
    <#
    .SYNOPSIS
    Initializes FTDI device for I2C communication via MPSSE.
    
    .DESCRIPTION
    Sets up the FTDI device for I2C bit-banging using MPSSE engine.
    Configures clock frequency and I2C pin mapping.
    
    .PARAMETER DeviceHandle
    Handle to the opened FTDI device
    
    .PARAMETER ClockFrequency
    I2C clock frequency in Hz (default: 100000 for standard mode)
    
    .EXAMPLE
    Initialize-MpsseI2C -DeviceHandle $handle -ClockFrequency 100000
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1000, 400000)]
        [int]$ClockFrequency = 100000
    )
    
    try {
        # Validate device handle
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or device is not open"
        }
        
        # Resolve real device handle - may be PSCustomObject wrapper or raw FTDI type
        $isRealDevice = $script:FtdiInitialized -and (
            $DeviceHandle.GetType().Name -eq 'FTDI' -or
            ($null -ne $DeviceHandle.PSObject -and $null -ne $DeviceHandle.Device)
        )

        if ($isRealDevice) {
            [uint32]$bytesWritten = 0

            # Disable divide-by-5 so base clock = 60 MHz (required for correct divisor math)
            # Disable internal loopback, disable 3-phase clocking (I2C uses 2-phase)
            [byte[]]$setupCommand = @(
                0x8A,        # Disable clk divide-by-5 => 60 MHz master
                0x85,        # Disable loopback
                0x97         # Disable 3-phase clocking
            )
            $status = $DeviceHandle.Write($setupCommand, $setupCommand.Length, [ref]$bytesWritten)
            if ($status -ne $script:FTDI_OK) {
                throw "Failed to configure MPSSE base settings: $status"
            }
            Start-Sleep -Milliseconds 20

            # Set clock frequency
            # MPSSE clock = 60 MHz / ((1 + ClockDivisor) * 2)
            $clockDivisor = [math]::Floor((60000000 / ($ClockFrequency * 2)) - 1)
            $clockDivisor = [math]::Max(0, [math]::Min(65535, $clockDivisor))

            [byte[]]$clockCommand = @(
                0x86,  # Set clock divisor
                [byte]($clockDivisor -band 0xFF),
                [byte](($clockDivisor -shr 8) -band 0xFF)
            )
            $status = $DeviceHandle.Write($clockCommand, $clockCommand.Length, [ref]$bytesWritten)
            if ($status -ne $script:FTDI_OK) {
                throw "Failed to set I2C clock frequency: $status"
            }

            # Set I2C pins idle: ADBUS0=SCL=1 (output), ADBUS1=SDA=1 (output)
            [byte[]]$pinCommand = @(0x80, 0x03, 0x03)
            $status = $DeviceHandle.Write($pinCommand, $pinCommand.Length, [ref]$bytesWritten)
            if ($status -ne $script:FTDI_OK) {
                throw "Failed to set I2C pin idle state: $status"
            }
            Start-Sleep -Milliseconds 20

            Write-Verbose "I2C initialized at $ClockFrequency Hz (divisor: $clockDivisor)"
            return $true
        } else {
            # Stub mode
            Write-Verbose "I2C initialized at $ClockFrequency Hz (STUB MODE)"
            return $true
        }
        
    } catch {
        Write-Error "Failed to initialize MPSSE I2C: $_"
        return $false
    }
}

function Send-MpsseI2CWrite {
    <#
    .SYNOPSIS
    Sends I2C write command via MPSSE.
    
    .DESCRIPTION
    Writes data to an I2C device using MPSSE bit-banging.
    Handles I2C start condition, address, data, and stop condition.
    
    .PARAMETER DeviceHandle
    Handle to the opened FTDI device
    
    .PARAMETER Address
    7-bit I2C slave address
    
    .PARAMETER Data
    Byte array of data to write
    
    .EXAMPLE
    Send-MpsseI2CWrite -DeviceHandle $handle -Address 0x3C -Data @(0x00, 0xAE)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 127)]
        [byte]$Address,
        
        [Parameter(Mandatory = $true)]
        [byte[]]$Data
    )
    
    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or device is not open"
        }
        
        # Resolve real device handle - may be PSCustomObject wrapper or raw FTDI type
        $isRealDevice = $script:FtdiInitialized -and (
            $DeviceHandle.GetType().Name -eq 'FTDI' -or
            ($null -ne $DeviceHandle.PSObject -and $null -ne $DeviceHandle.Device)
        )

        if ($isRealDevice) {
            # Build I2C transaction as a single buffer sent in one Write call
            [System.Collections.Generic.List[byte]]$transaction = @()

            # I2C Start condition:
            #   SDA high, SCL high (idle)
            #   SDA falls while SCL high  => start
            #   SCL falls to begin first bit
            $transaction.AddRange([byte[]]@(0x80, 0x03, 0x03))  # SCL=1, SDA=1, both output
            $transaction.AddRange([byte[]]@(0x80, 0x01, 0x03))  # SCL=1, SDA=0 (start condition)
            $transaction.AddRange([byte[]]@(0x80, 0x00, 0x03))  # SCL=0, SDA=0 (clock low)

            # Helper scriptblock: clock out one byte (8 bits) then ACK pulse
            # 0x1B = Clock Data Bits Out on Falling Edge, MSB first, no read
            #        Format: 0x1B <bit_count-1> <data_byte>
            #        0x1B 0x07 $b = clock out 8 bits of $b
            # ACK cycle: release SDA (input), pulse SCL high then low, reclaim SDA
            $clockByte = [scriptblock] {
                param([byte]$b)
                # Clock 8 data bits out
                $transaction.AddRange([byte[]]@(0x1B, 0x07, $b))
                # ACK clock cycle - release SDA to input so device can drive ACK
                $transaction.AddRange([byte[]]@(0x80, 0x00, 0x01))  # SDA=input, SCL=output-low
                $transaction.AddRange([byte[]]@(0x80, 0x01, 0x01))  # SCL=high (ACK bit sampled)
                $transaction.AddRange([byte[]]@(0x80, 0x00, 0x01))  # SCL=low
                $transaction.AddRange([byte[]]@(0x80, 0x02, 0x03))  # SDA=output-high, SCL=low
            }

            # Write address byte with write bit (R/W=0)
            $addressByte = [byte](($Address -shl 1) -bor 0x00)
            & $clockByte $addressByte

            # Write each data byte
            foreach ($b in $Data) {
                & $clockByte ([byte]$b)
            }

            # I2C Stop condition:
            #   SCL low, SDA low
            #   SCL rises
            #   SDA rises while SCL high  => stop
            $transaction.AddRange([byte[]]@(0x80, 0x00, 0x03))  # SCL=0, SDA=0
            $transaction.AddRange([byte[]]@(0x80, 0x01, 0x03))  # SCL=1, SDA=0
            $transaction.AddRange([byte[]]@(0x80, 0x03, 0x03))  # SCL=1, SDA=1 (stop)

            # Send entire transaction in one call
            [uint32]$bytesWritten = 0
            [byte[]]$command = $transaction.ToArray()
            $status = $DeviceHandle.Write($command, $command.Length, [ref]$bytesWritten)

            if ($status -eq $script:FTDI_OK -and $bytesWritten -eq $command.Length) {
                Write-Verbose ("I2C write OK: Address=0x{0:X2}, {1} data bytes" -f $Address, $Data.Length)
                return $true
            } else {
                throw "I2C write failed: Status=$status, BytesWritten=$bytesWritten (expected $($command.Length))"
            }
        } else {
            # Stub mode
            Write-Verbose ("I2C write: Address=0x{0:X2}, {1} bytes (STUB MODE)" -f $Address, $Data.Length)
            return $true
        }
        
    } catch {
        Write-Error "Failed to send I2C write: $_"
        return $false
    }
}

function Invoke-FtdiI2CScan {
    <#
    .SYNOPSIS
    Scans the I2C bus for connected devices.

    .DESCRIPTION
    Probes all standard 7-bit I2C addresses (0x08-0x77) and returns an object
    for each address that ACKs.  Supports two backends:
      - IoT  (FT232H via .NET IoT): uses I2cBus.CreateDevice() + ReadByte()
      - D2XX (FT232H via FTD2XX_NET MPSSE): MPSSE bit-bang START/addr/ACK/STOP

    .PARAMETER Connection
    Open connection object returned by Connect-PsGadgetFtdi.

    .PARAMETER ClockFrequency
    I2C SCL frequency in Hz. Only used for the D2XX MPSSE path. Default 100000.

    .EXAMPLE
    $r1 | Connect-PsGadgetFtdi | Invoke-FtdiI2CScan
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$Connection,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1000, 400000)]
        [int]$ClockFrequency = 100000
    )

    $found      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $gpioMethod = if ($Connection.PSObject.Properties['GpioMethod']) { $Connection.GpioMethod } else { 'Stub' }

    if ($gpioMethod -eq 'IoT') {
        # IoT path - use .NET IoT I2cBus to probe each address.
        # CreateOrGetI2cBus() is cached; do not dispose the bus.
        Write-Verbose 'I2C scan via IoT I2cBus (0x08-0x77)...'
        $bus = $Connection.Device.CreateOrGetI2cBus()
        for ($addr = 0x08; $addr -le 0x77; $addr++) {
            $dev = $null
            try {
                $dev = $bus.CreateDevice($addr)
                [byte]$dummy = $dev.ReadByte()   # NACK throws; silence below
                $found.Add([PSCustomObject]@{
                    PSTypeName = 'PsGadget.I2cDevice'
                    Address    = $addr
                    Hex        = ('0x{0:X2}' -f $addr)
                })
                Write-Verbose ('I2C device found: 0x{0:X2}' -f $addr)
            } catch {
                # No device at this address - expected during scan
            } finally {
                if ($dev) { try { $dev.Dispose() } catch {} }
            }
        }

    } elseif ($gpioMethod -eq 'MPSSE' -and $script:FtdiInitialized) {
        # D2XX path - MPSSE bit-bang I2C scan.
        # SCL = ADBUS0, SDA-out = ADBUS1, SDA-in = ADBUS1 (open-drain, released to input for ACK).
        Write-Verbose "I2C scan via MPSSE bit-bang D2XX (0x08-0x77) at $ClockFrequency Hz..."
        $ok = Initialize-MpsseI2C -DeviceHandle $Connection -ClockFrequency $ClockFrequency
        if (-not $ok) { throw 'Failed to initialize MPSSE I2C for scan' }

        # Purge any stale RX bytes before starting scan
        try { $Connection.Device.Purge(2) | Out-Null } catch {}
        Start-Sleep -Milliseconds 20

        for ($addr = 0x08; $addr -le 0x77; $addr++) {
            $addrByte = [byte](($addr -shl 1) -bor 0x00)  # 7-bit address + R/W=0 (write)

            $tx = [System.Collections.Generic.List[byte]]::new()

            # I2C START: SDA falls while SCL is high
            $tx.AddRange([byte[]]@(0x80, 0x03, 0x03))  # idle:  SCL=1, SDA=1, both output
            $tx.AddRange([byte[]]@(0x80, 0x01, 0x03))  # start: SCL=1, SDA=0
            $tx.AddRange([byte[]]@(0x80, 0x00, 0x03))  # SCL=0 (begin clocking)

            # Clock 8 address bits out on falling edge, MSB first (0x1B = bit-clock-out)
            $tx.AddRange([byte[]]@(0x1B, 0x07, $addrByte))

            # ACK clock: release SDA to input, raise SCL, capture ADBUS with 0x81, lower SCL
            $tx.AddRange([byte[]]@(0x80, 0x00, 0x01))  # SDA=input (dir=0x01: only SCL output), SCL=0
            $tx.AddRange([byte[]]@(0x80, 0x01, 0x01))  # SCL=1 (device drives ACK bit on SDA)
            $tx.Add([byte]0x81)                         # queue read of ADBUS byte (bit 1 = SDA)
            $tx.AddRange([byte[]]@(0x80, 0x00, 0x01))  # SCL=0
            $tx.AddRange([byte[]]@(0x80, 0x02, 0x03))  # SDA=1(output-high), SCL=0, both output

            # I2C STOP: SDA rises while SCL is high
            $tx.AddRange([byte[]]@(0x80, 0x00, 0x03))  # SCL=0, SDA=0
            $tx.AddRange([byte[]]@(0x80, 0x01, 0x03))  # SCL=1
            $tx.AddRange([byte[]]@(0x80, 0x03, 0x03))  # SCL=1, SDA=1 (stop)

            # Send Immediate - flush MPSSE command buffer to host
            $tx.Add([byte]0x87)

            [uint32]$bw  = 0
            [byte[]]$cmd = $tx.ToArray()
            $writeStatus = $Connection.Write($cmd, $cmd.Length, [ref]$bw)
            if ($writeStatus -ne $script:FTDI_OK) { continue }

            # Read 1 byte: ADBUS pin state queued by 0x81.  Bit 1 = SDA.
            # SDA=0 means device held it low => ACK => device present.
            [byte[]]$ackBuf = [byte[]]::new(1)
            [uint32]$br     = 0
            Start-Sleep -Milliseconds 1
            $Connection.Read($ackBuf, 1, [ref]$br)
            if ($br -eq 1) {
                $sdaBit = ($ackBuf[0] -shr 1) -band 0x01
                if ($sdaBit -eq 0) {
                    $found.Add([PSCustomObject]@{
                        PSTypeName = 'PsGadget.I2cDevice'
                        Address    = $addr
                        Hex        = ('0x{0:X2}' -f $addr)
                    })
                    Write-Verbose ('I2C device found: 0x{0:X2}' -f $addr)
                }
            }
        }

    } else {
        # Stub mode - return common I2C device addresses for development
        Write-Verbose 'I2C scan: stub mode - returning simulated device list'
        foreach ($stubAddr in @(0x3C, 0x3D, 0x48, 0x68)) {
            $found.Add([PSCustomObject]@{
                PSTypeName = 'PsGadget.I2cDevice'
                Address    = $stubAddr
                Hex        = ('0x{0:X2}' -f $stubAddr)
            })
        }
    }

    return , $found.ToArray()
}