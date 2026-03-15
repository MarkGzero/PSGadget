# PsGadgetFtdi Class
# Represents an FTDI device connection with automatic logging.
# Delegates to Connect-PsGadgetFtdi and Set-PsGadgetGpio public functions.

class PsGadgetFtdi : System.IDisposable {
    [int]$Index
    [string]$SerialNumber
    [string]$LocationId
    [string]$Description
    [string]$Type
    [string]$GpioMethod
    [bool]$IsOpen
    [PsGadgetLogger]$Logger
    hidden [object]$_connection  = $null
    hidden [object]$_display     = $null
    # Keyed by "ModuleName:HexAddress" (e.g. "PCA9685:40").
    # Stores initialized I2C device objects so re-calls skip construction + hardware init.
    hidden [hashtable]$_i2cDevices = $null

    # SSD1306 display height (32 or 64 pixels).  Set before first GetDisplay() call.
    # Writable via New-PsGadgetFtdi -DisplayHeight 32 or directly: $dev.DisplayHeight = 32
    [int]$DisplayHeight = 64

    # Stepper motor calibration.
    # 0.0 = use mode-appropriate default from Get-PsGadgetStepperDefaultStepsPerRev:
    #   Half: ~4075.77  Full: ~2037.89  (28BYJ-48 empirical, NOT 2048/4096)
    # Set to your measured value:  $dev.StepsPerRevolution = 4082.5
    [double]$StepsPerRevolution = 0.0
    # Default step mode for .Step() and .StepDegrees() shorthand calls.
    [string]$DefaultStepMode    = 'Half'

    # Constructor - connect by serial number (preferred)
    PsGadgetFtdi([string]$SerialNumber) {
        $this.SerialNumber = $SerialNumber
        $this.LocationId   = ''
        $this.Index        = -1
        $this.IsOpen       = $false
        $this.Description  = "FTDI $SerialNumber"
        $this._i2cDevices  = @{}
        $this.Logger = [PsGadgetLogger]::new()
        $this.Logger.WriteInfo("PsGadgetFtdi created for serial: $SerialNumber")
    }

    # Constructor - connect by device index
    PsGadgetFtdi([int]$DeviceIndex) {
        $this.Index        = $DeviceIndex
        $this.SerialNumber = ''
        $this.LocationId   = ''
        $this.IsOpen       = $false
        $this.Description  = "FTDI device index $DeviceIndex"
        $this._i2cDevices  = @{}
        $this.Logger = [PsGadgetLogger]::new()
        $this.Logger.WriteInfo("PsGadgetFtdi created for index: $DeviceIndex")
    }

    # Open the device connection.
    # Calls the exported Connect-PsGadgetFtdi function and stores the connection object.
    [void] Connect() {
        if ($this.IsOpen) {
            $this.Logger.WriteInfo("Device already open: $($this.SerialNumber)$($this.Index)")
            return
        }

        $this.Logger.WriteInfo("Connecting to FTDI device...")

        try {
            $conn = $null
            if ($this.LocationId -ne '') {
                $conn = Connect-PsGadgetFtdi -LocationId $this.LocationId
            } elseif ($this.SerialNumber -ne '') {
                $conn = Connect-PsGadgetFtdi -SerialNumber $this.SerialNumber
            } else {
                $conn = Connect-PsGadgetFtdi -Index $this.Index
            }

            if (-not $conn) {
                throw "Connect-PsGadgetFtdi returned null"
            }

            $this._connection  = $conn
            $this.IsOpen       = $true
            $this.Type         = $conn.Type
            $this.GpioMethod   = $conn.GpioMethod
            $this.Description  = $conn.Description
            if ($this.SerialNumber -eq '') { $this.SerialNumber = $conn.SerialNumber }
            if ($this.Index -lt 0)         { $this.Index        = $conn.Index }

            $this.Logger.WriteInfo("Connected: $($this.Description) ($($this.SerialNumber)) Type=$($this.Type) GPIO=$($this.GpioMethod)")
        } catch {
            $this.Logger.WriteError("Connect failed: $($_.Exception.Message)")
            throw
        }
    }

    # Close the device connection.
    [void] Close() {
        if (-not $this.IsOpen) {
            $this.Logger.WriteInfo("Close called but device is not open")
            return
        }

        $this.Logger.WriteInfo("Closing FTDI device: $($this.SerialNumber)")

        try {
            if ($this._connection -and $this._connection.Close) {
                $this._connection.Close()
            }
        } catch {
            $this.Logger.WriteError("Close error: $($_.Exception.Message)")
        } finally {
            $this.IsOpen      = $false
            $this._connection = $null
            $this._i2cDevices = @{}   # drop cached I2C device objects; stale on reconnect
        }
    }

