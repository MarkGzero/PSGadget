# Ftdi.Windows.ps1
# Windows-specific FTDI D2XX implementation

function Invoke-FtdiWindowsEnumerate {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()
    
    try {
        # Check if FTDI assembly is available, but try to use it anyway if types exist
        $ftdiAssemblyAvailable = $script:FtdiInitialized -or ([System.Type]::GetType("FTD2XX_NET.FTDI") -ne $null)
        
        if (-not $ftdiAssemblyAvailable) {
            throw [System.NotImplementedException]::new("FTDI assembly not loaded - Windows FTDI enumeration not available")
        }
        
        # Create FTDI instance for enumeration
        $ftdi = [FTD2XX_NET.FTDI]::new()
        
        # Get device count (use int like the working old function)
        [int]$deviceCount = 0
        $status = $ftdi.GetNumberOfDevices([ref]$deviceCount)
        
        # Use enum directly like the working old function
        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            $ftdi.Close() | Out-Null
            throw "FTDI GetNumberOfDevices failed: $status"
        }
        
        # Build D2XX device list
        $enrichedDevices = @()

        if ($deviceCount -eq 0) {
            Write-Verbose "No FTDI devices found via D2XX on Windows"
            $ftdi.Close() | Out-Null
        } else {
        Write-Verbose "Found $deviceCount FTDI device(s) via D2XX on Windows"
        
        # Get device info list (use New-Object like the working old function)
        $deviceList = New-Object 'FTD2XX_NET.FTDI+FT_DEVICE_INFO_NODE[]' $deviceCount
        $status = $ftdi.GetDeviceList($deviceList)
        
        if ($status -ne [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            $ftdi.Close() | Out-Null  
            throw "FTDI GetDeviceList failed: $status"
        }
        
        # Build enriched device objects with friendly type names
        for ($i = 0; $i -lt $deviceList.Count; $i++) {
            $device = $deviceList[$i]
            
            # Map device type to friendly name
            $typeName = switch ($device.Type) {
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_BM)       { "FT232BM" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_AM)       { "FT232AM" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_100AX)    { "FT100AX" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_2232C)    { "FT2232C" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_232R)     { "FT232R" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_2232H)    { "FT2232H" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_4232H)    { "FT4232H" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_232H)     { "FT232H" }
                ([FTD2XX_NET.FTDI+FT_DEVICE]::FT_DEVICE_X_SERIES) { "FT-X Series" }
                default { $device.Type.ToString() }
            }
            
            # Check if device is in use (bit 0 of flags indicates if device is open)
            $isOpen = ($device.Flags -band 0x00000001) -ne 0
            
            # Create enriched device object
            $caps = Get-FtdiChipCapabilities -TypeName $typeName
            $enrichedDevice = [PSCustomObject]@{
                Index          = $i
                Type           = $typeName
                Description    = $device.Description
                SerialNumber   = $device.SerialNumber
                LocationId     = $device.LocId
                IsOpen         = $isOpen
                Flags          = "0x{0:X8}" -f $device.Flags
                DeviceId       = "0x{0:X8}" -f $device.ID
                Handle         = $device.ftHandle
                Driver         = "ftd2xx.dll"
                Platform       = "Windows"
                GpioMethod     = $caps.GpioMethod
                GpioPins       = $caps.GpioPins
                HasMpsse       = $caps.HasMpsse
                CapabilityNote = $caps.CapabilityNote
            }
            
            $enrichedDevices += $enrichedDevice
        }

        # Close D2XX instance after enumeration
        $ftdi.Close() | Out-Null
        } # end D2XX block

        # Supplement: find VCP-mode FTDI devices not visible to D2XX
        Write-Verbose "Scanning registry for VCP-mode FTDI devices..."
        $vcpDevices = Invoke-FtdiWindowsEnumerateVcp
        foreach ($vcpDev in $vcpDevices) {
            $alreadyFound = $false
            foreach ($d in $enrichedDevices) {
                if ($d.SerialNumber -eq $vcpDev.SerialNumber) {
                    $alreadyFound = $true
                    # Enrich D2XX entry with COM port info if available
                    if ($vcpDev.ComPort -and -not $d.PSObject.Properties['ComPort']) {
                        $d | Add-Member -MemberType NoteProperty -Name ComPort -Value $vcpDev.ComPort -Force
                    }
                    break
                }
            }
            if (-not $alreadyFound) {
                $vcpDev.Index = $enrichedDevices.Count
                $enrichedDevices += $vcpDev
            }
        }

        if ($enrichedDevices.Count -eq 0) {
            Write-Verbose "No FTDI devices found on Windows"
            return @()
        }

        return $enrichedDevices
        
    } catch [System.NotImplementedException] {
        # Return enhanced stub data for Windows development
        return @(
            [PSCustomObject]@{
                Index          = 0
                Type           = "FT232H"
                Description    = "FT232H USB-Serial (Windows STUB)"
                SerialNumber   = "WINSTUB001"
                LocationId     = 0x1001
                IsOpen         = $false
                Flags          = "0x00000000"
                DeviceId       = "0x04036014"
                Handle         = $null
                Driver         = "ftd2xx.dll (STUB)"
                Platform       = "Windows"
                GpioMethod     = "MPSSE"
                GpioPins       = "ACBUS0-7, ADBUS0-7"
                HasMpsse       = $true
                CapabilityNote = ""
            },
            [PSCustomObject]@{
                Index          = 1
                Type           = "FT232R"
                Description    = "FT232R USB-Serial (Windows STUB)"
                SerialNumber   = "WINSTUB002"
                LocationId     = 0x1002
                IsOpen         = $false
                Flags          = "0x00000000"
                DeviceId       = "0x04036001"
                Handle         = $null
                Driver         = "ftdibus.sys (VCP) (STUB)"
                Platform       = "Windows"
                GpioMethod     = "CBUS"
                GpioPins       = "CBUS0-3 (CBUS bit-bang), ADBUS0-7 (async bit-bang)"
                HasMpsse       = $false
                CapabilityNote = "No MPSSE. CBUS bit-bang (mode 0x20): requires FT_PROG EEPROM config to set CBUS0-3 as 'CBUS I/O'. Async bit-bang (mode 0x01): uses ADBUS0-7 (UART lines), no EEPROM change needed."
            }
        )
    } catch {
        Write-Warning "Windows FTDI enumeration failed: $($_.Exception.Message)"
        return @()
    }
}

