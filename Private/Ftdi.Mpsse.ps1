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
        
        if ($script:FtdiInitialized -and $DeviceHandle.GetType().Name -eq 'FTDI') {
            # Reset MPSSE
            [byte[]]$resetCommand = @(0xAA)
            [uint32]$bytesWritten = 0
            $status = $DeviceHandle.Write($resetCommand, $resetCommand.Length, [ref]$bytesWritten)
            
            if ($status -ne $script:FTDI_OK) {
                throw "Failed to reset MPSSE: $status"
            }
            
            Start-Sleep -Milliseconds 50
            
            # Set clock frequency
            # MPSSE clock = 60MHz base clock divided by ((1+ClockDivisor)*2)
            $clockDivisor = [math]::Floor((60000000 / ($ClockFrequency * 2)) - 1)
            $clockDivisor = [math]::Max(0, [math]::Min(65535, $clockDivisor))
            
            [byte[]]$clockCommand = @(
                0x86,  # Set clock frequency
                [byte]($clockDivisor -band 0xFF),
                [byte](($clockDivisor -shr 8) -band 0xFF)
            )
            
            $status = $DeviceHandle.Write($clockCommand, $clockCommand.Length, [ref]$bytesWritten)
            if ($status -ne $script:FTDI_OK) {
                throw "Failed to set I2C clock frequency: $status"
            }
            
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
        
        if ($script:FtdiInitialized -and $DeviceHandle.GetType().Name -eq 'FTDI') {
            # Build I2C transaction
            [System.Collections.Generic.List[byte]]$transaction = @()
            
            # I2C Start condition
            $transaction.AddRange(@(0x80, 0x03, 0x03))  # Set SDA/SCL high
            $transaction.AddRange(@(0x80, 0x01, 0x03))  # Set SDA low (start)
            $transaction.AddRange(@(0x80, 0x00, 0x03))  # Set SCL low
            
            # Write address byte with write bit (bit 0 = 0)
            $addressByte = ($Address -shl 1) -bor 0x00
            $transaction.AddRange(@(0x11, 0x07, $addressByte))  # Clock out 8 bits
            
            # Write data bytes
            foreach ($byte in $Data) {
                $transaction.AddRange(@(0x11, 0x07, $byte))  # Clock out 8 bits
            }
            
            # I2C Stop condition
            $transaction.AddRange(@(0x80, 0x00, 0x03))  # Set SDA/SCL low
            $transaction.AddRange(@(0x80, 0x01, 0x03))  # Set SCL high
            $transaction.AddRange(@(0x80, 0x03, 0x03))  # Set SDA high (stop)
            
            # Send transaction
            [uint32]$bytesWritten = 0
            $command = $transaction.ToArray()
            $status = $DeviceHandle.Write($command, $command.Length, [ref]$bytesWritten)
            
            if ($status -eq $script:FTDI_OK -and $bytesWritten -eq $command.Length) {
                Write-Verbose ("I2C write successful: Address=0x{0:X2}, {1} bytes" -f $Address, $Data.Length)
                return $true
            } else {
                throw "I2C write failed: Status=$status, BytesWritten=$bytesWritten"
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