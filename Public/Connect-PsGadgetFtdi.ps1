# Connect-PsGadgetFtdi.ps1
# Connect to an FTDI device

function Connect-PsGadgetFtdi {
    <#
    .SYNOPSIS
    Connects to an FTDI device and returns a PsGadgetFtdi object.
    
    .DESCRIPTION
    Creates a new PsGadgetFtdi object for the specified device index. The device
    can then be opened and used for communication and GPIO control.
    
    .PARAMETER Index
    The index of the FTDI device to connect to. Use List-PsGadgetFtdi to see available devices.
    
    .EXAMPLE
    $Device = Connect-PsGadgetFtdi -Index 0
    $Device.Open()
    
    .EXAMPLE
    $FtdiDevices = List-PsGadgetFtdi
    $FirstDevice = Connect-PsGadgetFtdi -Index $FtdiDevices[0].Index
    
    .OUTPUTS
    PsGadgetFtdi
    A PsGadgetFtdi object that can be used to control the FTDI device.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [int]$Index
    )
    
    try {
        Write-Verbose "Connecting to FTDI device at index: $Index"
        
        # Validate that the device index exists
        if (-not (Test-FtdiDeviceAvailable -Index $Index)) {
            throw [System.ArgumentException]::new("FTDI device at index $Index not found or not available")
        }
        
        # Create and return new PsGadgetFtdi object
        $FtdiDevice = [PsGadgetFtdi]::new($Index)
        
        Write-Verbose "Successfully created FTDI device object for index: $Index"
        
        return $FtdiDevice
        
    } catch {
        Write-Error "Failed to connect to FTDI device at index $Index`: $($_.Exception.Message)"
        throw
    }
}