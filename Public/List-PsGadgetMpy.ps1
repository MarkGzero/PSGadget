# List-PsGadgetMpy.ps1
# Enumerate available serial ports for MicroPython devices

function List-PsGadgetMpy {
    <#
    .SYNOPSIS
    Lists all available serial ports that could contain MicroPython devices.
    
    .DESCRIPTION
    Enumerates serial ports on the system using .NET System.IO.Ports.SerialPort.
    Returns an array of port names that can be used with Connect-PsGadgetMpy.
    
    .EXAMPLE
    List-PsGadgetMpy
    
    .EXAMPLE
    $Ports = List-PsGadgetMpy
    foreach ($Port in $Ports) {
        Write-Host "Found serial port: $Port"
    }
    
    .OUTPUTS
    System.String[]
    Array of serial port names (e.g., COM3, /dev/ttyUSB0).
    #>
    
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param()
    
    try {
        Write-Verbose "Enumerating serial ports..."
        
        # Get available serial ports using .NET
        $SerialPorts = [System.IO.Ports.SerialPort]::GetPortNames()
        
        if ($SerialPorts.Count -eq 0) {
            Write-Warning "No serial ports found on this system"
            return @()
        }
        
        # Sort ports for consistent output
        $SortedPorts = $SerialPorts | Sort-Object
        
        Write-Verbose "Found $($SortedPorts.Count) serial port(s): $($SortedPorts -join ', ')"
        
        return $SortedPorts
        
    } catch {
        Write-Error "Failed to enumerate serial ports: $($_.Exception.Message)"
        throw
    }
}