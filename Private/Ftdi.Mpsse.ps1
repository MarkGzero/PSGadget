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
            # Send the command 5 times for signal reliability, matching FtdiSharp GPIO.Write().
            # A single write can occasionally be missed on capacitive or longer traces.
            $lastStatus = $script:FTDI_OK
            for ($i = 0; $i -lt 5; $i++) {
                [uint32]$bytesWritten = 0
                $lastStatus = $rawFtdi.Write($command, $command.Length, [ref]$bytesWritten)
                if ($lastStatus -ne $script:FTDI_OK) { break }
            }

            if ($lastStatus -eq $script:FTDI_OK) {
                Write-Verbose ("MPSSE ACBUS command sent (5x): value=0x{0:X2} dir=0x{1:X2}" -f $Value, $DirectionMask)
                # Update cached ACBUS state - eliminates USB reads from Get-FtdiGpioPins in hot loops
                $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'AcbusCachedState' -Value ([byte]$Value) -Force
                if ($script:PsGadgetTrace) {
                    $script:PsGadgetTrace.Write('GPIO.WRITE',
                        ("ACBUS val=0x{0:X2} dir=0x{1:X2}  (MPSSE x5)" -f $Value, $DirectionMask),
                        ("0x82 0x{0:X2} 0x{1:X2}" -f $Value, $DirectionMask))
                }
                return $true
            } else {
                Write-Warning ("MPSSE ACBUS command failed: status={0}" -f $lastStatus)
                return $false
            }
        } else {
            # Stub mode - simulate successful operation
            Write-Verbose "MPSSE command sent successfully (STUB MODE)"
            if ($script:PsGadgetTrace) {
                $script:PsGadgetTrace.Write('GPIO.WRITE',
                    ("ACBUS val=0x{0:X2} dir=0x{1:X2}  (STUB)" -f $Value, $DirectionMask),
                    ("0x82 0x{0:X2} 0x{1:X2}" -f $Value, $DirectionMask))
            }
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

        # MPSSE command 0x83: Read ACBUS pins.
        # 0x87 (SEND_IMMEDIATE) must follow so the MPSSE engine flushes the
        # result byte to the USB host buffer right away, rather than waiting
        # for the latency timer to expire (matches FtdiSharp Read pattern).
        [byte[]]$command = @(0x83, 0x87)

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

function Initialize-MpsseGpio {
    <#
    .SYNOPSIS
    Initializes FTDI device for MPSSE GPIO (ACBUS) operation.

    .DESCRIPTION
    Runs the MPSSE synchronization handshake and base clock configuration
    required before issuing ACBUS 0x82/0x83 commands. Matches FtdiSharp
    GPIO.FTDI_ConfigureMpsse() exactly, minus the drive-zero mode that is
    only needed for I2C open-drain operation.

    Called automatically by Set-PsGadgetFtdiMode when Mode = 'MPSSE'.

    .PARAMETER DeviceHandle
    Open connection object returned by Connect-PsGadgetFtdi.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or device is not open"
        }

        $rawDevice   = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal      = $script:FtdiInitialized -and ($null -ne $rawDevice)

        if ($isReal) {
            $rawDevice.SetLatency(16) | Out-Null

            $writeCmd = {
                param([byte[]]$cmd, [string]$label)
                [uint32]$bw = 0
                $st = $rawDevice.Write($cmd, [uint32]$cmd.Length, [ref]$bw)
                if ([int]$st -ne 0) { throw "$label failed: status=$st" }
            }

            $rawDevice.Purge(3) | Out-Null
            Start-Sleep -Milliseconds 30

            # MPSSE sync handshake: bad commands 0xAA and 0xAB each echo back 0xFA <cmd>
            [uint32]$sw = 0
            $rawDevice.Write([byte[]](0xAA), 1, [ref]$sw) | Out-Null
            Start-Sleep -Milliseconds 30
            [byte[]]$sb = [byte[]]::new(2); [uint32]$sr = 0
            $rawDevice.Read($sb, 2, [ref]$sr) | Out-Null
            if ($sr -ne 2 -or $sb[0] -ne 0xFA -or $sb[1] -ne 0xAA) {
                throw ("MPSSE GPIO sync failed (0xAA): got {0} bytes: 0x{1:X2} 0x{2:X2}" -f $sr, $sb[0], $sb[1])
            }
            $rawDevice.Write([byte[]](0xAB), 1, [ref]$sw) | Out-Null
            Start-Sleep -Milliseconds 30
            $rawDevice.Read($sb, 2, [ref]$sr) | Out-Null
            if ($sr -ne 2 -or $sb[0] -ne 0xFA -or $sb[1] -ne 0xAB) {
                throw ("MPSSE GPIO sync failed (0xAB): got {0} bytes: 0x{1:X2} 0x{2:X2}" -f $sr, $sb[0], $sb[1])
            }
            Write-Verbose "MPSSE GPIO sync OK"

            # Base config (matches FtdiSharp GPIO.FTDI_ConfigureMpsse, divisor=199 = 100kHz clock):
            #   0x8A  Disable clock divide-by-5 (60 MHz base)
            #   0x97  Turn off adaptive clocking
            #   0x8C  Enable 3-phase data clock
            #   0x86  Set clock divisor (199 = 100 kHz)
            #   0x85  Loopback off
            [byte[]]$cfg = @(0x8A, 0x97, 0x8C, 0x86, 0xC7, 0x00, 0x85)
            & $writeCmd $cfg 'MPSSE GPIO base config'
            Start-Sleep -Milliseconds 30

            # All ADBUS pins to output, all low (matches FtdiSharp GPIO ctor Write(0,0))
            [byte[]]$initPins = @(0x80, 0x00, 0x00)
            for ($i = 0; $i -lt 5; $i++) {
                [uint32]$ibw = 0
                $rawDevice.Write($initPins, [uint32]$initPins.Length, [ref]$ibw) | Out-Null
            }

            Write-Verbose "MPSSE GPIO initialized (all ADBUS pins low/input)"
            if ($script:PsGadgetTrace) {
                $script:PsGadgetTrace.Write('MPSSE.INIT', 'GPIO initialized  sync=OK  ADBUS all-low',
                    '8A 97 8C 86 C7 00 85  +  80 00 00 (x5)')
            }
            return $true
        } else {
            Write-Verbose "MPSSE GPIO initialized (STUB MODE)"
            if ($script:PsGadgetTrace) {
                $script:PsGadgetTrace.Write('MPSSE.INIT', 'GPIO initialized  (STUB)')
            }
            return $true
        }
    } catch {
        Write-Error "Failed to initialize MPSSE GPIO: $_"
        return $false
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
            # Set latency timer small so MPSSE read-backs arrive quickly
            $rawDevice.SetLatency(16) | Out-Null

            # Helper: write bytes to raw device and check status (int 0 = FT_OK)
            $writeCmd = {
                param([byte[]]$cmd, [string]$label)
                [uint32]$bw = 0
                $st = $rawDevice.Write($cmd, [uint32]$cmd.Length, [ref]$bw)
                if ([int]$st -ne 0) { throw "$label failed: status=$st" }
            }

            # Flush stale bytes before sync
            $rawDevice.Purge(3) | Out-Null
            Start-Sleep -Milliseconds 30

            # MPSSE synchronization handshake:
            # Send two deliberately invalid commands (0xAA, 0xAB).
            # The MPSSE echoes back 0xFA <bad-cmd> for each one.
            # If the echo is wrong the engine is not responding correctly.
            [uint32]$syncW = 0
            $rawDevice.Write([byte[]](0xAA), 1, [ref]$syncW) | Out-Null
            Start-Sleep -Milliseconds 30
            [byte[]]$syncBuf = [byte[]]::new(2)
            [uint32]$syncR = 0
            $rawDevice.Read($syncBuf, 2, [ref]$syncR) | Out-Null
            if ($syncR -ne 2 -or $syncBuf[0] -ne 0xFA -or $syncBuf[1] -ne 0xAA) {
                throw ("MPSSE sync failed (0xAA echo): got {0} byte(s): 0x{1:X2} 0x{2:X2}" -f $syncR, $syncBuf[0], $syncBuf[1])
            }
            $rawDevice.Write([byte[]](0xAB), 1, [ref]$syncW) | Out-Null
            Start-Sleep -Milliseconds 30
            $rawDevice.Read($syncBuf, 2, [ref]$syncR) | Out-Null
            if ($syncR -ne 2 -or $syncBuf[0] -ne 0xFA -or $syncBuf[1] -ne 0xAB) {
                throw ("MPSSE sync failed (0xAB echo): got {0} byte(s): 0x{1:X2} 0x{2:X2}" -f $syncR, $syncBuf[0], $syncBuf[1])
            }
            Write-Verbose "MPSSE sync OK"

            # Clock divisor formula with 3-phase clocking enabled (1.5x factor):
            #   f = 60 MHz / ((1 + divisor) * 2 * 1.5) = 60 MHz / ((1 + divisor) * 3)
            #   divisor = 60 MHz / (f * 3) - 1
            # Example: 100 kHz -> divisor = 199
            $clockDivisor = [int][math]::Floor(60000000 / ([double]$ClockFrequency * 3.0) - 1)
            $clockDivisor = [math]::Max(0, [math]::Min(65535, $clockDivisor))

            # I2C MPSSE configuration - sent as a single write for atomicity:
            #   0x8A  Disable clock divide-by-5 (60 MHz base clock)
            #   0x97  Turn off adaptive clocking
            #   0x8C  Enable 3-phase data clocking (REQUIRED for I2C - data valid on both edges)
            #   0x86  Set clock divisor (low byte, high byte follow)
            #   0x85  Loopback off
            #   0x9E  Drive-zero mode enable mask (open-drain on ADBUS bits 0,1,2 = SCL,SDA,DO)
            #   0x80  Set ADBUS direction/value: SCL=1, SDA=1, both output (idle state)
            [byte[]]$i2cConfig = @(
                0x8A,
                0x97,
                0x8C,
                0x86, [byte]($clockDivisor -band 0xFF), [byte](($clockDivisor -shr 8) -band 0xFF),
                0x85,
                0x9E, 0x07, 0x00,
                0x80, 0x03, 0x03
            )
            & $writeCmd $i2cConfig 'I2C config'
            Start-Sleep -Milliseconds 30

            Write-Verbose "I2C initialized at $ClockFrequency Hz (divisor=$clockDivisor, 3-phase+drive-zero enabled)"
            if ($script:PsGadgetTrace) {
                $hexStr = ($i2cConfig | ForEach-Object { $_.ToString('X2') }) -join ' '
                $script:PsGadgetTrace.Write('I2C.INIT',
                    ("clock=${ClockFrequency}Hz  divisor=${clockDivisor}  3phase=on  drive-zero=on"),
                    $hexStr)
            }
            return $true
        } else {
            # Stub mode or no raw device
            Write-Verbose "I2C initialized at $ClockFrequency Hz (STUB MODE)"
            if ($script:PsGadgetTrace) {
                $script:PsGadgetTrace.Write('I2C.INIT', "clock=${ClockFrequency}Hz  (STUB)")
            }
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
    Optimized: address phase uses 1 Write + 1 Read (NACK detection retained);
    data phase uses a single Write for all bytes (no per-byte ACK reads).
    Result: any-length I2C write = 4 USB round-trips instead of N*2.
    
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

            # Pre-build START and STOP byte sequences matching FtdiSharp reference.
            # Multiple repeated transitions ensure signal integrity on slow/capacitive buses.
            #
            # START: 6x idle (SDAhi_SCLhi) -> 6x SDA-falls (SDAlo_SCLhi) ->
            #        6x clock-low (SDAlo_SCLlo) -> 1x SDAhi_SCLlo (ready to clock)
            $startBytes = [System.Collections.Generic.List[byte]]::new()
            for ($i = 0; $i -lt 6; $i++) { $startBytes.AddRange([byte[]](0x80, 0x03, 0x03)) }
            for ($i = 0; $i -lt 6; $i++) { $startBytes.AddRange([byte[]](0x80, 0x01, 0x03)) }
            for ($i = 0; $i -lt 6; $i++) { $startBytes.AddRange([byte[]](0x80, 0x00, 0x03)) }
            $startBytes.AddRange([byte[]](0x80, 0x02, 0x03))
            [byte[]]$startCmd = $startBytes.ToArray()

            # STOP: 6x SDAlo_SCLlo -> 6x SDAlo_SCLhi -> 6x idle (SDAhi_SCLhi)
            $stopBytes = [System.Collections.Generic.List[byte]]::new()
            for ($i = 0; $i -lt 6; $i++) { $stopBytes.AddRange([byte[]](0x80, 0x00, 0x03)) }
            for ($i = 0; $i -lt 6; $i++) { $stopBytes.AddRange([byte[]](0x80, 0x01, 0x03)) }
            for ($i = 0; $i -lt 6; $i++) { $stopBytes.AddRange([byte[]](0x80, 0x03, 0x03)) }
            [byte[]]$stopCmd = $stopBytes.ToArray()

            # Send START
            [uint32]$bw = 0
            $st = $rawDevice.Write($startCmd, [uint32]$startCmd.Length, [ref]$bw)
            if ([int]$st -ne 0) { throw "I2C START failed: D2XX status=$st" }

            # ------------------------------------------------------------------
            # Address phase: 1 Write + 1 Read (ACK check retained for address
            # NACK detection).
            #
            # Per FtdiSharp FTDI_SendByte:
            #   0x11, 0x00, 0x00, $b  - MSB_FALLING_EDGE_CLOCK_BYTE_OUT (1 byte, length-1=0)
            #   0x80, 0x02, 0x03      - release SDA high (SDAhi_SCLlo) ready for ACK clock
            #   0x22, 0x00            - MSB_RISING_EDGE_CLOCK_BIT_IN (1 bit, length-1=0)
            #   0x87                  - SEND_IMMEDIATE: flush MPSSE RX buffer to host now
            # Read back 1 byte: bit 0 = ACK bit.  0=ACK (device held SDA low), 1=NACK.
            # ------------------------------------------------------------------
            [byte]$addrByte = [byte](($Address -shl 1) -bor 0x00)   # 7-bit addr + R/W=0 (write)
            [byte[]]$addrCmd = @(
                0x11, 0x00, 0x00, $addrByte,  # clock address byte out, MSB-first, falling edge
                0x80, 0x02, 0x03,              # release SDA high (SDAhi_SCLlo) before ACK
                0x22, 0x00,                    # clock in 1 ACK bit, rising edge
                0x87                           # SEND_IMMEDIATE
            )

            if ($ByteDump) {
                Write-Verbose ("I2C TX addr=0x{0:X2} (wire=0x{1:X2})" -f $Address, $addrByte)
            }

            [uint32]$bwa = 0
            $st = $rawDevice.Write($addrCmd, [uint32]$addrCmd.Length, [ref]$bwa)
            if ([int]$st -ne 0) { throw "I2C address byte write failed: D2XX status=$st" }

            [byte[]]$ackBuf = [byte[]]::new(1)
            [uint32]$bra = 0
            $rawDevice.Read($ackBuf, [uint32]1, [ref]$bra) | Out-Null

            if ($bra -ne 1 -or ($ackBuf[0] -band 0x01) -ne 0) {
                $nackPhase = 'address phase'
            }

            if ($ByteDump -and $bra -eq 1) {
                $ackLabel = if (($ackBuf[0] -band 0x01) -eq 0) { 'ACK' } else { 'NACK' }
                Write-Verbose ("I2C addr ACK: raw=0x{0:X2} ({1})" -f $ackBuf[0], $ackLabel)
            }

            if (-not $nackPhase) {
                # ------------------------------------------------------------------
                # Data phase: build all data byte MPSSE commands in one buffer and
                # issue a SINGLE $rawDevice.Write() call for the entire payload.
                # Per-byte ACK reads are skipped - SSD1306 always ACKs data bytes,
                # and polling the RX buffer per byte is the dominant latency source.
                # ------------------------------------------------------------------
                $dataBuf = [System.Collections.Generic.List[byte]]::new($Data.Length * 13 + 1)
                foreach ($b in $Data) {
                    # 0x11,0x00,0x00,$b: MSB_FALLING_EDGE_CLOCK_BYTE_OUT, 1 byte (length-1=0)
                    $dataBuf.AddRange([byte[]](0x11, 0x00, 0x00, $b))
                    # 9th ACK clock: release SDA then pulse SCL once.
                    # SDA is driven high (master owns the bus, slave ACK/NACK is ignored).
                    # Without this clock pulse the slave expects one more edge before it
                    # latches the byte; the next 0x11 byte's first edge is consumed as the
                    # ACK clock and all subsequent bytes are misaligned by 1 bit.
                    $dataBuf.AddRange([byte[]](0x80, 0x02, 0x03))  # SDA=hi, SCL=lo (release SDA)
                    $dataBuf.AddRange([byte[]](0x80, 0x03, 0x03))  # SDA=hi, SCL=hi (ACK clock hi)
                    $dataBuf.AddRange([byte[]](0x80, 0x02, 0x03))  # SDA=hi, SCL=lo (ACK clock lo)
                }
                $dataBuf.Add([byte]0x87)   # SEND_IMMEDIATE: flush entire payload

                if ($ByteDump) {
                    Write-Verbose ("I2C TX data: {0} byte(s)" -f $Data.Length)
                }

                [byte[]]$dataCmd = $dataBuf.ToArray()
                [uint32]$bwd = 0
                $st = $rawDevice.Write($dataCmd, [uint32]$dataCmd.Length, [ref]$bwd)
                if ([int]$st -ne 0) {
                    throw ("I2C data phase write failed: D2XX status={0}" -f $st)
                }
            }

            # Send STOP unconditionally to release the bus
            [uint32]$bws = 0
            $rawDevice.Write($stopCmd, [uint32]$stopCmd.Length, [ref]$bws) | Out-Null

            if (-not $nackPhase) {
                Write-Verbose ("I2C write OK: Address=0x{0:X2}, {1} data byte(s)" -f $Address, $Data.Length)
                if ($script:PsGadgetTrace) {
                    $hexStr = $script:PsGadgetTrace.FormatHex($Data)
                    $script:PsGadgetTrace.Write('I2C.WRITE',
                        ("addr=0x{0:X2}  {1}B  wire=0x{2:X2}" -f $Address, $Data.Length, (($Address -shl 1) -bor 0x00)),
                        $hexStr)
                }
            }
            return $true
        } else {
            # Stub mode
            Write-Verbose ("I2C write: Address=0x{0:X2}, {1} bytes (STUB MODE)" -f $Address, $Data.Length)
            if ($script:PsGadgetTrace) {
                $hexStr = $script:PsGadgetTrace.FormatHex($Data)
                $script:PsGadgetTrace.Write('I2C.WRITE',
                    ("addr=0x{0:X2}  {1}B  (STUB)" -f $Address, $Data.Length),
                    $hexStr)
            }
            return $true
        }

    } catch {
        Write-Error "Failed to send I2C write: $_"
        return $false
    }

    # NACK check outside try/catch so it throws as a terminating error (not caught above).
    # Stop was already sent inside the block to release the bus before we arrive here.
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

    } elseif (($gpioMethod -eq 'MPSSE' -or $gpioMethod -eq 'MpsseI2c') -and $script:FtdiInitialized) {
        # D2XX path - MPSSE bit-bang I2C scan.
        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $Connection
        if (-not $rawDevice) { throw 'Cannot resolve raw FTDI device handle for MPSSE scan' }

        Write-Verbose "I2C scan via MPSSE D2XX (0x08-0x77) at $ClockFrequency Hz..."
        $ok = Initialize-MpsseI2C -DeviceHandle $Connection -ClockFrequency $ClockFrequency
        if (-not $ok) { throw 'Failed to initialize MPSSE I2C for scan' }

        # Purge any stale RX bytes before starting scan
        try { $rawDevice.Purge(2) | Out-Null } catch {}
        Start-Sleep -Milliseconds 30

        # Pre-build START and STOP sequences (repeated transitions for signal integrity,
        # matching FtdiSharp reference implementation).
        #
        # Constants (ADBUS low-byte set command = 0x80):
        #   0x03 = SDAhi_SCLhi  (idle)
        #   0x01 = SDAlo_SCLhi  (start condition - SDA falls while SCL high)
        #   0x00 = SDAlo_SCLlo
        #   0x02 = SDAhi_SCLlo
        #
        # START: 6x idle -> 6x SDA-falls -> 6x clock-low -> 1x SDAhi_SCLlo (ready to clock)
        $startBytes = [System.Collections.Generic.List[byte]]::new()
        for ($i = 0; $i -lt 6; $i++) { $startBytes.AddRange([byte[]](0x80, 0x03, 0x03)) }
        for ($i = 0; $i -lt 6; $i++) { $startBytes.AddRange([byte[]](0x80, 0x01, 0x03)) }
        for ($i = 0; $i -lt 6; $i++) { $startBytes.AddRange([byte[]](0x80, 0x00, 0x03)) }
        $startBytes.AddRange([byte[]](0x80, 0x02, 0x03))
        [byte[]]$startCmd = $startBytes.ToArray()

        # STOP: 6x SDAlo_SCLlo -> 6x SDAlo_SCLhi -> 6x idle
        $stopBytes = [System.Collections.Generic.List[byte]]::new()
        for ($i = 0; $i -lt 6; $i++) { $stopBytes.AddRange([byte[]](0x80, 0x00, 0x03)) }
        for ($i = 0; $i -lt 6; $i++) { $stopBytes.AddRange([byte[]](0x80, 0x01, 0x03)) }
        for ($i = 0; $i -lt 6; $i++) { $stopBytes.AddRange([byte[]](0x80, 0x03, 0x03)) }
        [byte[]]$stopCmd = $stopBytes.ToArray()

        for ($addr = 0x08; $addr -le 0x77; $addr++) {
            # Use read probe (R/W=1): matches FtdiSharp Scan() which calls FTDI_CommandRead.
            $addrByte = [byte](($addr -shl 1) -bor 0x01)

            # Send START
            [uint32]$bw = 0
            $rawDevice.Write($startCmd, [uint32]$startCmd.Length, [ref]$bw) | Out-Null

            # Clock out address byte using byte-mode falling-edge command (0x11):
            #   0x11 = MSB_FALLING_EDGE_CLOCK_BYTE_OUT
            #   0x00, 0x00 = length-1 (0 = 1 byte)
            # Then release SDA high (0x80, 0x02, 0x03) before the ACK clock.
            # Clock in 1 ACK bit on rising edge (0x22, 0x00).
            # 0x87 = SEND_IMMEDIATE: flush MPSSE result buffer to host now.
            [byte[]]$byteCmd = @(
                0x11, 0x00, 0x00, $addrByte,   # clock byte out, falling edge, MSB first
                0x80, 0x02, 0x03,               # release SDA (SDAhi_SCLlo) before ACK
                0x22, 0x00,                     # clock in 1 ACK bit, rising edge
                0x87                            # SEND_IMMEDIATE
            )
            [uint32]$bwb = 0
            $rawDevice.Write($byteCmd, [uint32]$byteCmd.Length, [ref]$bwb) | Out-Null

            # Read back the 1 ACK bit clocked in by 0x22.
            # Bit 0 of the byte = 0 -> ACK (device held SDA low) -> device present.
            [byte[]]$ackBuf = [byte[]]::new(1)
            [uint32]$br     = 0
            Start-Sleep -Milliseconds 2
            $rawDevice.Read($ackBuf, [uint32]1, [ref]$br) | Out-Null

            # Send STOP unconditionally to release the bus
            [uint32]$bws = 0
            $rawDevice.Write($stopCmd, [uint32]$stopCmd.Length, [ref]$bws) | Out-Null

            if ($br -eq 1 -and (($ackBuf[0] -band 0x01) -eq 0)) {
                $found.Add([PSCustomObject]@{
                    PSTypeName = 'PsGadget.I2cDevice'
                    Address    = $addr
                    Hex        = ('0x{0:X2}' -f $addr)
                })
                Write-Verbose ('I2C device found: 0x{0:X2}' -f $addr)
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