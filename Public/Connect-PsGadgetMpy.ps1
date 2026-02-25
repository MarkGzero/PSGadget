# Connect-PsGadgetMpy.ps1
# Connect to a MicroPython device via serial port

function Connect-PsGadgetMpy {
    <#
    .SYNOPSIS
    Connects to a MicroPython device and returns a PsGadgetMpy object.
    
    .DESCRIPTION
    Creates a new PsGadgetMpy object for the specified serial port. The device
    can then be used for MicroPython code execution and file management.
    
    .PARAMETER SerialPort
    The serial port name to connect to (e.g., COM3, /dev/ttyUSB0). 
    Use List-PsGadgetMpy to see available ports.
    
    .EXAMPLE
    $Device = Connect-PsGadgetMpy -SerialPort "COM3"
    $Info = $Device.GetInfo()
    
    .EXAMPLE
    $AvailablePorts = List-PsGadgetMpy
    $MpyDevice = Connect-PsGadgetMpy -SerialPort $AvailablePorts[0]
    $Result = $MpyDevice.Invoke("print('Hello from MicroPython')")
    
    .OUTPUTS
    PsGadgetMpy
    A PsGadgetMpy object that can be used to control the MicroPython device.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SerialPort
    )
    
    try {
        Write-Verbose "Connecting to MicroPython device on serial port: $SerialPort"
        
        # Validate serial port parameter
        if ([string]::IsNullOrWhiteSpace($SerialPort)) {
            throw [System.ArgumentException]::new("SerialPort parameter cannot be null or empty")
        }
        
        # Check if serial port exists in available ports
        $AvailablePorts = [System.IO.Ports.SerialPort]::GetPortNames()
        if ($AvailablePorts -notcontains $SerialPort) {
            Write-Warning "Serial port '$SerialPort' not found in available ports: $($AvailablePorts -join ', ')"
        }
        
        # Create and return new PsGadgetMpy object
        $MpyDevice = [PsGadgetMpy]::new($SerialPort)
        
        Write-Verbose "Successfully created MicroPython device object for port: $SerialPort"
        
        return $MpyDevice
        
    } catch {
        Write-Error "Failed to connect to MicroPython device on port '$SerialPort'`: $($_.Exception.Message)"
        throw
    }
}