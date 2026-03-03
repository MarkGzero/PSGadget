# Ftdi.Unix.ps1
# Unix-specific FTDI implementation (Linux/macOS)

function Invoke-FtdiUnixEnumerate {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()

    # FTDI USB Product ID -> chip type name
    $ftdiPidMap = @{
        '6001' = 'FT232R'
        '6010' = 'FT2232H'
        '6011' = 'FT4232H'
        '6014' = 'FT232H'
        '6015' = 'FT-X Series'
        '0600' = 'FT232BM'
        '0601' = 'FT245BM'
    }

    $sysDevicesPath = '/sys/bus/usb/devices'

    # If sysfs is not available (non-Linux Unix / container), fall back to stubs.
    if (-not (Test-Path $sysDevicesPath)) {
        Write-Verbose "sysfs not available; returning Unix stub devices"
        return Invoke-FtdiUnixStubs
    }

    try {
        $found = @()

        Get-ChildItem -Path $sysDevicesPath -Directory -ErrorAction Stop | ForEach-Object {
            # Wrap each device entry in its own try/catch so one malformed or
            # inaccessible sysfs entry cannot abort the entire enumeration.
            try {
                $devDir    = $_.FullName
                $vendorFile = Join-Path $devDir 'idVendor'

                # Only process FTDI devices (VID 0403)
                if (-not (Test-Path $vendorFile)) { return }

                # Cast all Get-Content results to [string] before calling any methods.
                # sysfs files for optional attributes (serial, product) may not exist;
                # Get-Content returns $null for missing files.  Calling .Trim() on $null
                # throws 'You cannot call a method on a null-valued expression'.
                # Casting $null to [string] yields '' so .Trim() always succeeds.
                $vid     = ([string](Get-Content $vendorFile                          -Raw -ErrorAction SilentlyContinue)).Trim()
                if ($vid -ne '0403') { return }

                $pid     = ([string](Get-Content (Join-Path $devDir 'idProduct') -Raw -ErrorAction SilentlyContinue)).Trim()
                $serial  = ([string](Get-Content (Join-Path $devDir 'serial')    -Raw -ErrorAction SilentlyContinue)).Trim()
                $product = ([string](Get-Content (Join-Path $devDir 'product')   -Raw -ErrorAction SilentlyContinue)).Trim()
                $busNum  = ([string](Get-Content (Join-Path $devDir 'busnum')    -Raw -ErrorAction SilentlyContinue)).Trim()
                $devNum  = ([string](Get-Content (Join-Path $devDir 'devnum')    -Raw -ErrorAction SilentlyContinue)).Trim()

                # Find associated /dev/ttyUSBx.
                # USB sysfs layout: <devDir>/<devBase>:1.0/ttyUSB0
                # e.g. /sys/bus/usb/devices/1-2/1-2:1.0/ttyUSB0
                #
                # Use [System.IO.Directory]::GetDirectories() rather than Get-ChildItem.
                # PowerShell's Get-ChildItem produces DirectoryInfo objects backed by
                # sysfs virtual nodes; some of those nodes expose null property values
                # (Name, FullName) that crash any .Trim() / string interpolation downstream.
                # .NET Directory methods return plain strings (paths) which are never null.
                $isVcp      = $false
                $locationId = "usb-bus$busNum-dev$devNum"
                try {
                    $devBaseName = [System.IO.Path]::GetFileName($devDir)   # e.g. "1-2"
                    foreach ($ifPath in [System.IO.Directory]::GetDirectories($devDir, "${devBaseName}:*")) {
                        foreach ($ttyPath in [System.IO.Directory]::GetDirectories($ifPath, 'ttyUSB*')) {
                            $locationId = '/dev/' + [System.IO.Path]::GetFileName($ttyPath)
                            $isVcp      = $true
                            break
                        }
                        if ($isVcp) { break }
                    }
                } catch {
                    # ttyUSB probe failed for this device; treat as non-VCP (safe default)
                    Write-Verbose "  sysfs: ttyUSB probe failed for '${devDir}': $($_.Exception.Message)"
                }

                # If the kernel ftdi_sio (VCP) driver claimed the device, a ttyUSBx will exist.
                # D2XX / libftdi requires that driver to be unbound first.

                $typeName = if ($ftdiPidMap.ContainsKey($pid)) { $ftdiPidMap[$pid] } else { "FTDI-$pid" }
                $caps     = Get-FtdiChipCapabilities -TypeName $typeName
                $deviceId = '0x{0}{1}' -f ([string]$vid).ToUpper(), ([string]$pid).ToUpper()

                $found += [PSCustomObject]@{
                    Index          = $found.Count
                    Type           = $typeName
                    Description    = if ($product) { $product } else { "FTDI $typeName" }
                    SerialNumber   = if ($serial)  { $serial }  else { '' }
                    LocationId     = $locationId
                    IsOpen         = $false
                    Flags          = '0x00000000'
                    DeviceId       = $deviceId
                    Handle         = $null
                    Driver         = if ($isVcp) { 'ftdi_sio (VCP)' } else { 'sysfs' }
                    Platform       = 'Unix'
                    IsVcp          = $isVcp
                    GpioMethod     = $caps.GpioMethod
                    GpioPins       = $caps.GpioPins
                    HasMpsse       = $caps.HasMpsse
                    CapabilityNote = $caps.CapabilityNote
                }
            } catch {
                # $_ here is the ErrorRecord; use $devDir (captured at top of try block) for context.
                Write-Verbose "  sysfs: skipped device '$devDir': $($_.Exception.Message)"
            }
        }

        if ($found.Count -eq 0) {
            Write-Verbose "No FTDI devices found via sysfs; returning Unix stub devices"
            return Invoke-FtdiUnixStubs
        }

        return $found

    } catch {
        Write-Warning "Unix sysfs enumeration failed: $($_.Exception.Message)"
        return Invoke-FtdiUnixStubs
    }
}

