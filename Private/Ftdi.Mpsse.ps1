# Ftdi.Mpsse.ps1
# MPSSE (Multi-Protocol Synchronous Serial Engine) GPIO control functions

function Get-FtdiD2xxHandle {
    # Extract or acquire a real FTD2XX_NET.FTDI handle from a device handle wrapper.
    #
    # Handles three cases:
    #   1. $DeviceHandle is itself a FTD2XX_NET.FTDI object (rare - direct pass-through)
    #   2. $DeviceHandle is a PSCustomObject with Device = FTD2XX_NET.FTDI (normal D2XX path)
    #   3. $DeviceHandle is a PSCustomObject with Device = FtdiSharp/IoT (stale session scenario)
    #      -> opens a fresh FTD2XX_NET handle via SerialNumber and caches it on the connection
    #
    # Returns $null when stub mode is appropriate (no D2XX available).
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle
    )

    if ($null -eq $DeviceHandle) { return $null }

    # Case 1: DeviceHandle IS already the raw FTDI object
    if ($DeviceHandle.GetType().FullName -eq 'FTD2XX_NET.FTDI') {
        return $DeviceHandle
    }

    # Case 2: PSCustomObject wrapper - check Device property type
    if ($DeviceHandle.PSObject.Properties['Device'] -and $null -ne $DeviceHandle.Device) {
        $candidate = $DeviceHandle.Device
        if ($candidate.GetType().FullName -eq 'FTD2XX_NET.FTDI') {
            return $candidate
        }
        # Device is something else (FtdiSharp, IoT, etc.) - fall through to Case 3
        Write-Verbose ("Device handle has non-D2XX backend ({0}); acquiring FTD2XX_NET handle..." -f $candidate.GetType().FullName)
    }

    # Case 3: No usable D2XX handle yet - re-acquire using the device serial number.
    # This covers the stale-FtdiSharp-session scenario: a previous session opened the device
    # via FtdiSharp (old Connect-PsGadgetFtdi), but the new code needs raw D2XX MPSSE access.
    # FTD2XX_NET can open the device even while FtdiSharp holds a handle (ftd2xx.dll allows it).
    if (-not $script:FtdiInitialized) { return $null }

    $serial = $null
    if ($DeviceHandle.PSObject.Properties['SerialNumber'] -and $DeviceHandle.SerialNumber) {
        $serial = $DeviceHandle.SerialNumber
    }
    if (-not $serial) { return $null }

    try {
        $newFtdi = [FTD2XX_NET.FTDI]::new()
        $openStatus = $newFtdi.OpenBySerialNumber($serial)
        if ($openStatus -ne $script:FTDI_OK) {
            $newFtdi.Close() | Out-Null
            Write-Warning "Get-FtdiD2xxHandle: could not open D2XX handle for '$serial' (status=$openStatus). Restart your PS session if this persists."
            return $null
        }

        # Configure MPSSE so ACBUS 0x82 commands work immediately
        $newFtdi.ResetDevice() | Out-Null
        $newFtdi.SetBitMode(0x00, 0x02) | Out-Null   # MPSSE mode
        $newFtdi.SetTimeouts(5000, 5000) | Out-Null
        $newFtdi.Purge(3) | Out-Null
        Start-Sleep -Milliseconds 5
        [uint32]$initW = 0
        $newFtdi.Write([byte[]](0x8A, 0x97, 0x8D), 3, [ref]$initW) | Out-Null
        Start-Sleep -Milliseconds 5

        # Cache the real D2XX handle so subsequent calls in this session reuse it
        if ($DeviceHandle.PSObject.Properties['Device']) {
            $DeviceHandle.Device = $newFtdi
        } else {
            $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'Device' -Value $newFtdi -Force
        }
        # Initialize ACBUS state cache to 0 so Get-FtdiGpioPins never needs a USB read
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'AcbusCachedState' -Value ([byte]0) -Force
        Write-Verbose "Get-FtdiD2xxHandle: acquired FTD2XX_NET handle for '$serial' (was using non-D2XX backend)"
        return $newFtdi
    } catch {
        Write-Verbose "Get-FtdiD2xxHandle: failed to acquire D2XX handle: $_"
        return $null
    }
}

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

        # Read current ACBUS pin state so that pins not in $Pins are preserved (read-modify-write)
        $currentValue = [byte](Get-FtdiGpioPins -DeviceHandle $DeviceHandle)
        $directionMask = 0xFF  # All ACBUS pins as outputs

        # Apply state change only to the specified pins; all others keep their current value
        if ($isHigh) {
            $outputValue = [byte]($currentValue -bor [byte]$pinMask)
        } else {
            $outputValue = [byte]($currentValue -band ([byte](0xFF -bxor [byte]$pinMask)))
        }

        Write-Verbose ("Read-modify-write: current=0x{0:X2} mask=0x{1:X2} new=0x{2:X2}" -f $currentValue, $pinMask, $outputValue)

        # Send MPSSE command 0x82: Set ACBUS pins
        $success = Send-MpsseAcbusCommand -DeviceHandle $DeviceHandle -Value $outputValue -DirectionMask $directionMask

        if (-not $success) {
            throw "Failed to send MPSSE ACBUS command"
        }

        # Handle duration if specified
        if ($DurationMs) {
            Write-Verbose "Holding pin state for $DurationMs ms..."
            Start-Sleep -Milliseconds $DurationMs

            # Reverse ONLY the modified pins, preserve all others
            if ($isHigh) {
                $resetValue = [byte]($outputValue -band ([byte](0xFF -bxor [byte]$pinMask)))
            } else {
                $resetValue = [byte]($outputValue -bor [byte]$pinMask)
            }
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
        
        # --- FTD2XX_NET path - get (or re-acquire) the raw FTD2XX_NET.FTDI handle ---
        $rawFtdi = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle

        if ($script:FtdiInitialized -and $null -ne $rawFtdi) {
            [uint32]$bytesWritten = 0
            $status = $rawFtdi.Write($command, $command.Length, [ref]$bytesWritten)

            if ($status -eq $script:FTDI_OK -and $bytesWritten -eq $command.Length) {
                Write-Verbose "MPSSE command sent successfully ($bytesWritten bytes)"
                # Update cached ACBUS state - eliminates USB reads from Get-FtdiGpioPins in hot loops
                $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'AcbusCachedState' -Value ([byte]$Value) -Force
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

        # Return cached state if available - avoids USB round-trip in GPIO hot loops
        if ($DeviceHandle.PSObject.Properties['AcbusCachedState']) {
            Write-Verbose ("ACBUS pin states (cached): 0x{0:X2}" -f [byte]$DeviceHandle.AcbusCachedState)
            return [byte]$DeviceHandle.AcbusCachedState
        }
        
        # --- FTD2XX_NET path - get (or re-acquire) the raw FTD2XX_NET.FTDI handle ---
        $rawFtdi = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle

        # MPSSE command 0x83: Read ACBUS pins
        [byte[]]$command = @(0x83)

        if ($script:FtdiInitialized -and $null -ne $rawFtdi) {
            # Real FTDI device
            [uint32]$bytesWritten = 0
            $status = $rawFtdi.Write($command, $command.Length, [ref]$bytesWritten)

            if ($status -ne $script:FTDI_OK) {
                throw "Failed to send read command: $status"
            }

            # Read response
            [byte[]]$buffer = New-Object byte[] 1
            [uint32]$bytesRead = 0
            $status = $rawFtdi.Read($buffer, 1, [ref]$bytesRead)

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

        # Resolve the raw FTD2XX_NET.FTDI object from the device handle wrapper.
        $rawDevice    = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isRealDevice = $script:FtdiInitialized -and ($null -ne $rawDevice)

        if ($isRealDevice) {
            [uint32]$bytesWritten = 0

            # Helper: write bytes to raw device and check status (int 0 = FT_OK)
            $writeCmd = {
                param([byte[]]$cmd, [string]$label)
                [uint32]$bw = 0
                $st = $rawDevice.Write($cmd, [uint32]$cmd.Length, [ref]$bw)
                if ([int]$st -ne 0) { throw "$label failed: status=$st" }
            }

            # Disable clk divide-by-5 (=> 60 MHz base), disable loopback, disable 3-phase clk
            & $writeCmd @(0x8A, 0x85, 0x97) 'MPSSE base config'
            Start-Sleep -Milliseconds 20

            # Set clock frequency: MPSSE clock = 60 MHz / ((1 + divisor) * 2)
            $clockDivisor = [math]::Floor((60000000 / ($ClockFrequency * 2)) - 1)
            $clockDivisor = [math]::Max(0, [math]::Min(65535, $clockDivisor))
            & $writeCmd @(0x86, [byte]($clockDivisor -band 0xFF), [byte](($clockDivisor -shr 8) -band 0xFF)) 'Set clock divisor'

            # Set I2C pins idle: ADBUS0=SCL=1 (output), ADBUS1=SDA=1 (output)
            & $writeCmd @(0x80, 0x03, 0x03) 'I2C pin idle state'
            Start-Sleep -Milliseconds 20

            Write-Verbose "I2C initialized at $ClockFrequency Hz (divisor: $clockDivisor)"
            return $true
        } else {
            # Stub mode or no raw device
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
        [byte[]]$Data,

        [Parameter(Mandatory = $false)]
        [switch]$ByteDump
    )

    # NACK is detected inside the try block via a flag so that the terminating error
    # is raised AFTER the try/catch boundary (hardware errors stay non-terminating).
    $nackPhase = $null

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or device is not open"
        }

        # Resolve real device handle via the shared helper
        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isRealDevice = $script:FtdiInitialized -and ($null -ne $rawDevice)

        if ($isRealDevice) {
            if (-not $rawDevice) { throw 'Cannot resolve raw FTDI device handle for I2C write' }

            # Assemble the ordered list of bytes to clock: address (write) then data
            $allBytes = [System.Collections.Generic.List[byte]]::new()
            $allBytes.Add([byte](($Address -shl 1) -bor 0x00))
            foreach ($b in $Data) { $allBytes.Add([byte]$b) }

            # I2C START condition: SDA falls while SCL is high
            [byte[]]$startCmd = @(
                0x80, 0x03, 0x03,   # idle:  SCL=1, SDA=1, both output
                0x80, 0x01, 0x03,   # start: SCL=1, SDA=0
                0x80, 0x00, 0x03    # SCL=0  (begin clocking)
            )
            [uint32]$bw = 0
            $st = $rawDevice.Write($startCmd, [uint32]$startCmd.Length, [ref]$bw)
            if ([int]$st -ne 0) { throw "I2C START failed: D2XX status=$st" }

            # Clock each byte out and validate ACK before proceeding to the next byte.
            # Pattern mirrors Invoke-FtdiI2CScan which is known-good:
            #   0x1B 0x07 $b  - clock 8 bits out on falling edge, MSB first
            #   0x81          - queue a read of the ADBUS byte (bit 1 = SDA)
            #   0x87          - SEND_IMMEDIATE: flush MPSSE buffer to host now
            # Then Read(1 byte): bit 1 of result = SDA.  0=ACK, 1=NACK.
            for ($byteIdx = 0; $byteIdx -lt $allBytes.Count; $byteIdx++) {
                [byte]$b = $allBytes[$byteIdx]

                [byte[]]$byteCmd = @(
                    0x1B, 0x07, $b,     # clock 8 bits out on falling edge, MSB first
                    0x80, 0x00, 0x01,   # SDA=input (dir=0x01: only SCL output), SCL=0
                    0x80, 0x01, 0x01,   # SCL=1 (device drives ACK bit on SDA)
                    0x81,               # read ADBUS byte into RX buffer (bit 1 = SDA)
                    0x80, 0x00, 0x01,   # SCL=0
                    0x80, 0x02, 0x03,   # SDA=output-high, SCL=0, both output
                    0x87                # SEND_IMMEDIATE: flush to host now
                )

                if ($ByteDump) {
                    Write-Verbose ("I2C TX byte[{0}]=0x{1:X2} cmd: {2}" -f $byteIdx, $b, (($byteCmd | ForEach-Object { '0x{0:X2}' -f $_ }) -join ' '))
                }

                [uint32]$bwb = 0
                $st = $rawDevice.Write($byteCmd, [uint32]$byteCmd.Length, [ref]$bwb)
                if ([int]$st -ne 0) {
                    throw ("I2C write failed at byte {0}: D2XX status={1}" -f $byteIdx, $st)
                }

                # Read back the ADBUS pin state queued by 0x81
                [byte[]]$ackBuf = [byte[]]::new(1)
                [uint32]$br = 0
                Start-Sleep -Milliseconds 1
                $rawDevice.Read($ackBuf, [uint32]1, [ref]$br)

                if ($br -ne 1) {
                    throw ("I2C ACK timeout at byte {0}: device 0x{1:X2} did not respond" -f $byteIdx, $Address)
                }

                # Bit 1 of ADBUS byte = SDA.  0 = ACK (device held low), 1 = NACK.
                $sdaBit = ($ackBuf[0] -shr 1) -band 0x01

                if ($ByteDump) {
                    $ackLabel = if ($sdaBit -eq 0) { 'ACK' } else { 'NACK' }
                    Write-Verbose ("I2C ACK byte[{0}]: ADBUS=0x{1:X2} SDA={2} ({3})" -f $byteIdx, $ackBuf[0], $sdaBit, $ackLabel)
                }

                if ($sdaBit -ne 0) {
                    $nackPhase = if ($byteIdx -eq 0) { 'address phase' } else { "data byte $byteIdx" }
                    break
                }
            }

            # I2C STOP condition: SCL=0,SDA=0 -> SCL=1 -> SDA=1 while SCL=1
            [byte[]]$stopCmd = @(0x80, 0x00, 0x03, 0x80, 0x01, 0x03, 0x80, 0x03, 0x03)
            [uint32]$bws = 0
            $rawDevice.Write($stopCmd, [uint32]$stopCmd.Length, [ref]$bws) | Out-Null

            if (-not $nackPhase) {
                Write-Verbose ("I2C write OK: Address=0x{0:X2}, {1} data byte(s)" -f $Address, $Data.Length)
            }
            return $true
        } else {
            # Stub mode
            Write-Verbose ("I2C write: Address=0x{0:X2}, {1} bytes (STUB MODE)" -f $Address, $Data.Length)
            return $true
        }

    } catch {
        Write-Error "Failed to send I2C write: $_"
        return $false
    }

    # NACK check outside try/catch so it throws as a terminating error (not caught above).
    # Stop was already sent inside the loop to release the bus before we arrive here.
    if ($nackPhase) {
        $msg = "I2C NACK from device 0x{0:X2} at {1}" -f $Address, $nackPhase
        Write-Verbose $msg
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($msg),
                'I2CWriteNACK',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $Address
            )
        )
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
    $isSharp    = $Connection.PSObject.Properties['IsSharp'] -and $Connection.IsSharp

    if ($isSharp) {
        # FtdiSharp path (PS 5.1 + PS 7 on Windows).
        # [FtdiSharp.Protocols.I2C]::new(device).Scan() returns byte[] of ACK'd addresses.
        Write-Verbose 'I2C scan via FtdiSharp (0x08-0x77)...'
        $i2c = [FtdiSharp.Protocols.I2C]::new($Connection.SharpDevice)
        try {
            $addresses = $i2c.Scan()
            foreach ($addr in $addresses) {
                $found.Add([PSCustomObject]@{
                    PSTypeName = 'PsGadget.I2cDevice'
                    Address    = [int]$addr
                    Hex        = ('0x{0:X2}' -f $addr)
                })
                Write-Verbose ('I2C device found: 0x{0:X2}' -f $addr)
            }
        } finally {
            try { $i2c.Dispose() } catch {}
        }

    } elseif ($gpioMethod -eq 'IoT') {
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

    } elseif (($gpioMethod -eq 'MPSSE' -or $gpioMethod -eq 'MpsseI2c') -and $script:FtdiInitialized) {
        # D2XX path - MPSSE bit-bang I2C scan.
        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $Connection
        if (-not $rawDevice) { throw 'Cannot resolve raw FTDI device handle for MPSSE scan' }

        Write-Verbose "I2C scan via MPSSE bit-bang D2XX (0x08-0x77) at $ClockFrequency Hz..."
        $ok = Initialize-MpsseI2C -DeviceHandle $Connection -ClockFrequency $ClockFrequency
        if (-not $ok) { throw 'Failed to initialize MPSSE I2C for scan' }

        # Purge any stale RX bytes before starting scan
        try { $rawDevice.Purge(2) | Out-Null } catch {}
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
            $writeStatus = $rawDevice.Write($cmd, [uint32]$cmd.Length, [ref]$bw)
            if ([int]$writeStatus -ne 0) { continue }

            # Read 1 byte: ADBUS pin state queued by 0x81.  Bit 1 = SDA.
            # SDA=0 means device held it low => ACK => device present.
            [byte[]]$ackBuf = [byte[]]::new(1)
            [uint32]$br     = 0
            Start-Sleep -Milliseconds 1
            $rawDevice.Read($ackBuf, [uint32]1, [ref]$br)
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