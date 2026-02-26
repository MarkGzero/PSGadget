# Invoke-PsGadgetFtdiVcpUnload.ps1
# Public function to unload VCP driver from FTDI device

#Requires -Version 5.1

function Invoke-PsGadgetFtdiVcpUnload {
    <#
    .SYNOPSIS
    Attempts to unload VCP driver from an FTDI device to enable D2XX access.

    .DESCRIPTION
    Programmatically attempts to switch an FTDI device from VCP (Virtual COM Port) 
    mode to D2XX mode without requiring manual Device Manager intervention.

    This enables EEPROM programming functions like Set-PsGadgetFt232rCbusMode to work
    on devices that are currently showing as COM ports.

    WARNING: This is experimental functionality. Results may vary depending on:
    - FTDI D2XX driver version
    - Windows version  
    - Device usage by other applications
    - Administrator privileges

    Always ensure you can physically unplug/replug the device if needed.

    .PARAMETER SerialNumber
    Serial number of the FTDI device (as shown in List-PsGadgetFtdi output).

    .PARAMETER Method
    Method to attempt VCP unloading:
    - Reload: FT_Reload() API call (reloads all FTDI drivers)
    - CyclePort: FT_CyclePort() API call (cycles specific device)
    - SetVIDPID: VID/PID manipulation to force re-enumeration
    - Windows: Windows device disable/enable

    .EXAMPLE
    # Unload VCP for specific device using default method
    Invoke-PsGadgetFtdiVcpUnload -SerialNumber "BG01B0I1A"

    .EXAMPLE
    # Try different methods in sequence
    Invoke-PsGadgetFtdiVcpUnload -SerialNumber "BG01B0I1A" -Method CyclePort

    .EXAMPLE
    # Check device status before and after
    List-PsGadgetFtdi | Where-Object SerialNumber -eq "BG01B0I1A"
    Invoke-PsGadgetFtdiVcpUnload -SerialNumber "BG01B0I1A" 
    Start-Sleep -Seconds 3
    List-PsGadgetFtdi | Where-Object SerialNumber -eq "BG01B0I1A"

    .OUTPUTS
    Boolean indicating success/failure. Check List-PsGadgetFtdi to verify driver change.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$SerialNumber,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Reload', 'CyclePort', 'SetVIDPID', 'Windows')]
        [string]$Method = 'Reload'
    )

    $Logger = [PsGadgetLogger]::new()
    $Logger.WriteInfo("Starting VCP unload for device $SerialNumber using method $Method")

    # Verify device exists and is in VCP mode
    $devices = List-PsGadgetFtdi
    $targetDevice = $devices | Where-Object { $_.SerialNumber -eq $SerialNumber }

    if (-not $targetDevice) {
        Write-Error "No FTDI device found with serial number '$SerialNumber'"
        return $false
    }

    if ($targetDevice.Driver -eq 'ftd2xx.dll') {
        Write-Warning "Device $SerialNumber is already using D2XX driver (ftd2xx.dll)"
        $Logger.WriteInfo("Device $SerialNumber already in D2XX mode")
        return $true
    }

    if ($targetDevice.Driver -notlike '*VCP*') {
        Write-Warning "Device $SerialNumber driver is '$($targetDevice.Driver)' - not VCP mode"
        return $false
    }

    Write-Host "Attempting to unload VCP driver for:" -ForegroundColor Yellow
    Write-Host "  Device: $($targetDevice.Description)" -ForegroundColor Yellow  
    Write-Host "  Serial: $SerialNumber" -ForegroundColor Yellow
    Write-Host "  Current Driver: $($targetDevice.Driver)" -ForegroundColor Yellow
    Write-Host "  Method: $Method" -ForegroundColor Yellow

    try {
        $result = Invoke-FtdiVcpUnload -SerialNumber $SerialNumber -Method $Method
        
        if ($result) {
            $Logger.WriteInfo("VCP unload succeeded for device $SerialNumber")
            Write-Host "`nVCP unload completed. Waiting for device re-enumeration..." -ForegroundColor Green
            Start-Sleep -Seconds 3
            
            # Check if device switched to D2XX
            $updatedDevices = List-PsGadgetFtdi
            $updatedDevice = $updatedDevices | Where-Object { $_.SerialNumber -eq $SerialNumber }
            
            if ($updatedDevice -and $updatedDevice.Driver -eq 'ftd2xx.dll') {
                Write-Host "SUCCESS: Device $SerialNumber now using ftd2xx.dll driver!" -ForegroundColor Green
                $Logger.WriteInfo("Device $SerialNumber successfully switched to D2XX mode")
                return $true
            } else {
                Write-Warning "Device re-enumerated but driver status unclear. Run List-PsGadgetFtdi to check."
                return $true
            }
        } else {
            $Logger.WriteError("VCP unload failed for device $SerialNumber")
            Write-Host "`nVCP unload failed. Manual driver switching required." -ForegroundColor Red
            Write-Host "See troubleshooting section in psgadget_workflow.md" -ForegroundColor Yellow
            return $false
        }

    } catch {
        $Logger.WriteError("VCP unload exception for device $SerialNumber : $_")
        Write-Error "VCP unload failed: $_"
        return $false
    }
}