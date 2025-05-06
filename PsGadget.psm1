Add-Type -Path "$PSScriptRoot\lib\FtdiSharp.dll"

write-host $PSScriptRoot

$script:glyphs = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)

Get-ChildItem "$PSScriptRoot\src\" -Filter *.ps1 | ForEach-Object {
    try {
        Write-host  $_.FullName
        . $_.FullName
    } catch {
        Write-Error $_
    }
}
