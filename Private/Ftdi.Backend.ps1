# Ftdi.Backend.ps1
# Core FTDI backend functionality - platform agnostic

function Get-FtdiChipCapabilities {
    # Returns a capability descriptor hashtable for a given FTDI chip type name.
    # This is the single source of truth for GPIO method, pin availability, and
    # any EEPROM or setup requirements - used by enumeration, connect, and GPIO code.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    switch -Regex ($TypeName) {
        '^FT232H$|^FT232HP$' {
            return @{
                GpioMethod     = 'MPSSE'
                GpioPins       = 'ACBUS0-7, ADBUS0-7'
                HasMpsse       = $true
                CapabilityNote = ''
            }
        }
        '^FT2232H$|^FT2232C$|^FT2232D$' {
            return @{
                GpioMethod     = 'MPSSE'
                GpioPins       = 'ACBUS0-7, ADBUS0-7 (dual channel)'
                HasMpsse       = $true
                CapabilityNote = 'MPSSE available on both channels A and B'
            }
        }
        '^FT4232H$' {
            return @{
                GpioMethod     = 'MPSSE'
                GpioPins       = 'ADBUS0-7 (channels A/B only)'
                HasMpsse       = $true
                CapabilityNote = 'MPSSE on channels A and B only; C and D are UART/GPIO'
            }
        }
        '^FT232R(L|NL)?$' {
            return @{
                GpioMethod     = 'CBUS'
                GpioPins       = 'CBUS0-4 (5 pins; CBUS0-3 runtime bit-bang, CBUS4 EEPROM-config only), ADBUS0-7 (async bit-bang)'
                HasMpsse       = $false
                CapabilityNote = 'No MPSSE. Device has CBUS0-4 (5 pins). CBUS bit-bang (mode 0x20) runtime: CBUS0-3 only (D2XX mask is 8 bits, 4 direction + 4 value). CBUS4 is EEPROM-configurable (Set-PsGadgetFt232rCbusMode -Pins @(4)) but cannot be driven at runtime via SetBitMode. Async bit-bang (mode 0x01): uses ADBUS0-7 (UART lines), no EEPROM change needed.'
            }
        }
        '^FT231X$|^FT230X$|^FT-X' {
            return @{
                GpioMethod     = 'CBUS'
                GpioPins       = 'CBUS0-3'
                HasMpsse       = $false
                CapabilityNote = 'CBUS bit-bang (mode 0x20): requires FT_PROG EEPROM config'
            }
        }
        '^FT232BM$|^FT232AM$|^FT100AX$' {
            return @{
                GpioMethod     = 'AsyncBitBang'
                GpioPins       = 'ADBUS0-7'
                HasMpsse       = $false
                CapabilityNote = 'Legacy chip. Async bit-bang (mode 0x01) on ADBUS0-7 only'
            }
        }
        default {
            return @{
                GpioMethod     = 'Unknown'
                GpioPins       = 'Unknown'
                HasMpsse       = $false
                CapabilityNote = "Unrecognised chip type: $TypeName"
            }
        }
    }
}

