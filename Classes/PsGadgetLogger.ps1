#Requires -Version 5.1
# PsGadgetLogger Class
# Unified session + protocol logger.  All device instances share a single module-level
# singleton (created in PSGadget.psm1) that appends to a fixed
# ~/.psgadget/logs/psgadget.log file.  When TraceEnabled = $true (set by
# Open-PsGadgetTrace), WriteProto() entries are also written at [PROTO] level.
# Rolls to psgadget.1.log when the file exceeds _maxSizeMb at open time.

class PsGadgetLogger {
    [string]  $LogFilePath
    [string]  $SessionId
    [datetime]$StartTime
    [bool]    $TraceEnabled        # false until Open-PsGadgetTrace is called
    hidden [System.IO.StreamWriter]$_writer
    hidden [int]$_maxSizeMb

    PsGadgetLogger() {
        $this.StartTime   = [datetime]::Now
        $this.SessionId   = [System.Guid]::NewGuid().ToString().Substring(0, 8)
        $this.TraceEnabled = $false

        # Read max size from config if available; default 50 MB
        try {
            $cfg = $script:PsGadgetConfig
            if ($cfg -and $cfg.logging -and $cfg.logging.maxSizeMb) {
                $this._maxSizeMb = [int]$cfg.logging.maxSizeMb
            } else {
                $this._maxSizeMb = 50
            }
        } catch {
            $this._maxSizeMb = 50
        }

        $userHome = [Environment]::GetFolderPath('UserProfile')
        $logDir   = Join-Path $userHome '.psgadget/logs'

        if (-not (Test-Path -LiteralPath $logDir)) {
            $null = New-Item -Path $logDir -ItemType Directory -Force
        }

        $this.LogFilePath = Join-Path $logDir 'psgadget.log'

        # Roll if the file already exceeds maxSizeMb
        try {
            if (Test-Path -LiteralPath $this.LogFilePath) {
                $sizeMb = (Get-Item -LiteralPath $this.LogFilePath).Length / 1MB
                if ($sizeMb -ge $this._maxSizeMb) {
                    $backup = Join-Path $logDir 'psgadget.1.log'
                    Copy-Item -LiteralPath $this.LogFilePath -Destination $backup -Force
                    # Truncate by recreating
                    [System.IO.File]::WriteAllText($this.LogFilePath, '')
                }
            }
        } catch {}

        # Open for append with ReadWrite share so Get-Content -Wait can tail it
        try {
            $fs = [System.IO.File]::Open(
                $this.LogFilePath,
                [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::ReadWrite
            )
            $this._writer = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
            $this._writer.AutoFlush = $true
        } catch {
            # Silent -- log failure must never break hardware operations
            return
        }

        $this.WriteHeader()
    }

    hidden [void] WriteHeader() {
        $ts = $this.StartTime.ToString('yyyy-MM-dd HH:mm:ss')
        $lines = @(
            "=== PsGadget Session $($this.SessionId)  $ts ===",
            "OS: $([System.Environment]::OSVersion.VersionString)",
            "PowerShell: $($global:PSVersionTable.PSVersion)",
            "User: $([System.Environment]::UserName)  Computer: $([System.Environment]::MachineName)"
        )
        foreach ($line in $lines) {
            $this.WriteToFile('HEADER', $line)
        }
    }

    hidden [void] WriteToFile([string]$Level, [string]$Message) {
        if (-not $this._writer) { return }
        try {
            $ts = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $this._writer.WriteLine("[$ts] [$Level] $Message")
        } catch {}
    }

    # -- Standard log levels --------------------------------------------------

    [void] WriteInfo([string]$Message) {
        $this.WriteToFile('INFO', $Message)
        Write-Verbose $Message
    }

    [void] WriteDebug([string]$Message) {
        $this.WriteToFile('DEBUG', $Message)
        Write-Debug $Message
    }

    [void] WriteTrace([string]$Message) {
        $this.WriteToFile('TRACE', $Message)
    }

    [void] WriteError([string]$Message) {
        $this.WriteToFile('ERROR', $Message)
        Write-Warning $Message
    }

    # -- Protocol-level entries (WriteProto) ----------------------------------
    # Written only when TraceEnabled = $true (set by Open-PsGadgetTrace).
    # Format:
    #   [timestamp] [PROTO]  {Subsystem,-12}  {Summary}
    #   [timestamp] [PROTO]  {' '*12}  RAW  {RawHex}

    [void] WriteProto([string]$Subsystem, [string]$Summary) {
        if (-not $this.TraceEnabled -or -not $this._writer) { return }
        try {
            $ts = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $this._writer.WriteLine("[$ts] [PROTO]  $($Subsystem.PadRight(12))  $Summary")
        } catch {}
    }

    [void] WriteProto([string]$Subsystem, [string]$Summary, [string]$RawHex) {
        if (-not $this.TraceEnabled -or -not $this._writer) { return }
        try {
            $ts  = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $pad = ' ' * 12
            $this._writer.WriteLine("[$ts] [PROTO]  $($Subsystem.PadRight(12))  $Summary")
            if ($RawHex) {
                $this._writer.WriteLine("[$ts] [PROTO]  $pad  RAW  $RawHex")
            }
        } catch {}
    }

    # -- Hex formatting helper (moved from PsGadgetTrace) --------------------

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

    # Truncate the log file and reopen the writer so subsequent writes land at offset 0.
    # Used by Open-PsGadgetTrace -Clear -- calling Clear-Content externally leaves the
    # StreamWriter's position stale, causing writes to be preceded by a null-byte gap.
    [void] Clear() {
        try {
            if ($this._writer) {
                $this._writer.Flush()
                $this._writer.Close()
                $this._writer = $null
            }
            [System.IO.File]::WriteAllText($this.LogFilePath, '')
            $fs = [System.IO.File]::Open(
                $this.LogFilePath,
                [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::ReadWrite
            )
            $this._writer = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
            $this._writer.AutoFlush = $true
            $this.WriteHeader()
        } catch {}
    }

    [void] Dispose() {
        if ($this._writer) {
            try { $this._writer.Close() } catch {}
            $this._writer = $null
        }
    }
}
