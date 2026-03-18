# PsGadgetLogger Class
# Automatic logging for all PsGadget operations

class PsGadgetLogger {
    [string]$LogFilePath
    [string]$SessionId
    [datetime]$StartTime

    # Constructor
    PsGadgetLogger() {
        $this.StartTime = Get-Date
        $this.SessionId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
        
        # Get user home directory
        $UserHome = [Environment]::GetFolderPath("UserProfile")
        $LogDir = Join-Path -Path $UserHome -ChildPath ".psgadget/logs"
        
        # Ensure logs directory exists
        if (-not (Test-Path -Path $LogDir)) {
            $null = New-Item -Path $LogDir -ItemType Directory -Force
        }
        
        # Create log filename with timestamp
        $TimeStamp = $this.StartTime.ToString("yyyyMMdd-HHmmss")
        $LogFileName = "psgadget-$TimeStamp.log"
        $this.LogFilePath = Join-Path -Path $LogDir -ChildPath $LogFileName
        
        # Write session header
        $this.WriteHeader()
    }

    # Private method to write session header
    hidden [void] WriteHeader() {
        $Header = @(
            "=== PsGadget Session Started ===",
            "Timestamp: $($this.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))",
            "Session ID: $($this.SessionId)",
            "OS: $([System.Environment]::OSVersion.VersionString)",
            "PowerShell: $($global:PSVersionTable.PSVersion.ToString())",
            "Module Version: 0.1.0",
            "User: $([System.Environment]::UserName)",
            "Computer: $([System.Environment]::MachineName)",
            "================================="
        )
        
        foreach ($Line in $Header) {
            $this.WriteToFile("HEADER", $Line)
        }
    }

    # Private method to write to file
    hidden [void] WriteToFile([string]$Level, [string]$Message) {
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $LogEntry = "[$TimeStamp] [$Level] $Message"
        
        try {
            Add-Content -Path $this.LogFilePath -Value $LogEntry -Encoding UTF8 -ErrorAction Stop
        } catch {
            # Silently continue if logging fails - don't break functionality
        }
    }

    # Public logging methods
    [void] WriteInfo([string]$Message) {
        $this.WriteToFile("INFO", $Message)
        Write-Verbose $Message
    }

    [void] WriteDebug([string]$Message) {
        $this.WriteToFile("DEBUG", $Message)
        Write-Debug $Message
    }

    [void] WriteTrace([string]$Message) {
        $this.WriteToFile("TRACE", $Message)
        # Trace level - only to file
    }

    [void] WriteError([string]$Message) {
        $this.WriteToFile("ERROR", $Message)
        Write-Warning $Message
    }
}