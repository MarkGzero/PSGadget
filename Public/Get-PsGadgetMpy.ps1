#Requires -Version 5.1
# Get-PsGadgetMpy.ps1
# Enumerate available serial ports for MicroPython devices

function Get-PsGadgetMpy {
    <#
    .SYNOPSIS
    Lists all available serial ports that could contain MicroPython devices.
    
    .DESCRIPTION
    Enumerates serial ports on the system. On Windows, uses WMI to enrich results
    with VID/PID, board identification, and MicroPython detection when -Detailed is specified.
    
    .PARAMETER Detailed
    Return enriched objects with VID, PID, Manufacturer, IsMicroPython, and Status
    properties instead of plain port name strings.
    
    .EXAMPLE
    Get-PsGadgetMpy
    
    .EXAMPLE
    Get-PsGadgetMpy -Detailed | Where-Object { $_.IsMicroPython } | Select Port, FriendlyName, Manufacturer
    
    .OUTPUTS
    System.String[] when called without -Detailed.
    System.Object[] when called with -Detailed.
    #>
    
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [switch]$Detailed
    )
    
    try {
        Write-Verbose "Enumerating serial ports..."
        
        $ports = Get-MpyPortList -Detailed:$Detailed
        
        if ($Detailed) {
            $portArray = @($ports)
            if ($portArray.Count -eq 0) {
                Write-Warning "No serial ports found on this system"
                return @()
            }
            Write-Verbose "Found $($portArray.Count) serial port(s)"
            return $portArray
        } else {
            $portArray = @($ports)
            if ($portArray.Count -eq 0) {
                Write-Warning "No serial ports found on this system"
                return @()
            }
            Write-Verbose "Found $($portArray.Count) serial port(s): $($portArray -join ', ')"
            return $portArray
        }
        
    } catch {
        Write-Error "Failed to enumerate serial ports: $($_.Exception.Message)"
        throw
    }
}