    # IDisposable.Dispose() - enables try/finally and 'using' patterns.
    # Guarantees the D2XX handle is released even if the script errors mid-run.
    [void] Dispose() {
        $this.Logger.WriteInfo("Dispose()")
        $this.Close()
    }

    # Set a single GPIO pin by name: "HIGH"/"LOW"/"H"/"L"/"1"/"0"
    [void] SetPin([int]$Pin, [string]$State) {
        $this.Logger.WriteTrace("SetPin($Pin, $State)")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        Set-PsGadgetGpio -Connection $this._connection -Pins @($Pin) -State $State
    }

    # Set a single GPIO pin by boolean (true = HIGH, false = LOW)
    [void] SetPin([int]$Pin, [bool]$High) {
        $state = if ($High) { 'HIGH' } else { 'LOW' }
        $this.SetPin($Pin, $state)
    }

    # Set the baud rate on an open connection (useful for async bit-bang timing)
    [void] SetBaudRate([uint32]$BaudRate) {
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        if (-not $this._connection -or -not ($this._connection | Get-Member -Name SetBaudRate -MemberType Method -ErrorAction SilentlyContinue)) {
            throw "Underlying connection object does not support SetBaudRate"
        }
        $status = $this._connection.SetBaudRate($BaudRate)
        if ($status -ne 0) {
            throw "SetBaudRate failed with status $status"
        }
    }

    # Set multiple GPIO pins simultaneously
    [void] SetPins([int[]]$Pins, [string]$State) {
        $this.Logger.WriteTrace("SetPins([$($Pins -join ',')] $State)")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        Set-PsGadgetGpio -Connection $this._connection -Pins $Pins -State $State
    }

    # Set multiple GPIO pins by boolean
    [void] SetPins([int[]]$Pins, [bool]$High) {
        $state = if ($High) { 'HIGH' } else { 'LOW' }
        $this.SetPins($Pins, $state)
    }

    # Pulse a pin: set to State for DurationMs then invert
    [void] PulsePin([int]$Pin, [string]$State, [int]$DurationMs) {
        $this.Logger.WriteTrace("PulsePin($Pin, $State, ${DurationMs}ms)")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        Set-PsGadgetGpio -Connection $this._connection -Pins @($Pin) -State $State -DurationMs $DurationMs
    }

    # Write raw bytes to the device
    [void] Write([byte[]]$Data) {
        $this.Logger.WriteTrace("Write $($Data.Length) bytes")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        if (-not $this._connection -or -not $this._connection.Device) {
            throw [System.InvalidOperationException]::new("No underlying device handle available")
        }
        [uint32]$written = 0
        $status = $this._connection.Device.Write($Data, [uint32]$Data.Length, [ref]$written)
        $this.Logger.WriteInfo("Write $written/$($Data.Length) bytes status=$status")
    }

    # Read raw bytes from the device
    [byte[]] Read([int]$Count) {
        $this.Logger.WriteTrace("Read $Count bytes")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        if (-not $this._connection -or -not $this._connection.Device) {
            throw [System.InvalidOperationException]::new("No underlying device handle available")
        }
        $buf = [byte[]]::new($Count)
        [uint32]$bytesRead = 0
        $status = $this._connection.Device.Read($buf, [uint32]$Count, [ref]$bytesRead)
        $this.Logger.WriteInfo("Read $bytesRead/$Count bytes status=$status")
        if ($bytesRead -lt $Count) {
            $trimmed = [byte[]]::new($bytesRead)
            [System.Array]::Copy($buf, $trimmed, $bytesRead)
            return $trimmed
        }
        return $buf
    }

    # Soft reset - clears internal buffers and resets chip state, handle stays open
    [void] Reset() {
        $this.Logger.WriteInfo("Reset()")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        if (-not $this._connection -or -not $this._connection.Device) {
            throw [System.InvalidOperationException]::new("No underlying device handle available")
        }
        $status = $this._connection.Device.ResetDevice()
        $this.Logger.WriteInfo("ResetDevice status=$status")
        if ([int]$status -ne 0) {
            throw "ResetDevice failed: $status"
        }
    }

    # GetDisplay() - returns the cached PsGadgetSsd1306 object, lazily initializing it on first call.
    # Use this to access advanced formatting options (Align, FontSize, Invert) that Display() does not expose.
    # The same object is reused by Display() and ClearDisplay() -- no double-init conflicts.
    #
    # Usage:
    #   $d = $dev.GetDisplay()
    #   $d.WriteText("Clock", 0, 'center', 2, $false)
    #   $d.ClearPage(0)
    [PsGadgetSsd1306] GetDisplay() {
        return $this.GetDisplay(0x3C, $this.DisplayHeight)
    }

