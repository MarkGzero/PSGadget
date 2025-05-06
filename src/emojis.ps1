$script:emojis = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)

Write-Output "[$(Get-Date -format s)] Loaded emojis bitmap data: $($emojis.count) symbols."