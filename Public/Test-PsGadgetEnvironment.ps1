# Test-PsGadgetEnvironment.ps1
# Diagnostic command to verify the PsGadget environment and hardware readiness

function Test-PsGadgetEnvironment {
    <#
    .SYNOPSIS
    Checks this environment and reports whether PsGadget hardware is ready.

    .DESCRIPTION
    Verifies the PowerShell version, .NET runtime, FTDI driver/DLL state,
    native library presence (Linux/macOS), and connected devices.

    Default output is a clean summary. Use -Verbose for per-device hints and
    next-step commands you can copy directly into your session.

    .EXAMPLE
    Test-PsGadgetEnvironment

    .EXAMPLE
    Test-PsGadgetEnvironment -Verbose

    .OUTPUTS
    PSCustomObject with Platform, Backend, Devices, DeviceCount, and IsReady properties.
    Use the return value to script conditional setup logic.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $runningOnWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
    $runningOnMacOS   = (-not $runningOnWindows) -and (try { (& uname -s 2>$null).Trim() -eq 'Darwin' } catch { $false })
    $psVersion = $PSVersionTable.PSVersion
    $dotnet    = [System.Environment]::Version
    $platform  = if ($runningOnWindows) { 'Windows' } elseif ($runningOnMacOS) { 'macOS' } else { 'Linux' }

    # ------------------------------------------------------------------
    # Determine active backend from module-scope flags set at import time
    # ------------------------------------------------------------------
    $backendName = 'Stub (no hardware access)'
    $backendOk   = $false

    if ($script:IotBackendAvailable) {
        $backendName = 'IoT (Iot.Device.Bindings / .NET 8+)'
        $backendOk   = $true
    } elseif ($script:D2xxLoaded) {
        $backendName = 'D2XX (FTD2XX_NET.dll)'
        $backendOk   = $true
    }

    $sharpNote    = if ($script:FtdiSharpAvailable) { ' + FtdiSharp I2C/SPI' } else { '' }
    $readySuffix  = if ($backendOk) { ' - Ready' } else { ' - hardware commands unavailable' }
    $backendLabel = "$backendName$sharpNote$readySuffix"

    Write-Verbose "PS version  : $psVersion"
    Write-Verbose ".NET version: $dotnet"
    Write-Verbose "Platform    : $platform"
    Write-Verbose "IotBackend  : $($script:IotBackendAvailable)"
    Write-Verbose "D2xxLoaded  : $($script:D2xxLoaded)"
    Write-Verbose "FtdiSharp   : $($script:FtdiSharpAvailable)"

    # ------------------------------------------------------------------
    # Native library check
    # ------------------------------------------------------------------
    $nativeStatus = 'N/A (Windows)'
    $nativeOk     = $true
    $nativePath   = $null

    if ($runningOnWindows) {
        # On Windows the bundled lib/native/FTD2XX.dll is the native D2XX driver.
        # Locate it so NativeLibPath is populated in the return object.
        $moduleRoot    = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $windowsDll    = Join-Path $moduleRoot 'lib\native\FTD2XX.dll'
        if (([System.IO.FileInfo]::new($windowsDll)).Exists) {
            $nativePath = $windowsDll
        }
    }

    if (-not $runningOnWindows) {
        $moduleNet8Dir = Join-Path (Join-Path $PSScriptRoot '..') 'lib/net8'
        $moduleNet8Dir = [System.IO.Path]::GetFullPath($moduleNet8Dir)
        if ($runningOnMacOS) {
            $nativeLibLocations = @(
                (Join-Path $moduleNet8Dir 'libftd2xx.dylib'),
                '/usr/local/lib/libftd2xx.dylib',
                '/usr/lib/libftd2xx.dylib'
            )
        } else {
            $nativeLibLocations = @(
                # Local copy inside lib/net8/ - always readable by pwsh regardless of snap confinement
                (Join-Path $moduleNet8Dir 'libftd2xx.so'),
                '/usr/local/lib/libftd2xx.so',
                '/usr/lib/libftd2xx.so',
                '/usr/lib/x86_64-linux-gnu/libftd2xx.so',
                '/usr/lib/aarch64-linux-gnu/libftd2xx.so',
                '/usr/lib/arm-linux-gnueabihf/libftd2xx.so'
            )
        }
        # Use [System.IO.FileInfo]::Exists instead of Test-Path.
        # Snap-confined pwsh overrides Test-Path with a provider that returns $true
        # for paths outside the snap tree even when those files are not accessible
        # to .NET P/Invoke or bash. FileInfo.Exists uses System.IO stat(), which
        # matches what the runtime actually sees.
        $nativePath = $nativeLibLocations | Where-Object {
            try { ([System.IO.FileInfo]::new($_)).Exists } catch { $false }
        } | Select-Object -First 1

        if ($nativePath) {
            $nativeStatus = "[OK] $nativePath"
            $nativeOk     = $true
        } else {
            $nativeLibName = if ($runningOnMacOS) { 'libftd2xx.dylib' } else { 'libftd2xx.so' }
            $nativeStatus  = "[MISSING] $nativeLibName not found"
            $nativeOk      = $false
        }

        if ($runningOnMacOS) {
            # Check if AppleUSBFTDI kext is claiming the device
            try {
                $kextOut = & kextstat 2>$null
                if ($kextOut -match 'AppleUSBFTDI') {
                    $nativeStatus += ' [AppleUSBFTDI loaded]'
                    Write-Verbose 'AppleUSBFTDI kext is loaded - it may claim VCP devices before D2XX can open them.'
                    Write-Verbose 'To unload: sudo kextunload -b com.apple.driver.AppleUSBFTDI'
                }
            } catch {}

            if (-not $nativeOk) {
                Write-Verbose 'libftd2xx.dylib is required for FTDI hardware access on macOS.'
                Write-Verbose 'Download the D2XX macOS package from: https://ftdichip.com/drivers/d2xx-drivers/'
                Write-Verbose 'Open the DMG and run the installer, or: sudo cp libftd2xx.dylib /usr/local/lib/'
            }
        } else {
            # Check if ftdi_sio is blocking D2XX access (Linux only)
            try {
                $lsmodOut = & lsmod 2>/dev/null
                if ($lsmodOut -match 'ftdi_sio') {
                    $nativeStatus += ' [ftdi_sio loaded]'
                    Write-Verbose 'ftdi_sio kernel module is loaded - it claims VCP devices before D2XX can open them.'
                    Write-Verbose 'If hardware does not respond: sudo rmmod ftdi_sio'
                    Write-Verbose 'To make the change permanent: echo "blacklist ftdi_sio" | sudo tee /etc/modprobe.d/ftdi-psgadget.conf'
                }
            } catch {}

            if (-not $nativeOk) {
                Write-Verbose 'libftd2xx.so is required for FTDI hardware access on Linux.'
                Write-Verbose 'Download from: https://ftdichip.com/drivers/d2xx-drivers/'
                Write-Verbose 'Install: sudo cp libftd2xx.so /usr/local/lib && sudo ldconfig'
            }
        }
    }

    # ------------------------------------------------------------------
    # Enumerate connected devices
    # ------------------------------------------------------------------
    $devices    = @()
    $deviceNote = 'None found'

    try {
        $devices = @(List-PsGadgetFtdi -ErrorAction SilentlyContinue)
        if ($devices.Count -gt 0) {
            $deviceNote = "$($devices.Count) device(s) found"
        }
    } catch {
        $deviceNote = "Enumeration failed: $($_.Exception.Message)"
        Write-Verbose "Device enumeration error: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # Config check
    # ------------------------------------------------------------------
    $userHome   = [Environment]::GetFolderPath('UserProfile')
    $configPath = Join-Path $userHome (Join-Path '.psgadget' 'config.json')
    $configOk   = Test-Path $configPath
    $configNote = if ($configOk) { "[OK] $configPath" } else { '[MISSING] Run Set-PsGadgetConfig to create one' }

    # ------------------------------------------------------------------
    # Print summary block
    # ------------------------------------------------------------------
    $line = '-' * 52
    Write-Host ''
    Write-Host 'PsGadget Setup Check'
    Write-Host $line
    Write-Host ("Platform  : {0} / PS {1} / .NET {2}" -f $platform, $psVersion, $dotnet)
    Write-Host ("Driver    : {0}" -f $backendLabel)

    if (-not $runningOnWindows) {
        Write-Host ("Native lib: {0}" -f $nativeStatus)
    }

    Write-Host ("Devices   : {0}" -f $deviceNote)
    Write-Host ("Config    : {0}" -f $configNote)
    Write-Host $line

    # Per-device detail rows
    foreach ($dev in $devices) {
        $caps = Get-FtdiChipCapabilities -TypeName $dev.Type
        Write-Host ("  [{0}] {1,-10} SN={2,-14} GPIO={3}" -f `
            $dev.Index, $dev.Type, $dev.SerialNumber, $caps.GpioMethod)

        Write-Verbose ("      Pins    : {0}" -f $caps.GpioPins)
        if ($caps.CapabilityNote) {
            Write-Verbose ("      Note    : {0}" -f $caps.CapabilityNote)
        }

        # Actionable next-step hints
        if ($dev.SerialNumber) {
            Write-Verbose ("      Connect : `$dev = New-PsGadgetFtdi -SerialNumber '{0}'" -f $dev.SerialNumber)
        } elseif ($dev.LocationId) {
            Write-Verbose ("      Connect : `$dev = New-PsGadgetFtdi -LocationId '{0}'" -f $dev.LocationId)
        } else {
            Write-Verbose ("      Connect : `$dev = New-PsGadgetFtdi -Index {0}" -f $dev.Index)
        }

        if ($caps.HasMpsse) {
            Write-Verbose ("      I2C scan: `$dev.Scan()")
            Write-Verbose ("      Display : `$dev.Display('Hello world', 0)")
        }
    }

    # Pad before status line
    if ($devices.Count -gt 0) { Write-Host '' }

    # Backend guidance when in stub mode
    if (-not $backendOk) {
        Write-Verbose 'No FTDI backend loaded. Re-import with: Remove-Module PSGadget; Import-Module PSGadget -Verbose'
        Write-Verbose 'Verbose import output shows exactly which DLL paths were tried.'
    }

    # ------------------------------------------------------------------
    # Detect snap-confined PowerShell (causes GLIBC mismatch on import)
    # ------------------------------------------------------------------
    $isSnapPwsh = $false
    if (-not $runningOnWindows) {
        $snapEnv = [System.Environment]::GetEnvironmentVariable('SNAP')
        if ($snapEnv) {
            $isSnapPwsh = $true
        } else {
            try {
                $pwshPath = (Get-Process -Id $PID -ErrorAction SilentlyContinue).MainModule.FileName
                if ($pwshPath -and $pwshPath -like '*/snap/*') { $isSnapPwsh = $true }
            } catch {}
        }
    }

    # Overall status
    $isReady = $backendOk -and $nativeOk -and ($devices.Count -gt 0)

    # Derive Status / Reason / NextStep for structured return
    if ($isReady) {
        $resultStatus   = 'OK'
        $resultReason   = 'All checks passed'
        $resultNextStep = 'Run: List-PsGadgetFtdi | Format-Table'
    } elseif (-not $backendOk -and $isSnapPwsh) {
        $resultStatus   = 'Fail'
        $resultReason   = 'snap-confined pwsh: GLIBC mismatch prevents libftd2xx.so from loading (snap bundled glibc is older than library requirement)'
        $resultNextStep = 'exit from this session then use non-snap PowerShell (apt-get install -y powershell)then run `$ /usr/bin/pwsh` instead of `$ powershell` (snap alias)'
        Write-Verbose 'snap-confined pwsh detected. The snap sandbox bundles an older glibc that is'
        Write-Verbose 'incompatible with the libftd2xx.so in lib/net8/. Two options:'
        Write-Verbose '  A) Switch to non-snap PowerShell:'
        Write-Verbose '       sudo apt-get install -y powershell'
        Write-Verbose '       /usr/bin/pwsh  (not the snap alias)'
        Write-Verbose '  B) Replace lib/net8/libftd2xx.so with an older build (compiled for glibc <= 2.35):'
        Write-Verbose '       cd /tmp && wget https://ftdichip.com/wp-content/uploads/2024/04/libftd2xx-linux-x86_64-1.4.30.tgz'
        Write-Verbose '       tar xzf libftd2xx-linux-x86_64-1.4.30.tgz'
        Write-Verbose '       cp linux-x86_64/libftd2xx.so.1.4.30 <module-root>/lib/net8/libftd2xx.so'
    } elseif (-not $backendOk) {
        $resultStatus   = 'Fail'
        $resultReason   = 'No FTDI backend loaded'
        $resultNextStep = 'Remove-Module PSGadget; Import-Module PSGadget -Verbose'
    } elseif (-not $nativeOk) {
        $resultStatus = 'Fail'
        if ($runningOnMacOS) {
            $resultReason   = 'Native FTDI library not found (libftd2xx.dylib)'
            $resultNextStep = 'Download D2XX macOS package from https://ftdichip.com/drivers/d2xx-drivers/ then: sudo cp libftd2xx.dylib /usr/local/lib/'
        } else {
            $resultReason   = 'Native FTDI library not found (libftd2xx.so)'
            $resultNextStep = 'Download from https://ftdichip.com/drivers/d2xx-drivers/ then: sudo cp libftd2xx.so /usr/local/lib && sudo ldconfig'
        }
    } else {
        $resultStatus   = 'Fail'
        $resultReason   = 'No FTDI devices detected'
        $resultNextStep = 'Connect an FTDI device and retry, or run Test-PsGadgetEnvironment -Verbose for diagnostics'
    }

    $statusLabel = if ($isReady) { 'READY' } else { 'NOT READY - run with -Verbose for details' }
    Write-Host ("Status    : {0}" -f $statusLabel)
    if (-not $isReady) {
        Write-Host ("Next step : {0}" -f $resultNextStep)
    }
    Write-Host ''

    if ($isReady) {
        Write-Verbose 'All checks passed. Hardware is ready.'
        Write-Verbose 'Quick start: List-PsGadgetFtdi | Format-Table'
        Write-Verbose 'Then:        $dev = New-PsGadgetFtdi -SerialNumber <SN>'
    }

    return [PSCustomObject]@{
        Status        = $resultStatus
        Reason        = $resultReason
        NextStep      = $resultNextStep
        IsSnapPwsh    = $isSnapPwsh
        Platform      = $platform
        PsVersion     = $psVersion.ToString()
        DotNetVersion = $dotnet.ToString()
        Backend       = $backendLabel
        BackendReady  = $backendOk
        NativeLibOk   = $nativeOk
        NativeLibPath = $nativePath
        Devices       = $devices
        DeviceCount   = $devices.Count
        ConfigPresent = $configOk
        IsReady       = $isReady
    }
}

# Backward-compatibility alias
Set-Alias -Name 'Test-PsGadgetSetup' -Value 'Test-PsGadgetEnvironment'
