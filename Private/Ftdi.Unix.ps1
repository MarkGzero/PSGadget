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

        # Use [System.IO.Directory]::GetDirectories() for sysfs traversal at every level.
        # Get-ChildItem on Linux sysfs (a virtual pseudo-filesystem) can return DirectoryInfo
        # objects with null FullName/Name properties for certain kernel-internal nodes.
        # Calling any method on those null-property objects throws 'You cannot call a method
        # on a null-valued expression'.  Directory.GetDirectories() returns plain string[]
        # (absolute path strings), which are never null, avoiding the problem entirely.
        foreach ($devDir in [System.IO.Directory]::GetDirectories($sysDevicesPath)) {
            try {
                $vendorFile = Join-Path $devDir 'idVendor'

                # Only process FTDI devices (VID 0403)
                if (-not ([System.IO.File]::Exists($vendorFile))) { continue }

                # Use [System.IO.File]::ReadAllText() for all sysfs attribute reads.
                # Get-Content on Linux sysfs can produce null or behave unexpectedly even
                # with -ErrorAction SilentlyContinue; File.ReadAllText() returns a plain
                # string (never null) and throws IOException on failure, which is caught by
                # the per-device try/catch below.
                $readSysfs = {
                    param([string]$path)
                    if ([System.IO.File]::Exists($path)) {
                        try { return [System.IO.File]::ReadAllText($path).Trim() } catch { return '' }
                    }
                    return ''
                }

                $vid     = & $readSysfs $vendorFile
                if ($vid -ne '0403') { continue }

                $pid     = & $readSysfs (Join-Path $devDir 'idProduct')
                $serial  = & $readSysfs (Join-Path $devDir 'serial')
                $product = & $readSysfs (Join-Path $devDir 'product')
                $busNum  = & $readSysfs (Join-Path $devDir 'busnum')
                $devNum  = & $readSysfs (Join-Path $devDir 'devnum')

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
                # DeviceId format matches IoT/Windows output: 0x + 4-char VID + 8-char device ID
                # e.g. VID=0403 PID=6014 -> 0x040300006014
                $deviceId = '0x{0}0000{1}' -f $vid.ToUpper(), $pid.ToUpper()

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
                # Include ScriptStackTrace so the exact failing line is visible in -Verbose output.
                Write-Verbose "  sysfs: skipped device '$devDir': $($_.Exception.Message)"
                Write-Verbose "    at: $($_.ScriptStackTrace -replace '\n','; ')"
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
        [int]$Index,

        # When provided (from IoT enumeration), use this metadata directly and skip sysfs re-enum.
        # On macOS there is no /sys/bus/usb/devices, so sysfs always returns stubs. The stub at
        # index 0 is FT232H (GpioMethod=MPSSE) — if a real FT232R is at index 0, re-enumerating
        # via stubs would assign the wrong GpioMethod, silently routing all GPIO through MPSSE.
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$DeviceInfo = $null
    )

    # Get device metadata: prefer caller-supplied DeviceInfo, fall back to sysfs enumeration.
    if (-not $DeviceInfo) {
        $devices    = Invoke-FtdiUnixEnumerate
        $DeviceInfo = if ($Index -lt $devices.Count) { $devices[$Index] } else { $null }
    }

    $serial  = if ($DeviceInfo) { $DeviceInfo.SerialNumber } else { "DEV$Index" }
    $desc    = if ($DeviceInfo) { $DeviceInfo.Description  } else { "Unknown FTDI Device" }
    $type    = if ($DeviceInfo) { $DeviceInfo.Type         } else { 'FT232H' }
    $locId   = if ($DeviceInfo) { $DeviceInfo.LocationId   } else { "usb-bus?-dev?" }
    $caps    = Get-FtdiChipCapabilities -TypeName $type

    # ---------------------------------------------------------------------------
    # Path A: native P/Invoke (libftd2xx.so loaded) - real hardware handle
    # ---------------------------------------------------------------------------
    if ($script:FtdiNativeAvailable) {
        try {
            Write-Verbose "Invoke-FtdiUnixOpen: opening device $Index via native P/Invoke (FT_Open)"
            $nativeHandle = Invoke-FtdiNativeOpen -Index $Index

            $conn = [PSCustomObject]@{
                Device         = $null          # No FTD2XX_NET.FTDI object on Linux
                NativeHandle   = $nativeHandle  # IntPtr from FT_Open
                Index          = $Index
                SerialNumber   = $serial
                Description    = $desc
                Type           = $type
                LocationId     = $locId
                IsOpen         = $true
                GpioMethod     = $caps.GpioMethod
                GpioPins       = $caps.GpioPins
                HasMpsse       = $caps.HasMpsse
                MpsseEnabled   = $caps.HasMpsse
                CapabilityNote = $caps.CapabilityNote
                Platform       = 'Unix'
            }

            $conn | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
                if ($this.IsOpen -and $this.NativeHandle -ne [IntPtr]::Zero) {
                    Invoke-FtdiNativeClose -Handle $this.NativeHandle
                }
                $this.IsOpen     = $false
                $this.NativeHandle = [IntPtr]::Zero
            } | Out-Null

            Write-Verbose "Invoke-FtdiUnixOpen: device $Index opened via native D2XX handle"
            return $conn

        } catch {
            Write-Verbose "Invoke-FtdiUnixOpen: native open failed ($($_.Exception.Message)); falling back to stub"
        }
    }

    # ---------------------------------------------------------------------------
    # Path B: stub (native lib not loaded or open failed)
    # ---------------------------------------------------------------------------
    Write-Verbose "Creating stub connection for device $Index (Unix)"

    return [PSCustomObject]@{
        Device         = $null
        NativeHandle   = [IntPtr]::Zero
        Index          = $Index
        SerialNumber   = $serial
        Description    = $desc
        Type           = $type
        LocationId     = $locId
        IsOpen         = $true
        GpioMethod     = $caps.GpioMethod
        GpioPins       = $caps.GpioPins
        HasMpsse       = $caps.HasMpsse
        MpsseEnabled   = $caps.HasMpsse
        CapabilityNote = $caps.CapabilityNote
        Platform       = 'Unix (STUB)'
    } | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
        $this.IsOpen = $false
    } -PassThru
}

function Invoke-FtdiUnixClose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$Connection
    )

    try {
        if ($null -ne $Connection -and $Connection.PSObject.Methods['Close']) {
            $Connection.Close()
        }
    } catch {
        Write-Warning "Invoke-FtdiUnixClose: $_"
    }
}