# Get-PsGadgetLog.ps1
# View PSGadget session log files.

#Requires -Version 5.1

function Get-PsGadgetLog {
    <#
    .SYNOPSIS
    View PSGadget session log files.

    .DESCRIPTION
    Displays the content of PSGadget log files stored at ~/.psgadget/logs/.
    Each module import creates a new log file named psgadget-yyyyMMdd-HHmmss.log.

    By default shows the latest log file. Use -List to browse all sessions,
    -Tail to limit output lines, or -Follow to stream a live session.

    .PARAMETER List
    List all available log files with timestamps, instead of showing content.

    .PARAMETER Tail
    Show only the last N lines of the log. Default shows all lines.

    .PARAMETER Follow
    Stream the log file live (equivalent to tail -f). Press Ctrl+C to stop.
    Implies the latest log file.

    .EXAMPLE
    # Show the latest session log
    Get-PsGadgetLog

    .EXAMPLE
    # Show only the last 30 lines
    Get-PsGadgetLog -Tail 30

    .EXAMPLE
    # List all log sessions
    Get-PsGadgetLog -List

    .EXAMPLE
    # Stream live log output during a session
    Get-PsGadgetLog -Follow

    .NOTES
    Log files are stored at:  ~/.psgadget/logs/
    Log levels written to file: INFO, DEBUG, TRACE, ERROR
    Console visibility: only ERROR (Write-Warning) is shown by default.
    Use -Verbose on any PSGadget cmdlet to see INFO messages in the console.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'List')]
        [switch]$List,

        [Parameter(Mandatory = $false, ParameterSetName = 'Content')]
        [ValidateRange(1, 100000)]
        [int]$Tail,

        [Parameter(Mandatory = $false, ParameterSetName = 'Follow')]
        [switch]$Follow
    )

    $logDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.psgadget/logs'

    if (-not (Test-Path $logDir)) {
        Write-Warning "No log directory found at: $logDir"
        return
    }

    $logFiles = Get-ChildItem -Path $logDir -Filter 'psgadget-*.log' |
                Sort-Object LastWriteTime -Descending

    if (-not $logFiles) {
        Write-Warning "No log files found in: $logDir"
        return
    }

    if ($List) {
        return $logFiles | Select-Object Name,
            @{ Name = 'Size'; Expression = { '{0:N0} KB' -f ($_.Length / 1KB) } },
            @{ Name = 'Created'; Expression = { $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } }
    }

    $latest = $logFiles | Select-Object -First 1

    if ($Follow) {
        Write-Host "Streaming: $($latest.FullName)  (Ctrl+C to stop)"
        Get-Content -Path $latest.FullName -Wait
        return
    }

    if ($Tail) {
        return Get-Content -Path $latest.FullName -Tail $Tail
    }

    return Get-Content -Path $latest.FullName
}