function Invoke-FtdiWindowsEnumerateVcp {
    # Scan the FTDIBUS registry hive for VCP-mode FTDI devices (FT232R, etc.)
    # Returns device objects for any FTDI device not visible via D2XX.
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()

    $results = @()
    $ftdibusPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\FTDIBUS'

    if (-not (Test-Path $ftdibusPath)) {
        Write-Verbose "FTDIBUS registry key not found - no VCP FTDI devices installed"
        return $results
    }

    # Map FTDI PID (hex string, upper) to friendly device type name
    $pidTypeMap = @{
        '6001' = 'FT232R'    # FT232R / FT232RL / FT232RNL (same PID, all VCP-only)
        '6010' = 'FT2232D'   # FT2232D / FT2232C
        '6011' = 'FT4232H'
        '6014' = 'FT232H'
        '6015' = 'FT231X'    # FT-X Series (FT230X/FT231X)
        '6040' = 'FT232HP'
    }

    try {
        $comboKeys = Get-ChildItem $ftdibusPath -ErrorAction SilentlyContinue
        foreach ($comboKey in $comboKeys) {
            # Key name pattern: VID_0403+PID_6001+{SERIAL}
            if ($comboKey.PSChildName -match 'VID_([0-9A-Fa-f]{4})\+PID_([0-9A-Fa-f]{4})\+(.+)$') {
                $vid    = $Matches[1].ToUpper()
                $pid    = $Matches[2].ToUpper()
                $serial = $Matches[3]

                $typeName = if ($pidTypeMap.ContainsKey($pid)) { $pidTypeMap[$pid] } else { "FT-Unknown (PID $pid)" }

                # Each combo key has one or more instance sub-keys (typically '0000')
                $instanceKeys = Get-ChildItem $comboKey.PSPath -ErrorAction SilentlyContinue
                foreach ($inst in $instanceKeys) {
                    # Friendly name stored on the instance key
                    $friendlyName = $null
                    try {
                        $friendlyName = (Get-ItemProperty -Path $inst.PSPath -Name FriendlyName -ErrorAction SilentlyContinue).FriendlyName
                    } catch {}

                    # COM port stored under Device Parameters sub-key
                    $comPort = $null
                    $devParams = Join-Path $inst.PSPath 'Device Parameters'
                    try {
                        $comPort = (Get-ItemProperty -Path $devParams -Name PortName -ErrorAction SilentlyContinue).PortName
                    } catch {}

                    if (-not $friendlyName) { $friendlyName = "$typeName USB Serial" }

                    $caps = Get-FtdiChipCapabilities -TypeName $typeName
                    $results += [PSCustomObject]@{
                        Index          = -1   # assigned by caller
                        Type           = $typeName
                        Description    = $friendlyName
                        SerialNumber   = $serial
                        LocationId     = 0
                        IsOpen         = $false
                        Flags          = '0x00000000'
                        DeviceId       = "0x0403$pid"
                        Handle         = $null
                        Driver         = 'ftdibus.sys (VCP)'
                        Platform       = 'Windows'
                        ComPort        = $comPort
                        VID            = $vid
                        PID            = $pid
                        GpioMethod     = $caps.GpioMethod
                        GpioPins       = $caps.GpioPins
                        HasMpsse       = $caps.HasMpsse
                        CapabilityNote = $caps.CapabilityNote
                    }
                }
            }
        }
    } catch {
        Write-Verbose "VCP registry scan error: $($_.Exception.Message)"
    }

    return $results
}

