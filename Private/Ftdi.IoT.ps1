# Ftdi.IoT.ps1
# .NET IoT library backend for FTDI devices (PS 7.4+ / .NET 8+)
# Uses System.Device.Gpio and Iot.Device.Bindings for platform-agnostic hardware access.
#
# When $script:IotBackendAvailable is $true (set by Initialize-FtdiAssembly),
# this backend is used automatically in place of Ftdi.Windows.ps1 / Ftdi.Unix.ps1.
# Users never need to know or care which backend is running -- the public API is identical.
#
# MPSSE devices (FT232H, FT2232H, FT4232H, FT232HP): fully handled by IoT Ft232HDevice.
# CBUS devices (FT232R):  enumerated by IoT, but opened via FTD2XX_NET fallback on Windows.
# Pin mapping (FT232H ACBUS):
#   PsGadget user pin 0-7  ->  ACBUS0-7  ->  IoT GpioController pin 8-15 (C0-C7)
#   ADBUS0-7 (SPI/I2C/JTAG lines) are IoT pins 0-7 and are not used for GPIO here.

function Invoke-FtdiIotEnumerate {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()

    try {
        Write-Verbose "Enumerating FTDI devices via IoT FtCommon.GetDevices()..."
        $rawDevices = [Iot.Device.FtCommon.FtCommon]::GetDevices()

        if (-not $rawDevices -or $rawDevices.Count -eq 0) {
            Write-Verbose "No FTDI devices found via IoT backend"
            return @()
        }

        Write-Verbose "IoT FtCommon found $($rawDevices.Count) device(s)"

        $isWindows     = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
        $driverLabel   = if ($isWindows) { 'ftd2xx.dll (IoT)' } else { 'libftdi (IoT)' }
        $platformLabel = if ($isWindows) { 'Windows' }          else { 'Unix'           }

        # Map FtDeviceType integer value to PsGadget friendly chip name.
        # Integer comparison avoids PowerShell enum comparison quirks.
        $enrichedDevices = @()

        for ($i = 0; $i -lt $rawDevices.Count; $i++) {
            $d = $rawDevices[$i]

            $typeName = switch ([int]$d.Type) {
                0  { 'FT232BM'     }   # Ft232BOrFt245B
                1  { 'FT232AM'     }   # Ft8U232AmOrFTtU245Am
                2  { 'FT100AX'     }   # Ft8U100Ax
                4  { 'FT2232C'     }   # Ft2232
                5  { 'FT232R'      }   # Ft232ROrFt245R
                6  { 'FT2232H'     }   # Ft2232H
                7  { 'FT4232H'     }   # Ft4232H
                8  { 'FT232H'      }   # Ft232H
                9  { 'FT-X Series' }   # FtXSeries
                17 { 'FT2233HP'    }   # Ft2233HP
                18 { 'FT4233HP'    }   # Ft4233HP
                19 { 'FT2232HP'    }   # Ft2232HP
                20 { 'FT4232HP'    }   # Ft4232HP
                21 { 'FT233HP'     }   # Ft233HP
                22 { 'FT232HP'     }   # Ft232HP
                23 { 'FT2232HA'    }   # Ft2232HA
                24 { 'FT4232HA'    }   # Ft4232HA
                default { $d.Type.ToString() }
            }

            # PortOpened flag value = 1
            $isOpen = ([int]$d.Flags -band 1) -ne 0

            $caps = Get-FtdiChipCapabilities -TypeName $typeName

            $enriched = [PSCustomObject]@{
                Index          = $i
                Type           = $typeName
                Description    = $d.Description
                SerialNumber   = $d.SerialNumber
                LocationId     = $d.LocId
                IsOpen         = $isOpen
                Flags          = '0x{0:X8}' -f [int]$d.Flags
                DeviceId       = '0x{0:X8}' -f [uint32]$d.Id
                Handle         = $null
                Driver         = $driverLabel
                Platform       = $platformLabel
                IsVcp          = $false           # IoT FtCommon only surfaces D2XX-accessible devices
                GpioMethod     = $caps.GpioMethod
                GpioPins       = $caps.GpioPins
                HasMpsse       = $caps.HasMpsse
                CapabilityNote = $caps.CapabilityNote
                RawFtDevice    = $d               # preserved for Invoke-FtdiIotOpen
            }

            $enrichedDevices += $enriched
        }

        return $enrichedDevices

    } catch {
        Write-Verbose "IoT FTDI enumeration failed: $($_.Exception.Message)"
        throw
    }
}

