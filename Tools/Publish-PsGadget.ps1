#Requires -Version 5.1
<#
.SYNOPSIS
    Stage and publish PSGadget to the PowerShell Gallery.

.DESCRIPTION
    Copies only publishable module files (Classes, Private, Public, lib DLLs,
    PSGadget.psd1, PSGadget.psm1) to a clean temp staging folder, then calls
    Publish-Module against that folder. Docs, examples, tests, tools, and build
    artifacts are intentionally excluded from the package.

.PARAMETER NuGetApiKey
    Your PowerShell Gallery API key from https://www.powershellgallery.com/account

.PARAMETER DryRun
    Stages files and reports what would be published, without actually calling
    Publish-Module.

.EXAMPLE
    .\Tools\Publish-PsGadget.ps1 -DryRun
    .\Tools\Publish-PsGadget.ps1 -NuGetApiKey $env:PSGALLERY_API_KEY
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$NuGetApiKey,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path $PSScriptRoot -Parent
$stagingDir = Join-Path $env:TEMP 'PSGadget'

Write-Host "Module root : $moduleRoot"
Write-Host "Staging dir : $stagingDir"

# -----------------------------------------------------------------------
# Clean staging area
# -----------------------------------------------------------------------
if (Test-Path $stagingDir) {
    Remove-Item $stagingDir -Recurse -Force
}
New-Item $stagingDir -ItemType Directory -Force | Out-Null

# -----------------------------------------------------------------------
# Module root files
# -----------------------------------------------------------------------
Copy-Item (Join-Path $moduleRoot 'PSGadget.psd1') $stagingDir
Copy-Item (Join-Path $moduleRoot 'PSGadget.psm1') $stagingDir

# -----------------------------------------------------------------------
# Code folders (Classes, Private, Public) - full copy, all .ps1 files
# -----------------------------------------------------------------------
foreach ($folder in @('Classes', 'Private', 'Public')) {
    $src  = Join-Path $moduleRoot $folder
    $dest = Join-Path $stagingDir $folder
    Copy-Item $src $dest -Recurse
}

# -----------------------------------------------------------------------
# lib - only runtime DLLs + supporting files; exclude bin/ obj/ *.csproj
# -----------------------------------------------------------------------
$libDest = Join-Path $stagingDir 'lib'
New-Item $libDest -ItemType Directory -Force | Out-Null

Copy-Item (Join-Path $moduleRoot 'lib\README.md') $libDest

foreach ($libFolder in @('net48', 'netstandard20', 'native', 'net8', 'ftdisharp')) {
    $src  = Join-Path $moduleRoot "lib\$libFolder"
    if (-not (Test-Path $src)) { continue }
    $dest = Join-Path $libDest $libFolder
    New-Item $dest -ItemType Directory -Force | Out-Null
    # Copy DLLs and metadata files only
    foreach ($ext in @('*.dll', '*.xml', '*.json')) {
        $items = Get-ChildItem $src -Filter $ext -File -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            Copy-Item $item.FullName $dest
        }
    }
}

# -----------------------------------------------------------------------
# Report staged file list
# -----------------------------------------------------------------------
$stagedFiles = @(Get-ChildItem $stagingDir -Recurse -File)
Write-Host ""
Write-Host "Staged $($stagedFiles.Count) files:"
$stagedFiles | ForEach-Object { Write-Host "  $($_.FullName.Replace($stagingDir, '.'))" }
Write-Host ""

# -----------------------------------------------------------------------
# Validate manifest can be read from staging
# -----------------------------------------------------------------------
$psd1Path = Join-Path $stagingDir 'PSGadget.psd1'
$manifest  = Test-ModuleManifest -Path $psd1Path -ErrorAction Stop
Write-Host "Manifest valid: $($manifest.Name) v$($manifest.Version)"
Write-Host ""

# -----------------------------------------------------------------------
# Publish (-DryRun skips the actual Publish-Module call)
# -----------------------------------------------------------------------
if ($DryRun) {
    Write-Host "DryRun: Would publish PSGadget v$($manifest.Version) to PSGallery from $stagingDir"
    return
}

if (-not $NuGetApiKey) {
    Write-Error "Provide -NuGetApiKey to publish, or use -DryRun to verify staging only."
    return
}

Write-Host "Publishing PSGadget v$($manifest.Version) to PSGallery..."
Publish-Module -Path $stagingDir -NuGetApiKey $NuGetApiKey -Repository PSGallery -Verbose
Write-Host "Published successfully."
