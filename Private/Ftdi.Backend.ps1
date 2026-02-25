# Ftdi.Backend.ps1
# Core FTDI backend functionality - platform agnostic

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
        if ($devices -and $devices.Count -gt 0) {
            Write-Verbose "Successfully enumerated $($devices.Count) FTDI device(s)"
            
            # Ensure consistent Index values
            for ($i = 0; $i -lt $devices.Count; $i++) {
                $devices[$i].Index = $i
            }
            
            return $devices
        } else {
            Write-Verbose "No FTDI devices found"
            return @()
        }
        
    } catch [System.NotImplementedException] {
        Write-Verbose "FTDI enumeration not implemented - returning unified stub devices"
        
        # Return platform-agnostic stub device list for development
        $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
        
        return @(
            [PSCustomObject]@{
                Index = 0
                Type = "FT232H"
                Description = "FT232H USB-Serial (UNIFIED STUB)"
                SerialNumber = "STUB001"
                LocationId = if ($isWindows) { 0x1234 } else { "/dev/ttyUSB0" }
                IsOpen = $false
                Flags = "0x00000000"
                DeviceId = "0x04036014"
                Handle = $null
                Driver = if ($isWindows) { "ftd2xx.dll (STUB)" } else { "libftdi (STUB)" }
                Platform = if ($isWindows) { "Windows" } else { "Unix" }
            },
            [PSCustomObject]@{
                Index = 1
                Type = "FT2232H" 
                Description = "FT2232H Dual USB-Serial (UNIFIED STUB)"
                SerialNumber = "STUB002"
                LocationId = if ($isWindows) { 0x5678 } else { "/dev/ttyUSB1" }
                IsOpen = $false
                Flags = "0x00000000"
                DeviceId = "0x04036010"
                Handle = $null
                Driver = if ($isWindows) { "ftd2xx.dll (STUB)" } else { "libftdi (STUB)" }
                Platform = if ($isWindows) { "Windows" } else { "Unix" }
            }
        )
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