    [PsGadgetSsd1306] GetDisplay([byte]$Address) {
        return $this.GetDisplay($Address, $this.DisplayHeight)
    }

    [PsGadgetSsd1306] GetDisplay([byte]$Address, [int]$Height) {
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new('Device not open. Call Connect() first.')
        }
        # Invalidate cached display if height changed (e.g. caller corrects after first use).
        if ($this._display -and $this._display.IsInitialized -and $this._display.Height -ne $Height) {
            $this.Logger.WriteInfo("DisplayHeight changed ($($this._display.Height) -> $Height): reinitializing SSD1306")
            $this._display = $null
        }
        if (-not $this._display -or -not $this._display.IsInitialized) {
            Write-Host "GetDisplay: initializing SSD1306 0x$($Address.ToString('X2')) height=${Height}px. Default is 128x64 — use New-PsGadgetFtdi -DisplayHeight 32 for 128x32 modules."
            $ssd = [PsGadgetSsd1306]::new($this._connection, $Address, $Height)
            $ssd.Initialize($false) | Out-Null
            if (-not $ssd.IsInitialized) {
                throw [System.InvalidOperationException]::new('Failed to initialize SSD1306 display at 0x' + $Address.ToString('X2'))
            }
            $this._display = $ssd
        }
        return $this._display
    }

    # Display() - write text to the SSD1306 OLED (left-aligned, FontSize 1).
    # For alignment/FontSize/Invert use $dev.GetDisplay() then call .WriteText() directly.
    [void] Display([string]$Text) {
        $this.Display($Text, 0, 0x3C)
    }

    [void] Display([string]$Text, [int]$Page) {
        $this.Display($Text, $Page, 0x3C)
    }

    [void] Display([string]$Text, [int]$Page, [byte]$Address) {
        $this.Logger.WriteTrace("Display('$Text', page=$Page, addr=0x$($Address.ToString('X2')))")
        $this.GetDisplay($Address).WriteText($Text, $Page, 'left', 1, $false) | Out-Null
    }

    # ClearDisplay() - clear all pages or a single page.
    [void] ClearDisplay() {
        $this.ClearDisplay(-1, 0x3C)
    }

    [void] ClearDisplay([int]$Page) {
        $this.ClearDisplay($Page, 0x3C)
    }

    [void] ClearDisplay([int]$Page, [byte]$Address) {
        $this.Logger.WriteTrace("ClearDisplay(page=$Page, addr=0x$($Address.ToString('X2')))")
        if ($Page -ge 0) {
            $this.GetDisplay($Address).ClearPage($Page) | Out-Null
        } else {
            $this.GetDisplay($Address).Clear() | Out-Null
        }
    }

    # Scan for I2C devices on the bus (0x08 to 0x77).
    # Requires an MPSSE-capable device (FT232H) and an open connection.
    # IoT backend uses .NET IoT I2cBus; D2XX backend uses MPSSE bit-bang.
    # Returns an array of [PSCustomObject]@{ Address; Hex } for each ACK.
    [System.Object[]] ScanI2CBus() {
        $this.Logger.WriteInfo('ScanI2CBus() - I2C bus scan 0x08-0x77')
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new('Device not open. Call Connect() first.')
        }
        if ($this.GpioMethod -notin @('MPSSE', 'IoT', '')) {
            throw [System.InvalidOperationException]::new(
                "I2C scan requires an MPSSE device (FT232H). This device uses GpioMethod=$($this.GpioMethod).")
        }
        $devices = Invoke-FtdiI2CScan -Connection $this._connection
        $this.Logger.WriteInfo("ScanI2CBus() found $($devices.Count) device(s)")
        return $devices
    }

    # USB port cycle - equivalent to physically unplugging and replugging the device.
    # Triggers re-enumeration so EEPROM changes (e.g. CBUS mode) take effect without
    # a manual replug. D2XX automatically closes the handle after CyclePort succeeds.
    # Call Connect() again after this to reopen.
    [void] CyclePort() {
        $this.Logger.WriteInfo("CyclePort()")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        if (-not $this._connection -or -not $this._connection.Device) {
            throw [System.InvalidOperationException]::new("No underlying device handle available")
        }
        # CyclePort calls FT_Close internally on success - mark as closed regardless
        $status = $this._connection.Device.CyclePort()
        $this.IsOpen       = $false
        $this._connection  = $null
        $this.Logger.WriteInfo("CyclePort status=$status (handle released)")
        if ([int]$status -ne 0) {
            throw "CyclePort failed: $status"
        }
        $this.Logger.WriteInfo("USB port cycled - device will re-enumerate. Call Connect() to reopen.")
    }

    # ---------------------------------------------------------------------------
    # Stepper motor shorthand methods.
    # Delegates to Invoke-PsGadgetStepperMove (Private/Stepper.Backend.ps1).
    #
    # StepsPerRevolution and DefaultStepMode are instance properties so the
    # same device object can be calibrated once and reused across many calls:
    #   $dev.StepsPerRevolution = 4082.5
    #   $dev.DefaultStepMode    = 'Half'
    #   $dev.StepDegrees(90)
    # ---------------------------------------------------------------------------

    # Step() - move N individual step pulses.
    [void] Step([int]$Steps) {
        $this._Step($Steps, 'Forward', $this.DefaultStepMode, 2, 0x0F)
    }
    [void] Step([int]$Steps, [string]$Direction) {
        $this._Step($Steps, $Direction, $this.DefaultStepMode, 2, 0x0F)
    }
    [void] Step([int]$Steps, [string]$Direction, [string]$StepMode) {
        $this._Step($Steps, $Direction, $StepMode, 2, 0x0F)
    }
    [void] Step([int]$Steps, [string]$Direction, [string]$StepMode, [int]$DelayMs) {
        $this._Step($Steps, $Direction, $StepMode, $DelayMs, 0x0F)
    }
    # Full overload: explicit PinMask.
    [void] Step([int]$Steps, [string]$Direction, [string]$StepMode, [int]$DelayMs, [byte]$PinMask) {
        $this._Step($Steps, $Direction, $StepMode, $DelayMs, $PinMask)
    }
    hidden [void] _Step([int]$Steps, [string]$Direction, [string]$StepMode, [int]$DelayMs, [byte]$PinMask) {
        $this.Logger.WriteTrace("Step($Steps, $Direction, $StepMode, delay=${DelayMs}ms)")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        Invoke-PsGadgetStepperMove -Ftdi $this -Steps $Steps -Direction $Direction `
            -StepMode $StepMode -DelayMs $DelayMs -PinMask $PinMask
    }

    # StepDegrees() - rotate by angle using StepsPerRevolution calibration.
    # Uses $this.StepsPerRevolution if set (>0); otherwise falls back to
    # Get-PsGadgetStepperDefaultStepsPerRev for the active step mode.
    [void] StepDegrees([double]$Degrees) {
        $this._StepDegrees($Degrees, 'Forward', $this.DefaultStepMode, 2, 0x0F, $this.StepsPerRevolution)
    }
    [void] StepDegrees([double]$Degrees, [string]$Direction) {
        $this._StepDegrees($Degrees, $Direction, $this.DefaultStepMode, 2, 0x0F, $this.StepsPerRevolution)
    }
    [void] StepDegrees([double]$Degrees, [string]$Direction, [string]$StepMode) {
        $this._StepDegrees($Degrees, $Direction, $StepMode, 2, 0x0F, $this.StepsPerRevolution)
    }
    # Full overload: explicit calibration override.
    [void] StepDegrees([double]$Degrees, [string]$Direction, [string]$StepMode, [double]$StepsPerRevolution) {
        $this._StepDegrees($Degrees, $Direction, $StepMode, 2, 0x0F, $StepsPerRevolution)
    }
    hidden [void] _StepDegrees([double]$Degrees, [string]$Direction, [string]$StepMode, [int]$DelayMs, [byte]$PinMask, [double]$StepsPerRevolution) {
        $this.Logger.WriteTrace("StepDegrees($Degrees, $Direction, $StepMode, spr=$StepsPerRevolution)")
        if (-not $this.IsOpen) {
            throw [System.InvalidOperationException]::new("Device not open. Call Connect() first.")
        }
        $spr = if ($StepsPerRevolution -gt 0.0) {
            $StepsPerRevolution
        } else {
            Get-PsGadgetStepperDefaultStepsPerRev -StepMode $StepMode
        }
        $steps = [Math]::Max(1, [int][Math]::Round($Degrees / 360.0 * $spr))
        $this.Logger.WriteInfo("StepDegrees: $Degrees deg -> $steps steps (spr=$spr, mode=$StepMode)")
        Invoke-PsGadgetStepperMove -Ftdi $this -Steps $steps -Direction $Direction `
            -StepMode $StepMode -DelayMs $DelayMs -PinMask $PinMask
    }
}