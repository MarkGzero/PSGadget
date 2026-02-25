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
                GpioPins       = 'CBUS0-3 (CBUS bit-bang), ADBUS0-7 (async bit-bang)'
                HasMpsse       = $false
                CapabilityNote = 'No MPSSE. CBUS bit-bang (mode 0x20): requires FT_PROG EEPROM config to set CBUS0-3 as "CBUS I/O". Async bit-bang (mode 0x01): uses ADBUS0-7 (UART lines), no EEPROM change needed.'
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
        
        # Determine platform and call appropriate implementation
        if ($PSVersionTable.PSVersion.Major -le 5 -or [System.Environment]::OSVersion.Platform -eq 'Win32NT') {
            Write-Verbose "Using Windows FTDI backend"
            $devices = Invoke-FtdiWindowsEnumerate
        } else {
            Write-Verbose "Using Unix FTDI backend"  
            $devices = Invoke-FtdiUnixEnumerate
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