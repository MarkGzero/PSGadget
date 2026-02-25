# Invoke-NativeProcess.ps1
# Helper function for invoking native processes safely

function Invoke-NativeProcess {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @(),
        
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = (Get-Location).Path,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30,
        
        [Parameter(Mandatory = $false)]
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )
    
    try {
        # Create process start info
        $ProcessStartInfo = [System.Diagnostics.ProcessStartInfo]@{
            FileName = $FilePath
            Arguments = ($ArgumentList -join ' ')
            WorkingDirectory = $WorkingDirectory
            UseShellExecute = $false
            RedirectStandardOutput = $true
            RedirectStandardError = $true
            CreateNoWindow = $true
            StandardOutputEncoding = $Encoding
            StandardErrorEncoding = $Encoding
        }
        
        # Start the process
        $Process = [System.Diagnostics.Process]::Start($ProcessStartInfo)
        
        # Wait for completion with timeout
        $Completed = $Process.WaitForExit($TimeoutSeconds * 1000)
        
        if (-not $Completed) {
            $Process.Kill()
            throw [System.TimeoutException]::new("Process timed out after $TimeoutSeconds seconds")
        }
        
        # Read output streams
        $StandardOutput = $Process.StandardOutput.ReadToEnd()
        $StandardError = $Process.StandardError.ReadToEnd()
        $ExitCode = $Process.ExitCode
        
        # Clean up
        $Process.Dispose()
        
        return [PSCustomObject]@{
            ExitCode = $ExitCode
            StandardOutput = $StandardOutput
            StandardError = $StandardError
            Success = ($ExitCode -eq 0)
            TimedOut = $false
        }
        
    } catch [System.TimeoutException] {
        return [PSCustomObject]@{
            ExitCode = -1
            StandardOutput = ""
            StandardError = $_.Exception.Message
            Success = $false
            TimedOut = $true
        }
    } catch {
        return [PSCustomObject]@{
            ExitCode = -1
            StandardOutput = ""
            StandardError = $_.Exception.Message
            Success = $false
            TimedOut = $false
        }
    }
}

function Test-NativeCommand {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    
    try {
        if ($PSVersionTable.PSVersion.Major -le 5 -or [System.Environment]::OSVersion.Platform -eq 'Win32NT') {
            # Windows: Use where.exe
            $Result = Invoke-NativeProcess -FilePath "where.exe" -ArgumentList @($Command) -TimeoutSeconds 5
        } else {
            # Unix: Use which
            $Result = Invoke-NativeProcess -FilePath "which" -ArgumentList @($Command) -TimeoutSeconds 5
        }
        
        return $Result.Success
    } catch {
        return $false
    }
}