function Invoke-FtdiIotOpen {
    # Open an FTDI device using the .NET IoT Ft232HDevice class.
    # MPSSE devices (FT232H family): opened via Ft232HDevice with GpioController.
    # CBUS devices (FT232R): falls back to FTD2XX_NET on Windows (no IoT support for CBUS).
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DeviceInfo
    )

    try {
        # CBUS devices (FT232R, FT-X) are not supported by the IoT Ft232HDevice class.
        # On Windows with FTD2XX_NET loaded: fall back to the D2XX path.
        # On Unix with native P/Invoke loaded: delegate to Invoke-FtdiUnixOpen.
        # Otherwise: throw so Connect-PsGadgetFtdi can create an appropriate stub.
        if (-not $DeviceInfo.HasMpsse) {
            $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
            if ($isWindows -and $script:D2xxLoaded) {
                Write-Verbose "$($DeviceInfo.Type) is a CBUS device; using FTD2XX_NET backend to open"
                return Invoke-FtdiWindowsOpen -DeviceInfo $DeviceInfo
            }
            if (-not $isWindows -and $script:FtdiNativeAvailable) {
                Write-Verbose "$($DeviceInfo.Type) is a CBUS device; using native P/Invoke backend on Unix"
                return Invoke-FtdiUnixOpen -Index $DeviceInfo.Index
            }
            throw [System.NotImplementedException]::new(
                "$($DeviceInfo.Type) uses CBUS GPIO, which requires the FTD2XX_NET backend. " +
                "On Windows, install the FTDI CDM driver package (includes ftd2xx.dll). " +
                "On Linux/macOS with libftd2xx.so installed and loaded, this should work via " +
                "native P/Invoke -- ensure Initialize-FtdiNative ran successfully.")
        }

        # Obtain the raw IoT FtDevice object.
        # Normally stamped by Invoke-FtdiIotEnumerate; if missing (caller built their own device
        # info object) re-enumerate to get a fresh FtDevice.
        $rawFtDevice = $null
        if ($DeviceInfo.PSObject.Properties['RawFtDevice'] -and $DeviceInfo.RawFtDevice) {
            $rawFtDevice = $DeviceInfo.RawFtDevice
        } else {
            Write-Verbose "RawFtDevice missing; re-enumerating to locate $($DeviceInfo.SerialNumber)..."
            $allDevices  = [Iot.Device.FtCommon.FtCommon]::GetDevices()
            $rawFtDevice = $allDevices | Where-Object { $_.SerialNumber -eq $DeviceInfo.SerialNumber } |
                           Select-Object -First 1
        }

        if (-not $rawFtDevice) {
            throw "Could not locate an IoT FtDevice for serial number '$($DeviceInfo.SerialNumber)'. " +
                  "Try re-running List-PsGadgetFtdi and connecting again."
        }

        Write-Verbose "Opening $($DeviceInfo.Type) via IoT Ft232HDevice: $($DeviceInfo.Description)"

        $ft232h        = [Iot.Device.Ft232H.Ft232HDevice]::new($rawFtDevice)
        $gpioCtrl      = $ft232h.CreateGpioController()
        $isWindows     = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

        $connection = [PSCustomObject]@{
            Device         = $ft232h
            GpioController = $gpioCtrl
            Index          = $DeviceInfo.Index
            SerialNumber   = $DeviceInfo.SerialNumber
            Description    = $DeviceInfo.Description
            Type           = $DeviceInfo.Type
            LocationId     = $DeviceInfo.LocationId
            IsOpen         = $true
            GpioMethod     = 'IoT'
            GpioPins       = $DeviceInfo.GpioPins
            HasMpsse       = $DeviceInfo.HasMpsse
            MpsseEnabled   = $true
            Platform       = if ($isWindows) { 'Windows (IoT)' } else { 'Unix (IoT)' }
            Backend        = 'IoT'
        }

        # Close - disposes GpioController then Ft232HDevice
        $connection | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
            if ($this.GpioController) {
                try { $this.GpioController.Dispose() } catch {}
                $this.GpioController = $null
            }
            if ($this.Device) {
                try { $this.Device.Dispose() } catch {}
                $this.Device = $null
            }
            $this.IsOpen = $false
        }

        # Reset - soft-reset the FTDI chip (clears buffers, keeps connection open)
        $connection | Add-Member -MemberType ScriptMethod -Name 'Reset' -Value {
            if (-not $this.IsOpen -or -not $this.Device) { throw 'Device is not open' }
            $this.Device.Reset()
        }

        # CreateI2cBus - returns an IoT I2cBus for use with Iot.Device.Bindings sensor classes
        $connection | Add-Member -MemberType ScriptMethod -Name 'CreateI2cBus' -Value {
            if (-not $this.IsOpen -or -not $this.Device) { throw 'Device is not open' }
            return $this.Device.CreateOrGetI2cBus()
        }

        # CreateSpiDevice - returns an IoT SpiDevice for use with Iot.Device.Bindings bindings
        $connection | Add-Member -MemberType ScriptMethod -Name 'CreateSpiDevice' -Value {
            param([object]$SpiSettings)
            if (-not $this.IsOpen -or -not $this.Device) { throw 'Device is not open' }
            return $this.Device.CreateSpiDevice($SpiSettings)
        }

        Write-Verbose "Successfully opened $($DeviceInfo.Type) via IoT backend"
        return $connection

    } catch [System.NotImplementedException] {
        throw   # propagate cleanly for stub-mode detection upstream
    } catch {
        throw "Failed to open IoT FTDI device: $_"
    }
}

