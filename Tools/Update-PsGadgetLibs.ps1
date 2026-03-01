# Update-PsGadgetLibs.ps1
# Refresh NuGet-sourced DLLs in lib/ from the packageversions declared in lib/nuget-deps.csproj.
#
# Usage:
#   pwsh ./Tools/Update-PsGadgetLibs.ps1           # dry run (shows what would change)
#   pwsh ./Tools/Update-PsGadgetLibs.ps1 -Apply    # download and replace DLLs
#   pwsh ./Tools/Update-PsGadgetLibs.ps1 -Audit    # vulnerability + outdated check only
#
# Requirements: dotnet SDK 8+ on PATH
#
# NON-NUGET DEPENDENCIES (this script does NOT update these):
#   lib/native/FTD2XX.dll            FTDI D2XX native driver
#   lib/net48/FTD2XX_NET.dll         FTDI managed wrapper (vendor zip)
#   lib/netstandard20/FTD2XX_NET.dll FTDI managed wrapper (vendor zip)
#   Download: https://ftdichip.com/drivers/d2xx-drivers/

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Apply,
    [switch]$Audit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Path $PSScriptRoot -Parent
$CsprojPath = Join-Path $RepoRoot 'lib' 'nuget-deps.csproj'
$LibDir    = Join-Path $RepoRoot 'lib'
$TempDir   = Join-Path ([System.IO.Path]::GetTempPath()) 'psgadget-lib-update'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Assert-Dotnet {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "dotnet SDK not found on PATH. Install from https://dotnet.microsoft.com/download"
    }
    $ver = dotnet --version
    Write-Verbose "dotnet version: $ver"
}

function Invoke-Dotnet {
    param([string[]]$Arguments)
    $out = & dotnet @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error ("dotnet {0} failed (exit {1}):`n{2}" -f ($Arguments -join ' '), $LASTEXITCODE, ($out -join "`n"))
    }
    return $out
}

# ---------------------------------------------------------------------------
# Audit mode: vulnerability + outdated report only
# ---------------------------------------------------------------------------
if ($Audit) {
    Assert-Dotnet
    Write-Host "Running vulnerability scan..." -ForegroundColor Cyan
    Invoke-Dotnet @('restore', $CsprojPath, '--nologo', '--verbosity', 'quiet')
    $vulnOut = & dotnet list $CsprojPath package --vulnerable --include-transitive 2>&1
    Write-Host ($vulnOut -join "`n")

    Write-Host ""
    Write-Host "Running outdated check..." -ForegroundColor Cyan
    $outdatedOut = & dotnet list $CsprojPath package --outdated 2>&1
    Write-Host ($outdatedOut -join "`n")
    exit 0
}

# ---------------------------------------------------------------------------
# Destination map: which DLLs go where after restore
# package ID -> @{ tfm; dll filename; destination relative to lib/ }
# ---------------------------------------------------------------------------
$LibMap = @(
    @{ Package = 'System.Device.Gpio';                        Tfm = 'net8.0'; Dll = 'System.Device.Gpio.dll';                          Dest = 'net8' },
    @{ Package = 'Iot.Device.Bindings';                       Tfm = 'net8.0'; Dll = 'Iot.Device.Bindings.dll';                         Dest = 'net8' },
    @{ Package = 'UnitsNet';                                  Tfm = 'net8.0'; Dll = 'UnitsNet.dll';                                    Dest = 'net8' },
    @{ Package = 'Microsoft.Extensions.Logging.Abstractions'; Tfm = 'net8.0'; Dll = 'Microsoft.Extensions.Logging.Abstractions.dll';   Dest = 'net8' },
    @{ Package = 'FtdiSharp';                                 Tfm = 'net6.0'; Dll = 'FtdiSharp.dll';                                   Dest = 'ftdisharp' }
)

# ---------------------------------------------------------------------------
# Restore to temp package cache
# ---------------------------------------------------------------------------
Assert-Dotnet

if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
New-Item -ItemType Directory -Path $TempDir | Out-Null

$PackageCacheDir = Join-Path $TempDir 'packages'

Write-Host "Restoring packages from lib/nuget-deps.csproj..." -ForegroundColor Cyan
Invoke-Dotnet @(
    'restore', $CsprojPath,
    '--packages', $PackageCacheDir,
    '--nologo',
    '--verbosity', 'quiet'
)

