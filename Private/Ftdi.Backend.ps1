# Ftdi.Backend.ps1
# Core FTDI backend functionality - platform agnostic

function Get-FtdiDeviceList {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()
    
    try {
        # TODO: Implement actual FTDI D2XX device enumeration
        # This should call platform-specific implementations
        
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
            # Call Windows-specific implementation
            return Invoke-FtdiWindowsEnumerate
        } else {
            # Call Unix-specific implementation  
            return Invoke-FtdiUnixEnumerate
        }
        
    } catch [System.NotImplementedException] {
        # Return stub device list for development
        return @(
            [PSCustomObject]@{
                Index = 0
                Description = "FT232R USB UART (STUB)"
                SerialNumber = "A12345"
                LocationId = 0x1234
                IsOpen = $false
            },
            [PSCustomObject]@{
                Index = 1  
                Description = "FT2232H Dual RS232-HS (STUB)"
                SerialNumber = "B67890"
                LocationId = 0x5678
                IsOpen = $false
            }
        )
    } catch {
        Write-Warning "Failed to enumerate FTDI devices: $($_.Exception.Message)"
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