function Set-FtdiIotGpioPins {
    # Set ACBUS GPIO pins on an MPSSE device using the IoT GpioController.
    #
    # Pin mapping:
    #   PsGadget ACBUS pin 0  ->  IoT GpioController pin 8  (ACBUS0 / C0)
    #   PsGadget ACBUS pin 7  ->  IoT GpioController pin 15 (ACBUS7 / C7)
    #   ADBUS0-7 (IoT pins 0-7) are used for SPI/I2C/JTAG, not for general GPIO here.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$GpioController,

        [Parameter(Mandatory = $true)]
        [int[]]$Pins,

        [Parameter(Mandatory = $true)]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [int]$DurationMs
    )

    try {
        # Translate ACBUS pin numbers (0-7) to IoT controller pin numbers (8-15)
        $iotPins = $Pins | ForEach-Object { $_ + 8 }

        $pinValue = if ($State -in @('HIGH', 'H', '1')) {
            [System.Device.Gpio.PinValue]::High
        } else {
            [System.Device.Gpio.PinValue]::Low
        }

        foreach ($pin in $iotPins) {
            if (-not $GpioController.IsPinOpen($pin)) {
                $GpioController.OpenPin($pin, [System.Device.Gpio.PinMode]::Output)
            }
            $GpioController.Write($pin, $pinValue)
        }

        if ($DurationMs) {
            Start-Sleep -Milliseconds $DurationMs
            $restoreValue = if ($pinValue -eq [System.Device.Gpio.PinValue]::High) {
                [System.Device.Gpio.PinValue]::Low
            } else {
                [System.Device.Gpio.PinValue]::High
            }
            foreach ($pin in $iotPins) {
                $GpioController.Write($pin, $restoreValue)
            }
        }

        return $true

    } catch {
        Write-Warning "IoT GPIO operation failed: $($_.Exception.Message)"
        return $false
    }
}
