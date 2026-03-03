# Initialize-FtdiAssembly.ps1
# Version-aware FTDI assembly loading
#
# Loading strategy by runtime:
#   PS 5.1  / .NET Framework 4.8  : lib/net48/FTD2XX_NET.dll
#   PS 7.0-7.3 / .NET 6-7         : lib/netstandard20/FTD2XX_NET.dll
#   PS 7.4+ / .NET 8+             : lib/net8/ IoT DLLs (primary) +
#                                   lib/netstandard20/FTD2XX_NET.dll (FT232R CBUS fallback, Windows only)
#
# Script-scope flags set by this function:
#   $script:FtdiInitialized      - FTD2XX_NET.dll loaded successfully
#   $script:IotBackendAvailable  - .NET IoT DLLs loaded; IoT backend will be used
#   $script:FTDI_OK              - FT_STATUS.FT_OK constant (when FTD2XX_NET loaded)

function Initialize-FtdiAssembly {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ModuleRoot = $PSScriptRoot
    )

    # Initialise flags; set to $true only on successful load below
    $script:IotBackendAvailable  = $false
    $script:D2xxLoaded           = $false
    $script:FtdiSharpAvailable   = $false

    try {
        $psVersion  = $PSVersionTable.PSVersion.Major
        $dotnetMajor = [System.Environment]::Version.Major                     # 4 on net48, 6/8/9 on modern
        $isWindows  = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

        # ------------------------------------------------------------------
        # Path A: PS 7.4+ on .NET 8+ -> load IoT DLLs from lib/net8/
        #         Also load FTD2XX_NET (netstandard20) on Windows as fallback
        #         for CBUS devices (FT232R) that the IoT library does not cover.
        # ------------------------------------------------------------------
        if ($psVersion -ge 7 -and $dotnetMajor -ge 8) {
            Write-Verbose "PS $psVersion / .NET $dotnetMajor detected - attempting IoT backend (lib/net8/)"

            $iotDlls = @(
                'Microsoft.Extensions.Logging.Abstractions.dll',
                'UnitsNet.dll',
                'System.Device.Gpio.dll',
                'Iot.Device.Bindings.dll'
            )

            $iotDir    = Join-Path (Join-Path $ModuleRoot 'lib') 'net8'
            $iotLoaded = $true

            foreach ($dll in $iotDlls) {
                $dllPath = Join-Path $iotDir $dll
                if (Test-Path $dllPath) {
                    try {
                        [void][Reflection.Assembly]::LoadFrom($dllPath)
                        Write-Verbose "  Loaded IoT DLL: $dll"
                    } catch {
                        Write-Warning "  Failed to load IoT DLL '$dll': $_"
                        $iotLoaded = $false
                    }
                } else {
                    Write-Warning "  IoT DLL not found: $dllPath"
                    $iotLoaded = $false
                }
            }

            if ($iotLoaded) {
                # Verify key types are accessible
                $null = [Iot.Device.FtCommon.FtCommon]
                $null = [Iot.Device.Ft232H.Ft232HDevice]
                $null = [System.Device.Gpio.GpioController]
                Write-Verbose "IoT backend managed DLLs loaded - using Iot.Device.Bindings"

                # On Linux/macOS the managed DLLs load fine but the native D2XX .so is also
                # required at runtime.  Probe common install locations and warn early so the
                # user gets a clear message at module import rather than a wall of P/Invoke
                # errors when they first call Connect-PsGadgetFtdi.
                if (-not $isWindows) {
                    $nativeLibLocations = @(
                        '/usr/local/lib/libftd2xx.so',
                        '/usr/lib/libftd2xx.so',
                        '/usr/lib/x86_64-linux-gnu/libftd2xx.so',
                        '/usr/lib/aarch64-linux-gnu/libftd2xx.so',
                        '/usr/lib/arm-linux-gnueabihf/libftd2xx.so'
                    )
                    $nativeFound = $nativeLibLocations | Where-Object { Test-Path $_ } | Select-Object -First 1
                    if ($nativeFound) {
                        Write-Verbose "  Native libftd2xx.so found at: $nativeFound"

                        # .NET P/Invoke on Linux searches LD_LIBRARY_PATH and the assembly directory.
                        # Snap-confined PowerShell processes cannot see /usr/local/lib via ldconfig.
                        # Fix 1: add the native lib's directory to LD_LIBRARY_PATH for this session.
                        $nativeLibDir = [System.IO.Path]::GetDirectoryName($nativeFound)
                        $existing = $env:LD_LIBRARY_PATH
                        if (-not ($existing -split ':' | Where-Object { $_ -eq $nativeLibDir })) {
                            $env:LD_LIBRARY_PATH = if ($existing) { "${nativeLibDir}:${existing}" } else { $nativeLibDir }
                            Write-Verbose "  Set LD_LIBRARY_PATH += $nativeLibDir"
                        }

                        # Fix 2: copy libftd2xx.so into lib/net8/ so that .NET assembly-directory
                        # probing finds it regardless of LD_LIBRARY_PATH restrictions.
                        # A symlink is not used: snap-confined PowerShell processes cannot follow
                        # symlinks that point outside the snap directory tree, so the symlink would
                        # appear present but the dynamic linker would fail to open it.
                        $net8Dir   = Join-Path (Join-Path $ModuleRoot 'lib') 'net8'
                        $localCopy = Join-Path $net8Dir 'libftd2xx.so'
                        if (-not (Test-Path $localCopy)) {
                            try {
                                Copy-Item -Path $nativeFound -Destination $localCopy -ErrorAction Stop
                                Write-Verbose "  Copied libftd2xx.so to $localCopy"
                            } catch {
                                Write-Verbose "  Could not copy libftd2xx.so to lib/net8/ (non-fatal): $_"
                            }
                        } else {
                            Write-Verbose "  lib/net8/libftd2xx.so already present"
                        }

                        # Fix 3: probe that GetDevices() can reach the native lib.
                        # Two distinct failure modes:
                        #   a) 'Unable to load shared library' -- the native libftd2xx.so is not
                        #      visible to the runtime (missing file, wrong path, snap sandbox).
                        #      IotBackendAvailable = $false; sysfs handles enumeration.
                        #   b) Any other exception (device busy, ftdi_sio holds the device, etc.) --
                        #      the DLLs are correctly loaded; the conflict is ephemeral.
                        #      IotBackendAvailable = $true; after 'sudo rmmod ftdi_sio' the user
                        #      can call Connect-PsGadgetFtdi without reimporting.
                        try {
                            $null = [Iot.Device.FtCommon.FtCommon]::GetDevices()
                            $script:IotBackendAvailable = $true
                            Write-Verbose "  IoT native probe: OK - GetDevices() succeeded"
                        } catch {
                            $exMsg = $_.Exception.Message
                            if ($exMsg -match 'Unable to load shared library|DllNotFoundException') {
                                Write-Verbose "  IoT native probe: native library not loadable - backend disabled"
                                Write-Verbose "  Error: $exMsg"
                                # IotBackendAvailable stays $false
                            } else {
                                $script:IotBackendAvailable = $true
                                Write-Verbose "  IoT native probe: GetDevices() call failed (non-fatal: $($_.Exception.GetType().Name))"
                                Write-Verbose "  DLLs are loaded; likely ftdi_sio holds the device."
                                Write-Verbose "  Run: sudo rmmod ftdi_sio   then connect without reimporting."
                            }
                        }

                        # NOTE: FTD2XX_NET.dll (netstandard20) is Windows-only.
                        # It contains [DllImport("kernel32.dll")] calls (FreeLibrary/LoadLibrary) in
                        # its finalizer. Loading it on Linux causes an unhandled DllNotFoundException
                        # crash at GC finalization time. FT232R EEPROM/CBUS operations via FTD2XX_NET
                        # are therefore not available on Linux; stub mode is the correct fallback.
                    } else {
                        # Detect arch to guide the user to the right tarball
                        $arch = ''
                        try { $arch = (uname -m 2>$null).Trim() } catch {}
                        $archTgz  = switch ($arch) {
                            'x86_64'  { 'libftd2xx-linux-x86_64-1.4.34.tgz' }
                            'aarch64' { 'libftd2xx-linux-arm-v8-1.4.34.tgz' }
                            'armv7l'  { 'libftd2xx-linux-arm-v7-hf-1.4.34.tgz' }
                            default   { 'libftd2xx-linux-<arch>-1.4.34.tgz' }
                        }
                        $archUrl  = switch ($arch) {
                            'x86_64'  { 'https://ftdichip.com/wp-content/uploads/2025/11/libftd2xx-linux-x86_64-1.4.34.tgz' }
                            'aarch64' { 'https://ftdichip.com/drivers/d2xx-drivers/ (select ARM64 v8)' }
                            'armv7l'  { 'https://ftdichip.com/drivers/d2xx-drivers/ (select ARM v7 HF)' }
                            default   { 'https://ftdichip.com/drivers/d2xx-drivers/' }
                        }
                        Write-Warning (
                            "IoT FTDI DLLs loaded but native 'libftd2xx.so' was not found. " +
                            "Hardware access will fall back to stub mode until it is installed.`n`n" +
                            "Run the following in your PowerShell session to install (arch: $arch):`n" +
                            "----------------------------------------------------------------------`n" +
                            "`$tgz = '$archTgz'`n" +
                            "`$url = '$archUrl'`n" +
                            "Invoke-WebRequest `$url -OutFile `"/tmp/`$tgz`"`n" +
                            "tar xzf `"/tmp/`$tgz`" -C /tmp`n" +
                            "sudo sh -c 'find /tmp/release -name `"libftd2xx.so.*`" -exec cp {} /usr/local/lib/ \;'`n" +
                            "sudo sh -c 'ln -sf /usr/local/lib/libftd2xx.so.* /usr/local/lib/libftd2xx.so'`n" +
                            "sudo ldconfig`n" +
                            "# NOTE: D2XX and the VCP kernel driver (ftdi_sio) cannot share the same device.`n" +
                            "# If your device only appears under 'List-PsGadgetFtdi -ShowVCP' (i.e. shows as`n" +
                            "# /dev/ttyUSBx), you MUST unload the VCP module so D2XX can claim the device:`n" +
                            "`n" +
                            "#   sudo rmmod ftdi_sio`n" +
                            "`n" +
                            "# This lasts until the next reboot. To make it permanent across reboots:`n" +
                            "#   echo 'blacklist ftdi_sio' | sudo tee /etc/modprobe.d/ftdi-d2xx.conf`n" +
                            "#   sudo update-initramfs -u`n" +
                            "# To restore VCP mode at any time: sudo modprobe ftdi_sio`n" +
                            "----------------------------------------------------------------------`n" +
                            "Then re-import: Import-Module PSGadget -Force"
                        )
                    }
                } else {
                    # Windows: IoT managed DLLs loaded; native ftd2xx.dll is in system PATH via CDM driver.
                    # Probe GetDevices() to confirm ftd2xx.dll is reachable before marking backend ready.
                    try {
                        $null = [Iot.Device.FtCommon.FtCommon]::GetDevices()
                        $script:IotBackendAvailable = $true
                        Write-Verbose "  IoT native probe: OK (Windows)"
                    } catch {
                        Write-Verbose "  IoT native probe failed on Windows: $($_.Exception.Message)"
                    }
                }
            } else {
                Write-Warning "IoT DLL loading incomplete - falling back to FTD2XX_NET backend"
            }

            # On Windows: also load FTD2XX_NET (netstandard20) for FT232R CBUS fallback.
            # On Unix:    FTD2XX_NET is not available; FT232R stays in stub mode.
            if ($isWindows) {
                $d2xxPath = Join-Path (Join-Path (Join-Path $ModuleRoot 'lib') 'netstandard20') 'FTD2XX_NET.dll'
                if (Test-Path $d2xxPath) {
                    try {
                        [void][Reflection.Assembly]::LoadFrom($d2xxPath)
                        $null = [FTD2XX_NET.FTDI]
                        $script:FTDI_OK    = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK
                        $script:D2xxLoaded = $true
                        Write-Verbose "FTD2XX_NET.dll also loaded (FT232R CBUS fallback)"
                    } catch {
                        Write-Verbose "FTD2XX_NET.dll unavailable for fallback: $_"
                    }
                }

                # Load FtdiSharp for MPSSE I2C/SPI (used by SSD1306 and other I2C devices)
                $sharpPath = Join-Path (Join-Path (Join-Path $ModuleRoot 'lib') 'ftdisharp') 'FtdiSharp.dll'
                if (Test-Path $sharpPath) {
                    try {
                        [void][Reflection.Assembly]::LoadFrom($sharpPath)
                        $null = [FtdiSharp.FtdiDevices]
                        $null = [FtdiSharp.Protocols.I2C]
                        $script:FtdiSharpAvailable = $true
                        Write-Verbose "FtdiSharp.dll loaded - I2C/SPI protocol support available"
                    } catch {
                        Write-Verbose "FtdiSharp.dll load failed: $_"
                    }
                }
            }

            # $script:FtdiInitialized drives stub/real branching in Invoke-FtdiWindowsEnumerate.
            # Set it now so enumeration works even before psm1 assigns the return value.
            $script:FtdiInitialized = $script:D2xxLoaded

            # Return $true if at least one useful backend is ready
            return ($script:IotBackendAvailable -or $script:D2xxLoaded)
        }

        # ------------------------------------------------------------------
        # Path B: Windows PS 5.1 / PS 7 on .NET < 8 -> FTD2XX_NET only
        # ------------------------------------------------------------------
        if ($isWindows) {
            Write-Verbose "Windows PS $psVersion / .NET $dotnetMajor detected - loading FTD2XX_NET.dll"

            if ($psVersion -eq 5) {
                $dllPath = Join-Path (Join-Path (Join-Path $ModuleRoot 'lib') 'net48') 'FTD2XX_NET.dll'
            } elseif ($psVersion -ge 7) {
                $dllPath = Join-Path (Join-Path (Join-Path $ModuleRoot 'lib') 'netstandard20') 'FTD2XX_NET.dll'
            } else {
                Write-Warning "Unsupported PowerShell version: $psVersion"
                return $false
            }

            if (Test-Path $dllPath) {
                try {
                    [void][Reflection.Assembly]::LoadFrom($dllPath)
                    $null = [FTD2XX_NET.FTDI]
                    $null = [FTD2XX_NET.FTDI+FT_STATUS]
                    $null = [FTD2XX_NET.FTDI+FT_DEVICE]
                    $script:FTDI_OK    = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK
                    $script:D2xxLoaded = $true
                    Write-Verbose "Successfully loaded FTD2XX_NET.dll from $dllPath"
                } catch {
                    Write-Error "Failed to load FTD2XX_NET.dll: $_"
                    return $false
                }
            } else {
                Write-Warning "FTD2XX_NET.dll not found at: $dllPath"
                Write-Verbose "Operating in stub mode - real FTDI operations will not be available"
                return $false
            }

            # Load FtdiSharp for MPSSE I2C/SPI (SSD1306 and other I2C devices)
            $sharpPath = Join-Path (Join-Path (Join-Path $ModuleRoot 'lib') 'ftdisharp') 'FtdiSharp.dll'
            if (Test-Path $sharpPath) {
                try {
                    [void][Reflection.Assembly]::LoadFrom($sharpPath)
                    $null = [FtdiSharp.FtdiDevices]
                    $null = [FtdiSharp.Protocols.I2C]
                    $script:FtdiSharpAvailable = $true
                    Write-Verbose "FtdiSharp.dll loaded - I2C/SPI protocol support available"
                } catch {
                    Write-Verbose "FtdiSharp.dll load failed (I2C will use raw MPSSE): $_"
                }
            }

            $script:FtdiInitialized = $script:D2xxLoaded
            return $script:D2xxLoaded
        }

        # ------------------------------------------------------------------
        # Path C: Unix / Linux without IoT (.NET < 8) -> stub mode
        # ------------------------------------------------------------------
        Write-Verbose "Unix platform / .NET $dotnetMajor - IoT backend requires .NET 8+; stub mode active"
        return $false

    } catch {
        Write-Error "Failed to initialize FTDI assembly: $_"
        return $false
    }
}