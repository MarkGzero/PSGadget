# Set-PsGadgetGpio.ps1
# Public GPIO control function for FTDI devices

function Set-PsGadgetGpio {
    <#
    .SYNOPSIS
    Controls GPIO pins on connected FTDI devices.
    
    .DESCRIPTION
    Sets ACBUS GPIO pins on FTDI devices (FT232H, FT2232H) to HIGH or LOW states.
    Supports timing control and multiple pin operations. Uses MPSSE commands for
    precise hardware control.
    
    .PARAMETER DeviceIndex
    Index of the FTDI device to control (from List-PsGadgetFtdi)
    
    .PARAMETER Pins
    Array of ACBUS pin numbers to control (0-7)
    ACBUS0=pin21, ACBUS1=pin25, ACBUS2=pin26, ACBUS3=pin27
    ACBUS4=pin28, ACBUS5=pin29, ACBUS6=pin30, ACBUS7=pin31 (FT232H)
    
    .PARAMETER State
    Pin state: HIGH/H/1 or LOW/L/0
    
    .PARAMETER DurationMs
    Optional duration to hold the pin state in milliseconds
    
    .PARAMETER SerialNumber
    Alternative to DeviceIndex - specify device by serial number
    
    .EXAMPLE
    Set-PsGadgetGpio -DeviceIndex 0 -Pins @(2, 4) -State HIGH
    Sets ACBUS2 and ACBUS4 to HIGH on first FTDI device
    
    .EXAMPLE
    Set-PsGadgetGpio -SerialNumber "ABC123" -Pins @(0) -State LOW -DurationMs 500
    Pulses ACBUS0 LOW for 500ms on device with serial "ABC123"
    
    .EXAMPLE
    # LED Control Example
    Set-PsGadgetGpio -DeviceIndex 0 -Pins @(2) -State HIGH   # Red LED on
    Set-PsGadgetGpio -DeviceIndex 0 -Pins @(4) -State HIGH   # Green LED on
    Set-PsGadgetGpio -DeviceIndex 0 -Pins @(2, 4) -State LOW  # Both LEDs off
    
    .NOTES
    Requires FTDI D2XX drivers and FTD2XX_NET.dll assembly.
    Pin mapping for FT232H: ACBUS0-7 = physical pins 21,25-31.
    Use List-PsGadgetFtdi to see available devices.
    #>
    
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByIndex', Position = 0)]
        [int]$DeviceIndex,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [string]$SerialNumber,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(0, 7)]
        [int[]]$Pins,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateSet('HIGH', 'LOW', 'H', 'L', '1', '0')]
        [string]$State,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60000)]
        [int]$DurationMs
    )
    
    try {
        # Get available devices
        $devices = Get-FtdiDeviceList
        if (-not $devices -or $devices.Count -eq 0) {
            throw "No FTDI devices found. Run List-PsGadgetFtdi to check available devices."
        }
        
        # Find target device
        $targetDevice = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByIndex') {
            if ($DeviceIndex -lt 0 -or $DeviceIndex -ge $devices.Count) {
                throw "Device index $DeviceIndex is out of range. Available devices: 0-$($devices.Count - 1)"
            }
            $targetDevice = $devices[$DeviceIndex]
        } else {
            $targetDevice = $devices | Where-Object { $_.SerialNumber -eq $SerialNumber }
            if (-not $targetDevice) {
                throw "No device found with serial number '$SerialNumber'"
            }
        }
        
        Write-Verbose "Targeting device: $($targetDevice.Description) ($($targetDevice.SerialNumber))"
        
        # Check if device is available
        if ($targetDevice.IsOpen) {
            Write-Warning "Device $($targetDevice.SerialNumber) appears to be in use by another application"
        }
        
        # Open device connection
        $connection = Connect-PsGadgetFtdi -Index $targetDevice.Index
        if (-not $connection) {
            throw "Failed to connect to FTDI device"
        }
        
        try {
            # Validate device supports MPSSE (FT232H, FT2232H, etc.)
            if ($targetDevice.Type -notin @('FT232H', 'FT2232H', 'FT4232H')) {
                Write-Warning "Device type '$($targetDevice.Type)' may not support MPSSE GPIO control"
            }
            
            Write-Verbose "Setting pins [$($Pins -join ',')] to $State"
            
            # Perform GPIO control
            $params = @{
                DeviceHandle = $connection
                Pins = $Pins
                Direction = $State
            }
            
            if ($DurationMs) {
                $params.DurationMs = $DurationMs
            }
            
            $success = Set-FtdiGpioPins @params
            
            if ($success) {
                $pinList = $Pins -join ', '
                $message = "Successfully set ACBUS pins [$pinList] to $State"
                if ($DurationMs) {
                    $message += " for $DurationMs ms"
                }
                Write-Host $message -ForegroundColor Green
            } else {
                throw "GPIO operation failed"
            }
            
        } finally {
            # Always close the device connection
            if ($connection -and $connection.Close) {
                try {
                    $connection.Close()
                } catch {
                    Write-Warning "Failed to close device connection: $_"
                }
            }
        }
        
    } catch {
        Write-Error "GPIO control failed: $_"
        throw
    }
}