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
    $script:IotBackendAvailable = $false
    $script:D2xxLoaded          = $false

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

            $iotDir    = Join-Path $ModuleRoot 'lib' 'net8'
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
                $script:IotBackendAvailable = $true
                Write-Verbose "IoT backend loaded successfully - using Iot.Device.Bindings"
            } else {
                Write-Warning "IoT DLL loading incomplete - falling back to FTD2XX_NET backend"
            }

            # On Windows: also load FTD2XX_NET (netstandard20) for FT232R CBUS fallback.
            # On Unix:    FTD2XX_NET is not available; FT232R stays in stub mode.
            if ($isWindows) {
                $d2xxPath = Join-Path $ModuleRoot 'lib' 'netstandard20' 'FTD2XX_NET.dll'
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
            }

            # Return $true if at least one useful backend is ready
            return ($script:IotBackendAvailable -or $script:FtdiInitialized)
        }

        # ------------------------------------------------------------------
        # Path B: Windows PS 5.1 / PS 7 on .NET < 8 -> FTD2XX_NET only
        # ------------------------------------------------------------------
        if ($isWindows) {
            Write-Verbose "Windows PS $psVersion / .NET $dotnetMajor detected - loading FTD2XX_NET.dll"

            if ($psVersion -eq 5) {
                $dllPath = Join-Path $ModuleRoot 'lib' 'net48' 'FTD2XX_NET.dll'
            } elseif ($psVersion -ge 7) {
                $dllPath = Join-Path $ModuleRoot 'lib' 'netstandard20' 'FTD2XX_NET.dll'
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
                    return $true
                } catch {
                    Write-Error "Failed to load FTD2XX_NET.dll: $_"
                    return $false
                }
            } else {
                Write-Warning "FTD2XX_NET.dll not found at: $dllPath"
                Write-Verbose "Operating in stub mode - real FTDI operations will not be available"
                return $false
            }
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