# ---------------------------------------------------------------------------
# Locate and compare DLLs
# ---------------------------------------------------------------------------
$Updates = [System.Collections.Generic.List[hashtable]]::new()

foreach ($entry in $LibMap) {
    # NuGet cache layout: <cache>/<package.id.lower>/<version>/lib/<tfm>/<dll>
    $pkgLower = $entry.Package.ToLower()
    $pkgRoot  = Join-Path $PackageCacheDir $pkgLower

    if (-not (Test-Path $pkgRoot)) {
        Write-Warning ("Package cache not found for {0}: {1}" -f $entry.Package, $pkgRoot)
        continue
    }

    # Pick highest version dir available
    $versionDir = Get-ChildItem -Path $pkgRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $versionDir) {
        Write-Warning ("No version directory found under {0}" -f $pkgRoot)
        continue
    }

    # Try exact TFM first, then fall back to nearest available
    $tfmSearchOrder = @($entry.Tfm, 'net8.0', 'net6.0', 'netstandard2.0', 'netstandard1.6',
                        'net481', 'net48', 'net472', 'net471', 'net47', 'net462', 'net461')
    $srcDll = $null
    foreach ($tfm in $tfmSearchOrder) {
        $candidate = Join-Path $versionDir.FullName 'lib' $tfm $entry.Dll
        if (Test-Path $candidate) {
            $srcDll = $candidate
            break
        }
    }

    # Last resort: search entire package tree for the DLL
    if (-not $srcDll) {
        $found = Get-ChildItem -Path $versionDir.FullName -Recurse -Filter $entry.Dll -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) { $srcDll = $found.FullName }
    }

    if (-not $srcDll) {
        Write-Warning ("DLL not found in package cache for {0} ({1})" -f $entry.Package, $entry.Dll)
        continue
    }

    $destDll = Join-Path $LibDir $entry.Dest $entry.Dll

    # Compare file hash
    $srcHash  = (Get-FileHash -Path $srcDll  -Algorithm SHA256).Hash
    $destHash = if (Test-Path $destDll) { (Get-FileHash -Path $destDll -Algorithm SHA256).Hash } else { 'NOT_FOUND' }

    $changed = ($srcHash -ne $destHash)
    $Updates.Add(@{
        Package  = $entry.Package
        Version  = $versionDir.Name
        Dll      = $entry.Dll
        Dest     = $destDll
        Src      = $srcDll
        Changed  = $changed
        SrcHash  = $srcHash
        DestHash = $destHash
    })
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("{0,-50} {1,-10} {2,-8}" -f 'Package', 'Version', 'Status') -ForegroundColor White
Write-Host ("-" * 72)
foreach ($u in $Updates) {
    $status = if ($u.Changed) { '[CHANGED]' } else { '[OK]' }
    $color  = if ($u.Changed) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-48} {1,-10} {2}" -f $u.Package, $u.Version, $status) -ForegroundColor $color
}

$changedCount = ($Updates | Where-Object { $_.Changed }).Count
Write-Host ""

if ($changedCount -eq 0) {
    Write-Host "All NuGet-sourced DLLs are up to date." -ForegroundColor Green
    exit 0
}

Write-Host ("$changedCount DLL(s) differ from current NuGet restore.") -ForegroundColor Yellow

if (-not $Apply) {
    Write-Host ""
    Write-Host "Run with -Apply to replace them." -ForegroundColor Cyan
    exit 0
}

# ---------------------------------------------------------------------------
# Apply updates
# ---------------------------------------------------------------------------
foreach ($u in $Updates | Where-Object { $_.Changed }) {
    $destDir = Split-Path $u.Dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }

    if ($PSCmdlet.ShouldProcess($u.Dest, "Replace with $($u.Package) $($u.Version)")) {
        Copy-Item -Path $u.Src -Destination $u.Dest -Force
        Write-Host ("  [UPDATED] {0} -> {1}" -f $u.Dll, $u.Dest) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Done. Re-run without -Apply to verify." -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: lib/native/FTD2XX.dll and lib/**/FTD2XX_NET.dll are NOT managed" -ForegroundColor DarkYellow
Write-Host "      by this script. Check https://ftdichip.com/drivers/d2xx-drivers/ manually." -ForegroundColor DarkYellow

# Cleanup
if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
