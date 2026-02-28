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
                Write-Verbose "Run Test-PsGadgetSetup -Verbose for driver and native library diagnostics."
                return @()
            }
            Write-Verbose "$($Filtered.Count) PsGadget-compatible device(s) after filtering VCP"
            foreach ($dev in $Filtered) {
                $caps = Get-FtdiChipCapabilities -TypeName $dev.Type
                if ($dev.SerialNumber) {
                    Write-Verbose ("  [{0}] {1} SN={2} GPIO={3}" -f $dev.Index, $dev.Type, $dev.SerialNumber, $caps.GpioMethod)
                    Write-Verbose ("      Connect  : `$dev = New-PsGadgetFtdi -SerialNumber '{0}'; `$dev.Connect()" -f $dev.SerialNumber)
                } else {
                    Write-Verbose ("  [{0}] {1} GPIO={2}" -f $dev.Index, $dev.Type, $caps.GpioMethod)
                    Write-Verbose ("      Connect  : `$dev = New-PsGadgetFtdi -Index {0}; `$dev.Connect()" -f $dev.Index)
                }
                if ($caps.HasMpsse) {
                    Write-Verbose ("      I2C scan : `$dev.Scan()")
                    Write-Verbose ("      Display  : `$dev.Display('Hello', 0)")
                }
            }
            return $Filtered
        }

        # Return the full device list (VCP included)
        foreach ($dev in $Devices) {
            $caps = Get-FtdiChipCapabilities -TypeName $dev.Type
            if ($dev.SerialNumber) {
                Write-Verbose ("  [{0}] {1} SN={2} GPIO={3}" -f $dev.Index, $dev.Type, $dev.SerialNumber, $caps.GpioMethod)
            }
        }
        return $Devices
        
    } catch {
        Write-Error "Failed to enumerate FTDI devices: $($_.Exception.Message)"
        throw
    }
}