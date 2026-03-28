#Requires -Version 5.1
# Get-FTDevice.ps1
# Enumerate available FTDI devices

function Get-FTDevice {
    <#
    .SYNOPSIS
    Lists PsGadget-compatible FTDI devices on the system.
    
    .DESCRIPTION
    Enumerates FTDI devices using the D2XX driver. By default, only devices accessible
    via D2XX (and usable with PsGadget) are returned. Devices running the VCP
    (Virtual COM Port) driver are hidden unless -ShowVCP is specified, as they cannot
    be used with PsGadget's GPIO or MPSSE functions.
    
    .EXAMPLE
    Get-FTDevice
    
    .EXAMPLE  
    $Devices = Get-FTDevice
    $Devices | Where-Object { -not $_.IsOpen }

    .EXAMPLE
    Get-FTDevice -ShowVCP

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
                $runningOnWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
                if ($runningOnWindows) {
                    Write-Warning (
                        "No PsGadget-compatible FTDI devices found.`n" +
                        "`n" +
                        "  Cause : Device is likely in VCP mode (shown as COM port in Device Manager).`n" +
                        "  Fix   : Install the D2XX driver from https://ftdichip.com/drivers/d2xx-drivers/`n" +
                        "  Tip   : Use -ShowVCP to list VCP-mode devices."
                    )
                } else {
                    $vcpDevices = @($Devices | Where-Object { $_.IsVcp })
                    if ($vcpDevices.Count -gt 0) {
                        Write-Warning (
                            "No PsGadget-compatible FTDI devices found -- $($vcpDevices.Count) device(s) held by ftdi_sio (VCP).`n" +
                            "`n" +
                            "  Cause   : The ftdi_sio kernel module has claimed the device(s). D2XX cannot`n" +
                            "            claim a device while ftdi_sio is loaded.`n" +
                            "  Fix     : sudo rmmod ftdi_sio`n" +
                            "            Then: Import-Module PSGadget -Force`n" +
                            "  Perm    : echo 'blacklist ftdi_sio' | sudo tee /etc/modprobe.d/ftdi-d2xx.conf`n" +
                            "  Restore : sudo modprobe ftdi_sio  (re-enables /dev/ttyUSBx VCP mode)`n" +
                            "  Tip     : Use -ShowVCP to list VCP-mode devices."
                        )
                    } else {
                        Write-Warning (
                            "No PsGadget-compatible FTDI devices found.`n" +
                            "`n" +
                            "  Cause : libftd2xx.so may not be installed, or no device is connected.`n" +
                            "  Fix   : Confirm libftd2xx.so is installed (ldconfig -p | grep ftd2xx)`n" +
                            "          and device is plugged in (lsusb | grep -i ftdi).`n" +
                            "  Tip   : Use -ShowVCP to list VCP-mode devices."
                        )
                    }
                }
                Write-Verbose "Run Test-PsGadgetEnvironment -Verbose for driver and native library diagnostics."
                return @()
            }
            Write-Verbose "$($Filtered.Count) PsGadget-compatible device(s) after filtering VCP"
            foreach ($dev in $Filtered) {
                $caps = Get-FtdiChipCapabilities -TypeName $dev.Type
                if ($dev.SerialNumber) {
                    Write-Verbose ("  [{0}] {1} SN={2} GPIO={3}" -f $dev.Index, $dev.Type, $dev.SerialNumber, $caps.GpioMethod)
                    Write-Verbose ("      Connect  : `$dev = New-PsGadgetFtdi -SerialNumber '{0}'" -f $dev.SerialNumber)
                } else {
                    Write-Verbose ("  [{0}] {1} GPIO={2}" -f $dev.Index, $dev.Type, $caps.GpioMethod)
                    Write-Verbose ("      Connect  : `$dev = New-PsGadgetFtdi -Index {0}" -f $dev.Index)
                }
                if ($caps.HasMpsse) {
                    Write-Verbose ("      I2C scan : `$dev.ScanI2CBus()")
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

# Backward-compatibility alias
Set-Alias -Name 'Get-PsGadgetFtdi' -Value 'Get-FTDevice'