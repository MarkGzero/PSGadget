# Mpy.Backend.ps1
# MicroPython backend functionality using mpremote

# Known USB Vendor IDs for MicroPython / CircuitPython boards
$script:MpyKnownVids = @{
    '303A' = @{ Manufacturer = 'Espressif (ESP32)';          IsMicroPython = $true  }
    '2E8A' = @{ Manufacturer = 'Raspberry Pi (RP2040/RP2350)'; IsMicroPython = $true  }
    '0483' = @{ Manufacturer = 'STMicroelectronics';          IsMicroPython = $true  }
    '239A' = @{ Manufacturer = 'Adafruit (CircuitPython)';    IsMicroPython = $true  }
    '1D50' = @{ Manufacturer = 'MicroPython (Pyboard)';       IsMicroPython = $true  }
    '0403' = @{ Manufacturer = 'FTDI';                        IsMicroPython = $false }
    '1A86' = @{ Manufacturer = 'WCH (CH340)';                 IsMicroPython = $false }
    '10C4' = @{ Manufacturer = 'Silicon Labs (CP210x)';       IsMicroPython = $false }
}

function Get-MpyPortList {
    # Platform-aware serial port enumeration for MicroPython device discovery.
    # Default: returns port name strings. With -Detailed: returns enriched objects.
    [CmdletBinding()]
    param(
        [switch]$Detailed
    )

    $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

    if ($isWindows) {
        if ($Detailed) {
            return Invoke-MpyWindowsPortList
        } else {
            # Basic list - just port names sorted
            $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
            if (-not $ports -or @($ports).Count -eq 0) {
                Write-Verbose "No real serial ports found on Windows; returning stub port"
                return @('COM99 (STUB)')
            }
            return $ports
        }
    } else {
        # Unix: basic .NET enumeration for now
        $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
        if (-not $Detailed) {
            if (-not $ports -or @($ports).Count -eq 0) {
                Write-Verbose "No real serial ports found on Unix; returning stub port"
                return @('/dev/ttyUSB0 (STUB)')
            }
            return $ports
        }
        # Build minimal objects for Unix (no WMI available)
        if (-not $ports -or @($ports).Count -eq 0) {
            Write-Verbose "No real serial ports found on Unix; returning stub detailed object"
            return @([PSCustomObject]@{
                Port          = '/dev/ttyUSB0'
                FriendlyName  = '/dev/ttyUSB0 (STUB)'
                VID           = 'N/A'
                PID           = 'N/A'
                Manufacturer  = 'Unknown (STUB)'
                IsMicroPython = $false
                Status        = 'Stub'
            })
        }
        return $ports | ForEach-Object {
            [PSCustomObject]@{
                Port          = $_
                FriendlyName  = $_
                VID           = 'N/A'
                PID           = 'N/A'
                Manufacturer  = 'Unknown'
                IsMicroPython = $false
                Status        = 'Unknown'
            }
        }
    }
}

function Invoke-MpyWindowsPortList {
    # Windows-specific: enrich serial ports with VID/PID and board identification via WMI.
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()

    $results = @()

    try {
        $wmiPorts = Get-WmiObject -Class Win32_SerialPort -ErrorAction SilentlyContinue
        foreach ($port in $wmiPorts) {
            $vid = $null
            $pid = $null

            if ($port.PNPDeviceID -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
                $vid = $Matches[1].ToUpper()
                $pid = $Matches[2].ToUpper()
            }

            if ($vid -and $script:MpyKnownVids.ContainsKey($vid)) {
                $mfgInfo = $script:MpyKnownVids[$vid]
                $mfg    = $mfgInfo.Manufacturer
                $isMpy  = $mfgInfo.IsMicroPython
            } else {
                $mfg   = if ($port.Manufacturer) { $port.Manufacturer } else { 'Unknown' }
                $isMpy = $false
            }

            $results += [PSCustomObject]@{
                Port          = $port.DeviceID
                FriendlyName  = $port.Name
                VID           = if ($vid) { "0x$vid" } else { 'N/A' }
                PID           = if ($pid) { "0x$pid" } else { 'N/A' }
                Manufacturer  = $mfg
                IsMicroPython = $isMpy
                Status        = $port.Status
            }
        }
    } catch {
        Write-Verbose "WMI serial port enumeration failed: $($_.Exception.Message)"
    }

    # MicroPython devices first, then alphabetical by port name
    return $results | Sort-Object -Property @{Expression = 'IsMicroPython'; Descending = $true}, Port
}

function Invoke-MpyBackendGetInfo {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialPort
    )
    
    try {
        # TODO: Implement actual mpremote device info retrieval
        $MpremoteArgs = @("connect", $SerialPort, "exec", "import sys; print(sys.implementation)")
        
        throw [System.NotImplementedException]::new("MicroPython mpremote info retrieval not yet implemented")
        
    } catch [System.NotImplementedException] {
        # Return stub device info
        return @{
            Port = $SerialPort
            PythonVersion = "MicroPython v1.20.0 on 2023-04-26 (STUB)"
            Board = "Generic ESP32 board (STUB)"  
            ChipFamily = "ESP32 (STUB)"
            FlashSize = "4MB (STUB)"
            FreeMemory = 102400
            Connected = $true
            Stub = $true
        }
    } catch {
        Write-Warning "Failed to get MicroPython device info: $($_.Exception.Message)"
        throw
    }
}

function Invoke-MpyBackendExecute {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialPort,
        
        [Parameter(Mandatory = $true)]
        [string]$Code
    )
    
    try {
        # TODO: Implement actual mpremote code execution
        $MpremoteArgs = @("connect", $SerialPort, "exec", $Code)
        
        throw [System.NotImplementedException]::new("MicroPython mpremote code execution not yet implemented")
        
    } catch [System.NotImplementedException] {
        # Return stub execution result
        $StubOutput = @"
>>> $Code 
# Executed successfully (STUB MODE)
# Output would appear here in real implementation
>>> 
"@
        return $StubOutput
    } catch {
        Write-Warning "Failed to execute MicroPython code: $($_.Exception.Message)"
        throw
    }
}

function Invoke-MpyBackendPushFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialPort,
        
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,
        
        [Parameter(Mandatory = $false)]
        [string]$RemotePath
    )
    
    try {
        # TODO: Implement actual mpremote file push
        if ([string]::IsNullOrEmpty($RemotePath)) {
            $RemotePath = Split-Path -Leaf $LocalPath
        }
        
        $MpremoteArgs = @("connect", $SerialPort, "cp", $LocalPath, ":$RemotePath")
        
        throw [System.NotImplementedException]::new("MicroPython mpremote file push not yet implemented")
        
    } catch [System.NotImplementedException] {
        $FileItem = Get-Item -Path $LocalPath -ErrorAction SilentlyContinue
        $FileSize = if ($FileItem) { $FileItem.Length } else { 0 }
        Write-Verbose "Pushed file $LocalPath -> $RemotePath ($FileSize bytes) (STUB MODE)"
    } catch {
        Write-Warning "Failed to push file via MicroPython: $($_.Exception.Message)"
        throw
    }
}

function Test-MpyBackendConnection {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialPort
    )
    
    try {
        # TODO: Implement actual mpremote connection test
        throw [System.NotImplementedException]::new("MicroPython connection test not yet implemented")
        
    } catch [System.NotImplementedException] {
        # Return stub connection test (always true for now)
        return $true
    } catch {
        Write-Warning "Failed to test MicroPython connection: $($_.Exception.Message)"
        return $false
    }
}