function Invoke-FtdiWindowsOpen {
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )
    
    try {
        # Check if FTDI assembly is available
        if (-not $script:FtdiInitialized) {
            throw [System.NotImplementedException]::new("FTDI assembly not loaded - cannot open device")
        }
        
        # Get device list to validate index
        $devices = Invoke-FtdiWindowsEnumerate
        if ($Index -lt 0 -or $Index -ge $devices.Count) {
            throw "Device index $Index is out of range. Available devices: 0-$($devices.Count - 1)"
        }
        
        $targetDevice = $devices[$Index]
        Write-Verbose "Opening FTDI device: $($targetDevice.Description) ($($targetDevice.SerialNumber))"
        
        # Create new FTDI instance for this connection
        $ftdi = [FTD2XX_NET.FTDI]::new()
        
        # Try to open by index first
        $status = $ftdi.OpenByIndex([uint32]$Index)
        
        if ($status -ne $script:FTDI_OK) {
            # Try alternative opening methods
            Write-Verbose "OpenByIndex failed, trying OpenBySerialNumber..."
            $ftdi.Close() | Out-Null
            
            $ftdi = [FTD2XX_NET.FTDI]::new()
            $status = $ftdi.OpenBySerialNumber($targetDevice.SerialNumber)
            
            if ($status -ne $script:FTDI_OK) {
                $ftdi.Close() | Out-Null
                throw "Failed to open FTDI device: $status"
            }
        }
        
        # Configure device for MPSSE mode if supported
        if ($targetDevice.HasMpsse) {
            Write-Verbose "Configuring device for MPSSE mode..."
            
            # Reset the device
            $status = $ftdi.ResetDevice()
            if ($status -ne $script:FTDI_OK) {
                Write-Warning "Device reset failed: $status"
            }
            
            # Set bit mode for MPSSE (mode 0x02)
            $status = $ftdi.SetBitMode(0x00, 0x02)  # 0x02 = MPSSE mode
            if ($status -ne $script:FTDI_OK) {
                Write-Warning "Failed to set MPSSE mode: $status"
                # Continue anyway - some operations might still work
            } else {
                Write-Verbose "MPSSE mode enabled successfully"
            }
            
            # Set timeouts
            $ftdi.SetTimeouts(5000, 5000) | Out-Null  # 5 second read/write timeouts
        } else {
            Write-Verbose "Device uses $($targetDevice.GpioMethod) GPIO (no MPSSE setup needed on open)"
            $ftdi.SetTimeouts(5000, 5000) | Out-Null
        }
        
        # Create connection object with device info
        $connection = [PSCustomObject]@{
            Device      = $ftdi
            Index       = $Index
            SerialNumber = $targetDevice.SerialNumber
            Description  = $targetDevice.Description
            Type         = $targetDevice.Type
            IsOpen       = $true
            GpioMethod   = $targetDevice.GpioMethod
            GpioPins     = $targetDevice.GpioPins
            HasMpsse     = $targetDevice.HasMpsse
            MpsseEnabled = $targetDevice.HasMpsse
            Platform     = "Windows"
        }
        
        # Add methods to the connection object
        $connection | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
            if ($this.Device) {
                $this.Device.Close()
                $this.IsOpen = $false
            }
        }
        
        $connection | Add-Member -MemberType ScriptMethod -Name 'Write' -Value {
            param([byte[]]$data, [int]$length, [ref]$bytesWritten)
            return $this.Device.Write($data, $length, $bytesWritten)
        }
        
        $connection | Add-Member -MemberType ScriptMethod -Name 'Read' -Value {
            param([byte[]]$buffer, [int]$length, [ref]$bytesRead)
            return $this.Device.Read($buffer, $length, $bytesRead)
        }
        
        Write-Verbose "Successfully opened FTDI device $Index"
        return $connection
        
    } catch [System.NotImplementedException] {
        # Return stub connection for development
        Write-Verbose "Creating stub connection for device $Index (Windows)"
        
        return [PSCustomObject]@{
            Device = $null
            Index = $Index
            SerialNumber = "WINSTUB$Index"
            Description = "Windows STUB Connection"
            Type = "FT232H"
            IsOpen = $true
            MpsseEnabled = $true
            Platform = "Windows (STUB)"
            Close = { $this.IsOpen = $false }
            Write = { param($data, $length, $bytesWritten); $bytesWritten.Value = $length; return $script:FTDI_OK }
            Read = { param($buffer, $length, $bytesRead); $bytesRead.Value = 1; return $script:FTDI_OK }
        }
    } catch {
        Write-Error "Failed to open Windows FTDI device: $_"
        return $null
    }
}

function Invoke-FtdiWindowsClose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Handle
    )
    
    try {
        # TODO: Implement Windows FTDI device close via D2XX
        throw [System.NotImplementedException]::new("Windows FTDI device close not yet implemented")
        
    } catch [System.NotImplementedException] {
        Write-Verbose "Closed FTDI device handle $Handle on Windows (STUB MODE)"
        return [PSCustomObject]@{
            Success = $true
            Message = "Device closed successfully (Windows STUB)"
        }
    } catch {
        Write-Warning "Failed to close Windows FTDI device: $($_.Exception.Message)"
        throw
    }
}