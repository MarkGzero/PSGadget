# Ftdi.VcpUnload.ps1
# Private helper to programmatically unload VCP driver from FTDI device

#Requires -Version 5.1

function Invoke-FtdiVcpUnload {
    <#
    .SYNOPSIS
    Attempts to programmatically unload VCP driver from an FTDI device to enable D2XX access.

    .DESCRIPTION
    Uses FTDI D2XX API methods to attempt driver unloading/reloading for a specific device.
    This can help switch devices from VCP mode to D2XX mode without manual Device Manager changes.

    WARNING: This is an experimental feature. Always have physical access to unplug/replug
    the device if something goes wrong.

    .PARAMETER SerialNumber
    Serial number of the FTDI device to unload VCP driver from.

    .PARAMETER Method
    Method to use for VCP unloading:
    - Reload: Use FT_Reload() if available
    - CyclePort: Use FT_CyclePort() if available
    - SetVIDPID: Temporarily change VID/PID to force re-enumeration

    .EXAMPLE
    Invoke-FtdiVcpUnload -SerialNumber "BG01B0I1A" -Method Reload

    .OUTPUTS
    Boolean indicating success/failure
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialNumber,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Reload', 'CyclePort', 'SetVIDPID')]
        [string]$Method = 'Reload'
    )

    if (-not $script:FtdiInitialized) {
        Write-Error "FTDI assembly not loaded"
        return $false
    }

    Write-Verbose "Attempting to unload VCP driver for device $SerialNumber using method: $Method"

    try {
        $ftdi = [FTD2XX_NET.FTDI]::new()
        
        switch ($Method) {
            'Reload' {
                # Try FT_Reload() - reloads all FTDI drivers
                if ($ftdi | Get-Member -Name "Reload" -MemberType Method -ErrorAction SilentlyContinue) {
                    Write-Verbose "Calling FT_Reload()..."
                    $status = $ftdi.Reload()
                    if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
                        Write-Host "FT_Reload() succeeded - drivers reloaded" -ForegroundColor Green
                        return $true
                    } else {
                        Write-Warning "FT_Reload() failed: $status"
                    }
                } else {
                    Write-Warning "FT_Reload() method not available in this D2XX version"
                }
            }

            'CyclePort' {
                # Try opening device first, then cycling
                $status = $ftdi.OpenBySerialNumber($SerialNumber)
                if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
                    if ($ftdi | Get-Member -Name "CyclePort" -MemberType Method -ErrorAction SilentlyContinue) {
                        Write-Verbose "Calling FT_CyclePort()..."
                        $status = $ftdi.CyclePort()
                        $ftdi.Close() | Out-Null
                        if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
                            Write-Host "FT_CyclePort() succeeded - device cycled" -ForegroundColor Green
                            return $true
                        } else {
                            Write-Warning "FT_CyclePort() failed: $status"
                        }
                    } else {
                        $ftdi.Close() | Out-Null
                        Write-Warning "FT_CyclePort() method not available in this D2XX version"
                    }
                } else {
                    Write-Warning "Could not open device $SerialNumber for cycling: $status"
                }
            }

            'SetVIDPID' {
                # Try VID/PID manipulation to force re-enumeration
                if ($ftdi | Get-Member -Name "SetVIDPID" -MemberType Method -ErrorAction SilentlyContinue) {
                    Write-Verbose "Attempting VID/PID manipulation..."
                    # Standard FTDI VID, temporarily change to force reload
                    $origVid = 0x0403
                    $origPid = 0x6001  # FT232R
                    $tempPid = 0x6002  # Temporary PID
                    
                    # Set temporary PID
                    $status1 = $ftdi.SetVIDPID($origVid, $tempPid)
                    Start-Sleep -Milliseconds 500
                    
                    # Restore original PID
                    $status2 = $ftdi.SetVIDPID($origVid, $origPid)
                    
                    if ($status1 -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK -and 
                        $status2 -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
                        Write-Host "VID/PID cycling succeeded - device should re-enumerate" -ForegroundColor Green
                        return $true
                    } else {
                        Write-Warning "VID/PID manipulation failed: Set1=$status1, Set2=$status2"
                    }
                } else {
                    Write-Warning "SetVIDPID() method not available in this D2XX version"
                }
            }
        }

        # If all methods failed, try direct driver restart approach
        Write-Verbose "D2XX methods failed, attempting Windows driver restart..."
        return Invoke-FtdiVcpUnloadWindows -SerialNumber $SerialNumber

    } catch {
        Write-Error "VCP unload failed: $_"
        return $false
    } finally {
        if ($ftdi) {
            try { $ftdi.Close() | Out-Null } catch {}
        }
    }
}

function Invoke-FtdiVcpUnloadWindows {
    <#
    .SYNOPSIS
    Windows-specific VCP unloading using device management APIs.
    
    .DESCRIPTION
    Uses Windows Device Manager / PnP APIs to disable/enable the specific FTDI device
    to force driver reload in D2XX mode.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialNumber
    )

    try {
        Write-Verbose "Looking for FTDI device with serial $SerialNumber in Windows registry..."
        
        # Find device instance ID from registry
        $ftdibusPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\FTDIBUS'
        if (-not (Test-Path $ftdibusPath)) {
            Write-Warning "FTDIBUS registry path not found"
            return $false
        }

        $deviceInstanceId = $null
        $comboKeys = Get-ChildItem $ftdibusPath -ErrorAction SilentlyContinue
        
        foreach ($comboKey in $comboKeys) {
            if ($comboKey.PSChildName -match "VID_[0-9A-Fa-f]{4}\+PID_[0-9A-Fa-f]{4}\+$SerialNumber") {
                $instanceKeys = Get-ChildItem $comboKey.PSPath -ErrorAction SilentlyContinue
                if ($instanceKeys) {
                    $deviceInstanceId = "$($comboKey.PSChildName)\$($instanceKeys[0].PSChildName)"
                    break
                }
            }
        }

        if (-not $deviceInstanceId) {
            Write-Warning "Could not find device instance for serial $SerialNumber"
            return $false
        }

        Write-Verbose "Found device instance: $deviceInstanceId"

        # Use pnputil or devcon to disable/enable device
        # First try pnputil (available on Windows 10+)
        $pnputilPath = "$env:SystemRoot\System32\pnputil.exe"
        if (Test-Path $pnputilPath) {
            Write-Verbose "Attempting device restart via pnputil..."
            
            # Disable device
            $disableResult = & $pnputilPath /disable-device "FTDIBUS\$deviceInstanceId" 2>$null
            Start-Sleep -Seconds 2
            
            # Enable device  
            $enableResult = & $pnputilPath /enable-device "FTDIBUS\$deviceInstanceId" 2>$null
            Start-Sleep -Seconds 2
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Device restart via pnputil succeeded" -ForegroundColor Green
                return $true
            } else {
                Write-Warning "pnputil device restart failed (exit code: $LASTEXITCODE)"
            }
        }

        # Fallback: suggest manual replug
        Write-Warning @"
Automatic VCP unload methods failed for device $SerialNumber.
Manual options:
1. Unplug and replug the USB device
2. Use Device Manager to disable/enable the device
3. Switch driver in Device Manager: Ports -> USB Serial Port -> Update Driver -> USB Serial Converter
"@
        return $false

    } catch {
        Write-Error "Windows VCP unload failed: $_"
        return $false
    }
}