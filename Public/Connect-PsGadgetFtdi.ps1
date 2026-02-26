# Connect-PsGadgetFtdi.ps1
# Connect to an FTDI device

function Connect-PsGadgetFtdi {
    <#
    .SYNOPSIS
    Connects to an FTDI device for GPIO and communication control.
    
    .DESCRIPTION
    Opens a direct connection to an FTDI device using the appropriate platform backend.
    Returns a connection object that can be used for MPSSE GPIO control, serial 
    communication, and other FTDI operations.
    
    .PARAMETER Index
    The index of the FTDI device to connect to. Use List-PsGadgetFtdi to see available devices.
    
    .PARAMETER SerialNumber
    Alternative to Index - connect to device by its serial number
    
    .PARAMETER LocationId
    Alternative to Index/SerialNumber - connect by USB LocationId (hub+port address).
    LocationId is stable for a fixed physical USB port. Use List-PsGadgetFtdi to find the value.

    $Connection.Close()
    
    .EXAMPLE
    $Connection = Connect-PsGadgetFtdi -SerialNumber "ABC123"
    # Use connection for GPIO or serial operations
    $Connection.Close()
    
    .EXAMPLE
    $Connection = Connect-PsGadgetFtdi -LocationId 197634
    # Stable USB port addressing - same port always opens the same physical device
    $Connection.Close()

    .OUTPUTS
    System.Object
    A connection object with platform-specific device handle and control methods.
    #>
    
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIndex', Position = 0)]
        [int]$Index,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [string]$SerialNumber,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByLocation')]
        [string]$LocationId
    )
    
    try {
        # Get available devices for validation
        $devices = Get-FtdiDeviceList
        if (-not $devices -or $devices.Count -eq 0) {
            throw "No FTDI devices found. Run List-PsGadgetFtdi to check available devices."
        }
        
        # Determine target device
        $targetDevice = $null
        $deviceIndex = -1
        
        if ($PSCmdlet.ParameterSetName -eq 'ByIndex') {
            if ($Index -lt 0 -or $Index -ge $devices.Count) {
                throw "Device index $Index is out of range. Available devices: 0-$($devices.Count - 1)"
            }
            $deviceIndex = $Index
            $targetDevice = $devices[$Index]
        } elseif ($PSCmdlet.ParameterSetName -eq 'BySerial') {
            $targetDevice = $devices | Where-Object { $_.SerialNumber -eq $SerialNumber }
            if (-not $targetDevice) {
                throw "No device found with serial number '$SerialNumber'"
            }
            $deviceIndex = $targetDevice.Index
        } else {
            # ByLocation - match on LocationId (shown by List-PsGadgetFtdi)
            $targetDevice = $devices | Where-Object { "$($_.LocationId)" -eq $LocationId } | Select-Object -First 1
            if (-not $targetDevice) {
                throw "No device found with LocationId '$LocationId'. Run List-PsGadgetFtdi to see available LocationIds."
            }
            $deviceIndex = $targetDevice.Index
        }
        
        Write-Verbose "Connecting to: $($targetDevice.Description) ($($targetDevice.SerialNumber))"
        
        # Check if device is already in use
        if ($targetDevice.IsOpen) {
            Write-Warning "Device appears to be in use by another application"
        }
        
        # Call platform-specific opening function
        if ($PSVersionTable.PSVersion.Major -le 5 -or [System.Environment]::OSVersion.Platform -eq 'Win32NT') {
            Write-Verbose "Using Windows FTDI backend for connection"
            $connection = Invoke-FtdiWindowsOpen -DeviceInfo $targetDevice
        } else {
            Write-Verbose "Using Unix FTDI backend for connection"
            $connection = Invoke-FtdiUnixOpen -Index $deviceIndex
        }
        
        if (-not $connection) {
            throw "Failed to establish connection to FTDI device"
        }
        
        Write-Verbose "Successfully connected to FTDI device $deviceIndex"
        return $connection
        
    } catch {
        Write-Error "Failed to connect to FTDI device: $_"
        throw
    }
}