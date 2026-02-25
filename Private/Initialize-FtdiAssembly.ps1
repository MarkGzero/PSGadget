# Initialize-FtdiAssembly.ps1
# Version-aware FTDI assembly loading

function Initialize-FtdiAssembly {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ModuleRoot = $PSScriptRoot
    )
    
    try {
        # Detect PowerShell version for appropriate assembly loading
        $psVersion = $PSVersionTable.PSVersion.Major
        $isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
        
        if ($isWindows) {
            Write-Verbose "Windows PowerShell v$psVersion detected - loading FTD2XX_NET.dll"
            
            # Determine appropriate assembly path based on PowerShell version
            if ($psVersion -eq 5) {
                $dllPath = Join-Path $ModuleRoot "lib\net48\FTD2XX_NET.dll"
            } elseif ($psVersion -ge 7) {
                $dllPath = Join-Path $ModuleRoot "lib\netstandard20\FTD2XX_NET.dll"
            } else {
                Write-Warning "Unsupported PowerShell version: $psVersion"
                return $false
            }
            
            # Check if assembly file exists
            if (Test-Path $dllPath) {
                try {
                    # Load the FTDI assembly
                    [void][Reflection.Assembly]::LoadFrom($dllPath)
                    
                    # Verify assembly loaded correctly by testing key types
                    $ftdiType = [FTD2XX_NET.FTDI]
                    $statusType = [FTD2XX_NET.FTDI+FT_STATUS]
                    $deviceType = [FTD2XX_NET.FTDI+FT_DEVICE]
                    
                    Write-Verbose "Successfully loaded FTD2XX_NET.dll from $dllPath"
                    
                    # Set global status constants for easier access
                    $script:FTDI_OK = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK
                    
                    return $true
                    
                } catch {
                    Write-Error "Failed to load FTDI assembly: $_"
                    return $false
                }
            } else {
                Write-Warning "FTDI assembly not found at: $dllPath"
                Write-Verbose "Operating in stub mode - real FTDI operations will not be available"
                return $false
            }
        } else {
            # Unix/Linux - use libftdi or other approaches
            Write-Verbose "Unix platform detected - libftdi support not yet implemented"
            Write-Verbose "Operating in stub mode for Unix platforms"
            return $false
        }
        
    } catch {
        Write-Error "Failed to initialize FTDI assembly: $_"
        return $false
    }
}