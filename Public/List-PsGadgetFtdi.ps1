# List-PsGadgetFtdi.ps1
# Enumerate available FTDI devices

function List-PsGadgetFtdi {
    <#
    .SYNOPSIS
    Lists all available FTDI devices on the system.
    
    .DESCRIPTION
    Enumerates FTDI devices using the D2XX driver. Returns a list of device objects
    with index, description, serial number, and availability status.
    
    .EXAMPLE
    List-PsGadgetFtdi
    
    .EXAMPLE  
    $Devices = List-PsGadgetFtdi
    $Devices | Where-Object { -not $_.IsOpen }
    
    .OUTPUTS
    System.Object[]
    Array of FTDI device objects with Index, Description, SerialNumber, LocationId, and IsOpen properties.
    #>
    
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()
    
    try {
        Write-Verbose "Enumerating FTDI devices..."
        
        # Call the backend function to get device list
        $Devices = Get-FtdiDeviceList
        
        if ($Devices.Count -eq 0) {
            Write-Warning "No FTDI devices found on this system"
            return @()
        }
        
        Write-Verbose "Found $($Devices.Count) FTDI device(s)"
        
        # Return the device list
        return $Devices
        
    } catch {
        Write-Error "Failed to enumerate FTDI devices: $($_.Exception.Message)"
        throw
    }
}