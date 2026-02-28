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

    $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
    $psVersion = $PSVersionTable.PSVersion
    $dotnet    = [System.Environment]::Version
    $platform  = if ($isWindows) { 'Windows' } else { 'Linux/Unix' }

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
    $backendLabel = "$backendName$sharpNote"

    Write-Verbose "PS version  : $psVersion"
    Write-Verbose ".NET version: $dotnet"
    Write-Verbose "Platform    : $platform"
    Write-Verbose "IotBackend  : $($script:IotBackendAvailable)"
    Write-Verbose "D2xxLoaded  : $($script:D2xxLoaded)"
    Write-Verbose "FtdiSharp   : $($script:FtdiSharpAvailable)"

    # ------------------------------------------------------------------
    # Native library check (Linux/macOS only)
    # ------------------------------------------------------------------
    $nativeStatus = 'N/A (Windows)'
    $nativeOk     = $true
    $nativePath   = $null

    if (-not $isWindows) {
        $nativeLibLocations = @(
            '/usr/local/lib/libftd2xx.so',
            '/usr/lib/libftd2xx.so',
            '/usr/lib/x86_64-linux-gnu/libftd2xx.so',
            '/usr/lib/aarch64-linux-gnu/libftd2xx.so',
            '/usr/lib/arm-linux-gnueabihf/libftd2xx.so'
        )
        $nativePath = $nativeLibLocations | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($nativePath) {
            $nativeStatus = "[OK] $nativePath"
            $nativeOk     = $true
        } else {
            $nativeStatus = '[MISSING] libftd2xx.so not found'
            $nativeOk     = $false
        }

        # Check if ftdi_sio is blocking D2XX access
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
    Write-Host ("Backend   : {0}" -f $backendLabel)

    if (-not $isWindows) {
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

    # Overall status
    $isReady = $backendOk -and $nativeOk -and ($devices.Count -gt 0)

    # Derive Status / Reason / NextStep for structured return
    if ($isReady) {
        $resultStatus   = 'OK'
        $resultReason   = 'All checks passed'
        $resultNextStep = 'Run: List-PsGadgetFtdi | Format-Table'
    } elseif (-not $backendOk) {
        $resultStatus   = 'Fail'
        $resultReason   = 'No FTDI backend loaded'
        $resultNextStep = 'Remove-Module PSGadget; Import-Module PSGadget -Verbose'
    } elseif (-not $nativeOk) {
        $resultStatus   = 'Fail'
        $resultReason   = 'Native FTDI library not found (libftd2xx.so)'
        $resultNextStep = 'Download from https://ftdichip.com/drivers/d2xx-drivers/ then: sudo cp libftd2xx.so /usr/local/lib && sudo ldconfig'
    } else {
        $resultStatus   = 'Fail'
        $resultReason   = 'No FTDI devices detected'
        $resultNextStep = 'Connect an FTDI device and retry, or run Test-PsGadgetEnvironment -Verbose for diagnostics'
    }

    $statusLabel = if ($isReady) { 'READY' } else { 'NOT READY - run with -Verbose for details' }
    Write-Host ("Status    : {0}" -f $statusLabel)
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
