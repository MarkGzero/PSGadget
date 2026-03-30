# Get-PsGadgetLog.ps1
# View the PSGadget unified session log.

#Requires -Version 5.1

function Get-PsGadgetLog {
    <#
    .SYNOPSIS
    View the PSGadget session log.

    .DESCRIPTION
    Displays the content of ~/.psgadget/logs/psgadget.log -- the unified session log
    that contains INFO/DEBUG/ERROR entries from all device instances plus [PROTO]
    wire-level entries when Open-PsGadgetTrace has been called this session.

    Use -List to also see the rolled backup (psgadget.1.log), -Tail to limit output
    lines, or -Follow to stream live updates.

    .PARAMETER List
    List the log file(s) with sizes and timestamps instead of showing content.

    .PARAMETER Tail
    Show only the last N lines. Default shows all lines.

    .PARAMETER Follow
    Stream the log file live (equivalent to tail -f). Press Ctrl+C to stop.

    .EXAMPLE
    # Show the full session log
    Get-PsGadgetLog

    .EXAMPLE
    # Stream live as hardware commands run
    Get-PsGadgetLog -Follow

    .EXAMPLE
    # Show last 50 lines
    Get-PsGadgetLog -Tail 50

    .EXAMPLE
    # List log files and sizes
    Get-PsGadgetLog -List

    .NOTES
    Log file:    ~/.psgadget/logs/psgadget.log
    Backup file: ~/.psgadget/logs/psgadget.1.log  (created when max size is reached)
    Log levels:  [HEADER] [INFO] [DEBUG] [TRACE] [ERROR] [PROTO]
    Protocol entries ([PROTO]) are written only after Open-PsGadgetTrace is called.
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

    $logDir  = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.psgadget/logs'
    $logFile = Join-Path $logDir 'psgadget.log'

    if (-not (Test-Path $logDir)) {
        Write-Warning "No log directory found at: $logDir"
        return
    }

    if ($List) {
        $files = @('psgadget.log', 'psgadget.1.log') |
                 ForEach-Object { Get-Item -LiteralPath (Join-Path $logDir $_) -ErrorAction SilentlyContinue } |
                 Where-Object { $_ }
        if (-not $files) {
            Write-Warning "No log files found in: $logDir"
            return
        }
        return $files | Select-Object Name,
            @{ Name = 'Size';     Expression = { '{0:N1} MB' -f ($_.Length / 1MB) } },
            @{ Name = 'Modified'; Expression = { $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } }
    }

    if (-not (Test-Path -LiteralPath $logFile)) {
        Write-Warning "Session log not found: $logFile  (import the module first)"
        return
    }

    if ($Follow) {
        Write-Host "Streaming: $logFile  (Ctrl+C to stop)"
        Get-Content -LiteralPath $logFile -Wait
        return
    }

    if ($Tail) {
        return Get-Content -LiteralPath $logFile -Tail $Tail
    }

    return Get-Content -LiteralPath $logFile
}
