# Deploy-ToMac.ps1
# Copies changed module files to MBP001 via SCP and reloads the module.
#
# Usage:
#   ./Tools/Deploy-ToMac.ps1              # deploy all tracked changed files
#   ./Tools/Deploy-ToMac.ps1 -Reload      # deploy + reload module on Mac
#   ./Tools/Deploy-ToMac.ps1 -File PSGadget.psm1  # deploy specific file only

[CmdletBinding()]
param(
    [string[]]$File,
    [switch]$Reload
)

$RemoteHost = 'MBP001'
$RemotePath = '/Users/AdminMark/psgadget'
$LocalRoot  = $PSScriptRoot | Split-Path   # repo root = parent of Tools/

# Resolve files to deploy
if ($File) {
    $filesToDeploy = $File | ForEach-Object {
        if ([System.IO.Path]::IsPathRooted($_)) { $_ }
        else { Join-Path $LocalRoot $_ }
    }
} else {
    # Deploy all files modified relative to HEAD (staged + unstaged)
    $changed = git -C $LocalRoot diff --name-only HEAD
    if (-not $changed) {
        Write-Host "Nothing changed relative to HEAD."
        exit 0
    }
    $filesToDeploy = $changed | ForEach-Object { Join-Path $LocalRoot $_ }
}

foreach ($localFile in $filesToDeploy) {
    if (-not (Test-Path $localFile)) {
        Write-Warning "File not found, skipping: $localFile"
        continue
    }

    # Compute relative path from repo root and build remote target path
    $rel        = $localFile.Substring($LocalRoot.Length).TrimStart('\', '/')
    $relFwd     = $rel -replace '\\', '/'
    $remoteFile = "$RemotePath/$relFwd"
    $remoteDir  = $remoteFile | Split-Path -Parent

    # Ensure remote directory exists, then copy
    ssh $RemoteHost "mkdir -p '$remoteDir'" 2>&1 | Out-Null
    Write-Host "scp -> $relFwd"
    scp -q "$localFile" "${RemoteHost}:${remoteFile}"
}

if ($Reload) {
    Write-Host "Reloading module on $RemoteHost..."
    ssh $RemoteHost "/usr/local/bin/pwsh -NoProfile -Command `"Import-Module $RemotePath/PSGadget.psm1 -Force; Write-Host 'Module reloaded'`""
}

Write-Host "Done."
