#Requires -Version 5.1
function Install-MacOSD2XXDrivers {
    <#
    .SYNOPSIS
    Downloads and installs the FTDI D2XX native library on macOS.

    .DESCRIPTION
    Downloads the official FTDI D2XX package for macOS, mounts the DMG, copies the
    versioned dylib to /usr/local/lib/, creates the libftd2xx.dylib symlink, and
    copies it into the PSGadget module's lib/net8/ directory so the module can load
    it directly on the next Import-Module.

    Requires Administrator (sudo) access. You will be prompted for your macOS password.

    This function only runs on macOS. Run Test-PsGadgetEnvironment after installation
    to verify the library is found.

    .PARAMETER Version
    D2XX library version to install. Defaults to the current known-good release (1.4.30).

    .PARAMETER SkipModuleCopy
    Skip copying the dylib into the module's lib/net8/ directory.

    .EXAMPLE
    Install-MacOSD2XXDrivers
    # Downloads D2XX 1.4.30, installs to /usr/local/lib/, copies into PSGadget module.

    .EXAMPLE
    Install-MacOSD2XXDrivers -WhatIf
    # Show what would be done without making any changes.

    .NOTES
    After installation, reimport the module:
        Import-Module PSGadget -Force
        Test-PsGadgetEnvironment

    If Get-FtdiDevice still shows no devices, the AppleUSBFTDI kext may be claiming
    the device before D2XX can open it. Unload it with:
        sudo kextunload -b com.apple.driver.AppleUSBFTDI
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Version = '1.4.30',

        [Parameter(Mandatory = $false)]
        [switch]$SkipModuleCopy
    )

    # macOS-only gate
    $isMac = (-not ([System.Environment]::OSVersion.Platform -eq 'Win32NT')) -and
             (& { try { (& uname -s 2>$null).Trim() -eq 'Darwin' } catch { $false } })
    if (-not $isMac) {
        throw "Install-MacOSD2XXDrivers is for macOS only. For Linux, see: Get-Help Test-PsGadgetEnvironment -Full"
    }

    $dmgUrl      = "https://ftdichip.com/wp-content/uploads/2024/04/D2XX$Version.dmg"
    $dmgPath     = "/tmp/D2XX$Version.dmg"
    $libName     = "libftd2xx.$Version.dylib"
    $libDest     = "/usr/local/lib/$libName"
    $symlinkDest = '/usr/local/lib/libftd2xx.dylib'
    $mountPoint  = $null

    if (-not $PSCmdlet.ShouldProcess('/usr/local/lib', "Install FTDI D2XX $Version")) { return }

    # ── Download ────────────────────────────────────────────────────────────────
    if (Test-Path $dmgPath) {
        Write-Host "Using cached DMG: $dmgPath (delete it to force re-download)"
    } else {
        Write-Host "Downloading FTDI D2XX $Version..."
        Write-Host "  URL: $dmgUrl"
        & curl -fL $dmgUrl -o $dmgPath
        if ($LASTEXITCODE -ne 0) {
            throw "curl failed (exit $LASTEXITCODE). Check your internet connection and try again."
        }
        Write-Host "  Saved to: $dmgPath"
    }

    # ── Mount ───────────────────────────────────────────────────────────────────
    Write-Host "Mounting DMG..."
    $hdiLines = & hdiutil attach $dmgPath -nobrowse -readonly 2>&1
    # hdiutil output: last line containing /Volumes/ has the mount point as the last token
    $mountLine  = @($hdiLines) | Where-Object { $_ -match '/Volumes/' } | Select-Object -Last 1
    if ($mountLine) {
        $mountPoint = ($mountLine -split '\s+' | Where-Object { $_ -like '/Volumes/*' } | Select-Object -First 1)
    }
    if (-not $mountPoint) {
        throw "Failed to determine mount point. hdiutil output:`n$($hdiLines -join "`n")"
    }
    Write-Host "  Mounted at: $mountPoint"

    try {
        # ── Find the dylib ───────────────────────────────────────────────────────
        # Try the known FTDI DMG layout first (avoids Get-ChildItem -Recurse which
        # can hang on macOS mounted volumes due to Spotlight/xattr enumeration).
        $knownPath = Join-Path $mountPoint 'release' 'build' "libftd2xx.$Version.dylib"
        $dylibFile = $null
        if (Test-Path $knownPath) {
            $dylibFile = Get-Item $knownPath
        } else {
            # Fallback: native find (faster and more reliable than PS recursive enum on volumes)
            $findResult = & find $mountPoint -name 'libftd2xx.*.dylib' -not -name '*.dSYM' 2>$null |
                          Select-Object -First 1
            if ($findResult) { $dylibFile = Get-Item $findResult }
        }
        if (-not $dylibFile) {
            throw "libftd2xx dylib not found inside mounted DMG at '$mountPoint'. Try running: find '$mountPoint' -name 'libftd2xx*.dylib'"
        }
        Write-Host "  Found dylib: $($dylibFile.FullName)"

        # ── Install ──────────────────────────────────────────────────────────────
        Write-Host "Installing (sudo required — enter your macOS password if prompted)..."
        & sudo mkdir -p /usr/local/lib
        if ($LASTEXITCODE -ne 0) { throw "sudo mkdir /usr/local/lib failed" }

        & sudo cp $dylibFile.FullName $libDest
        if ($LASTEXITCODE -ne 0) { throw "sudo cp '$($dylibFile.FullName)' '$libDest' failed" }

        & sudo ln -sf $libDest $symlinkDest
        if ($LASTEXITCODE -ne 0) { throw "sudo ln -sf '$libDest' '$symlinkDest' failed" }

        Write-Host "  Installed:  $libDest"
        Write-Host "  Symlink:    $symlinkDest -> $libDest"

        # ── Copy into module lib/net8/ ───────────────────────────────────────────
        if (-not $SkipModuleCopy) {
            $net8Dir  = Join-Path $PSScriptRoot '..' 'lib' 'net8'
            $net8Dest = Join-Path $net8Dir 'libftd2xx.dylib'
            if (Test-Path $net8Dir) {
                Copy-Item -Path $libDest -Destination $net8Dest -Force
                Write-Host "  Module copy: $net8Dest"
            } else {
                Write-Warning "Module lib/net8/ directory not found at '$net8Dir' — skipping module copy."
            }
        }

        # ── AppleUSBFTDI kext warning ────────────────────────────────────────────
        try {
            $kextOut = & kextstat 2>$null
            if ($kextOut -match 'AppleUSBFTDI') {
                Write-Warning (
                    "AppleUSBFTDI kext is loaded. It may claim the FTDI device before D2XX can open it.`n" +
                    "If Get-FtdiDevice returns no results, unload it:`n" +
                    "  sudo kextunload -b com.apple.driver.AppleUSBFTDI"
                )
            }
        } catch {}

        # ── Unmount before success message so output is ordered cleanly ────────────
        if ($mountPoint) {
            Write-Host "Unmounting $mountPoint..."
            & hdiutil detach $mountPoint -quiet 2>$null | Out-Null
            $mountPoint = $null
        }

        # ── Done ─────────────────────────────────────────────────────────────────
        # Detect whether running from a local path or an installed module location
        # so the reimport instruction matches what will actually work.
        $psmPath  = Join-Path $PSScriptRoot '..' 'PSGadget.psm1'
        $importCmd = if (Test-Path $psmPath) {
            "Import-Module '$((Resolve-Path $psmPath).Path)' -Force"
        } else {
            'Import-Module PSGadget -Force'
        }

        Write-Host ""
        Write-Host "D2XX $Version installed successfully."
        Write-Host "Next steps in pwsh:"
        Write-Host "  $importCmd"
        Write-Host "  Test-PsGadgetEnvironment"

    } finally {
        if ($mountPoint) {
            & hdiutil detach $mountPoint -quiet 2>$null | Out-Null
        }
    }
}