function Get-FtdiDeviceList {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()
    
    try {
        Write-Verbose "Enumerating FTDI devices via platform-specific backend..."
        
        # Determine platform and call appropriate implementation.
        # IoT backend is tried first on PS7.4+/.NET8+.  If it throws (e.g. libftd2xx.so
        # absent on a Linux dev machine with no physical device) fall through to the
        # platform-specific backend so that Unix stubs remain active.
        $devices = $null
        if ($script:IotBackendAvailable) {
            Write-Verbose "Using IoT .NET backend for enumeration"
            try {
                $devices = Invoke-FtdiIotEnumerate
            } catch {
                Write-Verbose "IoT backend unavailable ($($_.Exception.GetType().Name)); falling back to platform-specific backend"
                $devices = $null
            }
            if (-not $devices -or @($devices).Count -eq 0) {
                Write-Verbose "IoT enumeration returned no devices; falling back to platform-specific backend"
                $devices = $null
            }

            # Detect ftdi_sio conflict: D2XX sees the device but can't query its type
            # because the kernel VCP driver has it claimed. All devices come back as
            # 'UnknownDevice' with DeviceId=0x00000000 and Flags bit 0 set (PortOpened).
            # Fall back to sysfs for accurate chip identification; warn about the conflict.
            if ($devices -and @($devices).Count -gt 0) {
                $allUnknown = @($devices) | Where-Object { $_.Type -ne 'UnknownDevice' } | Measure-Object | Select-Object -ExpandProperty Count
                if ($allUnknown -eq 0) {
                    $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
                    if (-not $isWindows) {
                        Write-Warning "ftdi_sio kernel module is holding the device - D2XX cannot read chip type."
                        Write-Warning "Enumeration metadata falls back to sysfs (read-only; connect will fail until ftdi_sio is unloaded)."
                        Write-Warning "To enable D2XX/IoT hardware access: sudo rmmod ftdi_sio"
                        Write-Warning "To make permanent: echo 'blacklist ftdi_sio' | sudo tee /etc/modprobe.d/ftdi-d2xx.conf"
                        $devices = $null   # trigger sysfs fallback below
                    }
                }
            }
        }
        if ($null -eq $devices) {
            if ($PSVersionTable.PSVersion.Major -le 5 -or [System.Environment]::OSVersion.Platform -eq 'Win32NT') {
                Write-Verbose "Using Windows FTDI backend"
                $devices = Invoke-FtdiWindowsEnumerate
            } else {
                Write-Verbose "Using Unix FTDI backend"
                $devices = Invoke-FtdiUnixEnumerate
            }
        }
        
        # Validate and enrich device list
        if ($devices -and @($devices).Count -gt 0) {
            Write-Verbose "Successfully enumerated $(@($devices).Count) FTDI device(s)"
            
            # Ensure consistent Index values and backfill any missing capability properties.
            # Windows and future platform backends may already stamp these; this pass ensures
            # that any backend which omits Get-FtdiChipCapabilities still produces a complete object.
            $deviceArray = @($devices)
            for ($i = 0; $i -lt $deviceArray.Count; $i++) {
                $deviceArray[$i].Index = $i
                if (-not $deviceArray[$i].PSObject.Properties['GpioMethod']) {
                    $caps = Get-FtdiChipCapabilities -TypeName $deviceArray[$i].Type
                    $deviceArray[$i] | Add-Member -MemberType NoteProperty -Name GpioMethod     -Value $caps.GpioMethod     -Force
                    $deviceArray[$i] | Add-Member -MemberType NoteProperty -Name GpioPins       -Value $caps.GpioPins       -Force
                    $deviceArray[$i] | Add-Member -MemberType NoteProperty -Name HasMpsse       -Value $caps.HasMpsse       -Force
                    $deviceArray[$i] | Add-Member -MemberType NoteProperty -Name CapabilityNote -Value $caps.CapabilityNote -Force
                }
                # Stamp IsVcp based on Driver field (VCP devices use ftdibus.sys)
                if (-not $deviceArray[$i].PSObject.Properties['IsVcp']) {
                    $isVcp = $deviceArray[$i].Driver -like '*VCP*'
                    $deviceArray[$i] | Add-Member -MemberType NoteProperty -Name IsVcp -Value $isVcp -Force
                }
            }
            
            return $deviceArray
        } else {
            Write-Verbose "No FTDI devices found"
            return @()
        }
        
    } catch [System.NotImplementedException] {
        Write-Verbose "FTDI enumeration not implemented - returning unified stub devices"
        
        # Return platform-agnostic stub device list for development
        $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
        
        $stubDevices = @(
            [PSCustomObject]@{
                Index          = 0
                Type           = 'FT232H'
                Description    = 'FT232H USB-Serial (UNIFIED STUB)'
                SerialNumber   = 'STUB001'
                LocationId     = if ($isWindows) { 0x1234 } else { '/dev/ttyUSB0' }
                IsOpen         = $false
                Flags          = '0x00000000'
                DeviceId       = '0x04036014'
                Handle         = $null
                Driver         = if ($isWindows) { 'ftd2xx.dll (STUB)' } else { 'libftdi (STUB)' }
                Platform       = if ($isWindows) { 'Windows' } else { 'Unix' }
                IsVcp          = $false
                GpioMethod     = 'MPSSE'
                GpioPins       = 'ACBUS0-7, ADBUS0-7'
                HasMpsse       = $true
                CapabilityNote = ''
            },
            [PSCustomObject]@{
                Index          = 1
                Type           = 'FT232R'
                Description    = 'FT232R USB UART (UNIFIED STUB)'
                SerialNumber   = 'STUB002'
                LocationId     = if ($isWindows) { 0x5678 } else { '/dev/ttyUSB1' }
                IsOpen         = $false
                Flags          = '0x00000000'
                DeviceId       = '0x04036001'
                Handle         = $null
                Driver         = if ($isWindows) { 'ftdibus.sys (VCP) (STUB)' } else { 'libftdi (STUB)' }
                Platform       = if ($isWindows) { 'Windows' } else { 'Unix' }
                IsVcp          = if ($isWindows) { $true } else { $false }
                GpioMethod     = 'CBUS'
                GpioPins       = 'CBUS0-3 (CBUS bit-bang), ADBUS0-7 (async bit-bang)'
                HasMpsse       = $false
                CapabilityNote = "No MPSSE. CBUS bit-bang (mode 0x20): requires FT_PROG EEPROM config to set CBUS0-3 as 'CBUS I/O'. Async bit-bang (mode 0x01): uses ADBUS0-7 (UART lines), no EEPROM change needed."
            }
        )
        return $stubDevices
    } catch {
        Write-Warning "FTDI device enumeration failed: $($_.Exception.Message)"
        return @()
    }
}

function Test-FtdiDeviceAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )
    
    try {
        $Devices = Get-FtdiDeviceList
        return ($null -ne ($Devices | Where-Object { $_.Index -eq $Index }))
    } catch {
        Write-Warning "Failed to check FTDI device availability: $($_.Exception.Message)"
        return $false
    }
}

function Get-FtdiDeviceInfo {
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )
    
    try {
        $Devices = Get-FtdiDeviceList
        $Device = $Devices | Where-Object { $_.Index -eq $Index }
        
        if ($null -eq $Device) {
            throw [System.ArgumentException]::new("FTDI device at index $Index not found")
        }
        
        return $Device
    } catch {
        Write-Warning "Failed to get FTDI device info: $($_.Exception.Message)"
        throw
    }
}