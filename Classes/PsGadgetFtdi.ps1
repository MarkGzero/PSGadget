# PsGadgetFtdi Class
# Represents an FTDI device connection with automatic logging.
# Delegates to Connect-PsGadgetFtdi and Set-PsGadgetGpio public functions.

class PsGadgetFtdi {
    [int]$Index
    [string]$SerialNumber
    [string]$LocationId
    [string]$Description
    [string]$Type
    [string]$GpioMethod
    [bool]$IsOpen
    [PsGadgetLogger]$Logger
    hidden [object]$_connection = $null

    # Constructor - connect by serial number (preferred)
    PsGadgetFtdi([string]$SerialNumber) {
        $this.SerialNumber = $SerialNumber
        $this.LocationId   = ''
        $this.Index        = -1
        $this.IsOpen       = $false
        $this.Description  = "FTDI $SerialNumber"
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
        }
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
        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            throw "ResetDevice failed: $status"
        }
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
        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            throw "CyclePort failed: $status"
        }
        $this.Logger.WriteInfo("USB port cycled - device will re-enumerate. Call Connect() to reopen.")
    }
}