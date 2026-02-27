# List-PsGadgetFtdi.ps1
# Enumerate available FTDI devices

function List-PsGadgetFtdi {
    <#
    .SYNOPSIS
    Lists PsGadget-compatible FTDI devices on the system.
    
    .DESCRIPTION
    Enumerates FTDI devices using the D2XX driver. By default, only devices accessible
    via D2XX (and usable with PsGadget) are returned. Devices running the VCP
    (Virtual COM Port) driver are hidden unless -ShowVCP is specified, as they cannot
    be used with PsGadget's GPIO or MPSSE functions.
    
    .EXAMPLE
    List-PsGadgetFtdi
    
    .EXAMPLE  
    $Devices = List-PsGadgetFtdi
    $Devices | Where-Object { -not $_.IsOpen }

    .EXAMPLE
    List-PsGadgetFtdi -ShowVCP

    Shows all detected FTDI devices including those running the VCP (Virtual COM Port) driver,
    which are not usable with PsGadget but may be useful for diagnostics.

    .PARAMETER ShowVCP
    When specified, includes VCP-mode devices in the output. By default only D2XX-accessible
    (PsGadget-compatible) devices are shown.
    
    .OUTPUTS
    System.Object[]
    Array of FTDI device objects with Index, Description, SerialNumber, LocationId, and IsOpen properties.
    #>
    
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [switch]$ShowVCP
    )
    
    try {
        Write-Verbose "Enumerating FTDI devices..."
        
        # Call the backend function to get device list
        $Devices = @(Get-FtdiDeviceList)
        
        if ($Devices.Count -eq 0) {
            Write-Warning "No FTDI devices found on this system"
            return @()
        }
        
        Write-Verbose "Found $($Devices.Count) FTDI device(s)"
        
        # Filter out VCP-mode devices unless -ShowVCP is specified.
        # VCP devices require a different driver (ftdibus.sys) and cannot be used
        # with PsGadget's D2XX-based GPIO/MPSSE functions.
        if (-not $ShowVCP) {
            $Filtered = @($Devices | Where-Object { -not $_.IsVcp })
            if ($Filtered.Count -eq 0) {
                Write-Warning "No PsGadget-compatible FTDI devices found. If you have FTDI devices loaded with the VCP driver, use -ShowVCP to see them."
                return @()
            }
            Write-Verbose "$($Filtered.Count) PsGadget-compatible device(s) after filtering VCP"
            return $Filtered
        }
        
        # Return the device list
        return $Devices
        
    } catch {
        Write-Error "Failed to enumerate FTDI devices: $($_.Exception.Message)"
        throw
    }
}