function Invoke-FtdiUnixStubs {
    # Returns hardcoded stub device objects for dev/CI environments with no hardware.
    $caps232H = Get-FtdiChipCapabilities -TypeName 'FT232H'
    $caps232R = Get-FtdiChipCapabilities -TypeName 'FT232R'
    return @(
        [PSCustomObject]@{
            Index          = 0
            Type           = 'FT232H'
            Description    = 'FT232H USB-Serial (Unix STUB)'
            SerialNumber   = 'UNIXSTUB001'
            LocationId     = '/dev/ttyUSB0'
            IsOpen         = $false
            Flags          = '0x00000000'
            DeviceId       = '0x040300006014'
            Handle         = $null
            Driver         = 'libftdi (STUB)'
            Platform       = 'Unix'
            IsVcp          = $false
            GpioMethod     = $caps232H.GpioMethod
            GpioPins       = $caps232H.GpioPins
            HasMpsse       = $caps232H.HasMpsse
            CapabilityNote = $caps232H.CapabilityNote
        },
        [PSCustomObject]@{
            Index          = 1
            Type           = 'FT232R'
            Description    = 'FT232R USB UART (Unix STUB)'
            SerialNumber   = 'UNIXSTUB002'
            LocationId     = '/dev/ttyUSB1'
            IsOpen         = $false
            Flags          = '0x00000000'
            DeviceId       = '0x040300006001'
            Handle         = $null
            Driver         = 'libftdi (STUB)'
            Platform       = 'Unix'
            IsVcp          = $false
            GpioMethod     = $caps232R.GpioMethod
            GpioPins       = $caps232R.GpioPins
            HasMpsse       = $caps232R.HasMpsse
            CapabilityNote = $caps232R.CapabilityNote
        }
    )
}

function Invoke-FtdiUnixOpen {
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )
    
    try {
        # TODO: Implement Unix FTDI device open via libftdi or direct USB access
        # This could use libftdi bindings, pyftdi bridge, or direct USB device access
        
        throw [System.NotImplementedException]::new("Unix FTDI device open not yet implemented")
        
    } catch [System.NotImplementedException] {
        # Return enhanced stub connection for Unix development
        Write-Verbose "Creating stub connection for device $Index (Unix)"
        
        # Get device info for realistic stub
        $devices = Invoke-FtdiUnixEnumerate
        $targetDevice = if ($Index -lt $devices.Count) { $devices[$Index] } else {
            [PSCustomObject]@{
                SerialNumber = "UNIXSTUB$Index"
                Description = "Unix STUB Device"
                Type = "FT232H"
                LocationId = "/dev/ttyUSB$Index"
            }
        }
        
        return [PSCustomObject]@{
            Device = $null
            Index = $Index
            SerialNumber = $targetDevice.SerialNumber
            Description = $targetDevice.Description
            Type = $targetDevice.Type
            LocationId = $targetDevice.LocationId
            IsOpen = $true
            MpsseEnabled = $true
            Platform = "Unix (STUB)"
        } | Add-Member -MemberType ScriptMethod -Name 'Close' -Value { $this.IsOpen = $false } -PassThru |
          Add-Member -MemberType ScriptMethod -Name 'Write' -Value { 
            param([byte[]]$data, [int]$length, [ref]$bytesWritten)
            $bytesWritten.Value = $length
            return 0  # Simulate FT_OK equivalent
          } -PassThru |
          Add-Member -MemberType ScriptMethod -Name 'Read' -Value { 
            param([byte[]]$buffer, [int]$length, [ref]$bytesRead)
            $bytesRead.Value = 1
            $buffer[0] = 0x55  # Stub data
            return 0  # Simulate FT_OK equivalent
          } -PassThru
        
    } catch {
        Write-Error "Failed to open Unix FTDI device: $_"
        return $null
    }
}

function Invoke-FtdiUnixClose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Handle
    )
    
    try {
        # TODO: Implement Unix FTDI device close via libftdi
        throw [System.NotImplementedException]::new("Unix FTDI device close not yet implemented")
        
    } catch [System.NotImplementedException] {
        Write-Verbose "Closed FTDI device handle $Handle on Unix (STUB MODE)"
        return [PSCustomObject]@{
            Success = $true
            Message = "Device closed successfully (Unix STUB)"
        }
    } catch {
        Write-Warning "Failed to close Unix FTDI device: $($_.Exception.Message)"
        throw
    }
}