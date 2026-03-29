#Requires -Version 5.1
# PsGadgetTrace.ps1
# Module-level protocol trace writer — always-on, separate from per-device PsGadgetLogger.
# Written to ~/.psgadget/logs/trace-yyyyMMdd-HHmmss.log with ReadWrite file sharing so
# a second terminal can tail it while it is being written.

class PsGadgetTrace {
    [string]  $TraceFilePath
    [string]  $SessionId
    [datetime]$StartTime
    hidden [System.IO.StreamWriter]$_writer

    PsGadgetTrace() {
        $this.StartTime = [datetime]::Now
        $this.SessionId = [System.Guid]::NewGuid().ToString().Substring(0, 8)

        $userHome = [Environment]::GetFolderPath('UserProfile')
        $logDir   = Join-Path $userHome '.psgadget/logs'

        if (-not (Test-Path -LiteralPath $logDir)) {
            $null = New-Item -Path $logDir -ItemType Directory -Force
        }

        $ts = $this.StartTime.ToString('yyyyMMdd-HHmmss')
        $this.TraceFilePath = Join-Path $logDir "trace-$ts.log"

        try {
            # ReadWrite share so Get-Content -Wait in the viewer window can read while we write
            $fs = [System.IO.File]::Open(
                $this.TraceFilePath,
                [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::ReadWrite
            )
            $this._writer = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
            $this._writer.AutoFlush = $true

            $this._writer.WriteLine(
                "=== PsGadget Trace  session=$($this.SessionId)  $($this.StartTime.ToString('yyyy-MM-dd HH:mm:ss')) ==="
            )
        } catch {
            # Silent — trace failure must never break hardware operations
        }
    }

    # Format a byte array as hex, truncating at maxBytes with a [...+N] suffix
    [string] FormatHex([byte[]]$bytes) {
        return $this.FormatHex($bytes, 64)
    }

    [string] FormatHex([byte[]]$bytes, [int]$maxBytes) {
        if (-not $bytes -or $bytes.Length -eq 0) { return '' }
        $take = [System.Math]::Min($bytes.Length, $maxBytes)
        $hex  = ($bytes[0..($take - 1)] | ForEach-Object { $_.ToString('X2') }) -join ' '
        if ($bytes.Length -gt $maxBytes) {
            $hex += " [...+$($bytes.Length - $maxBytes)]"
        }
        return $hex
    }

    # Single-line entry: semantic summary only (no raw bytes — e.g. IoT abstracted path)
    [void] Write([string]$Subsystem, [string]$Summary) {
        if (-not $this._writer) { return }
        try {
            $ts = [datetime]::Now.ToString('HH:mm:ss.fff')
            $this._writer.WriteLine('{0}  {1,-12}  {2}' -f $ts, $Subsystem, $Summary)
        } catch {}
    }

    # Two-line entry: semantic summary + indented RAW hex line
    [void] Write([string]$Subsystem, [string]$Summary, [string]$RawHex) {
        if (-not $this._writer) { return }
        try {
            $ts  = [datetime]::Now.ToString('HH:mm:ss.fff')
            $pad = ' ' * 12
            $this._writer.WriteLine('{0}  {1,-12}  {2}' -f $ts, $Subsystem, $Summary)
            if ($RawHex) {
                $this._writer.WriteLine('{0}  {1,-12}  RAW  {2}' -f $pad, '', $RawHex)
            }
        } catch {}
    }

    [void] Dispose() {
        if ($this._writer) {
            try { $this._writer.Close() } catch {}
            $this._writer = $null
        }
    }
}
