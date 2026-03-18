# Initialize-PsGadgetEnvironment
# Sets up the required directory structure for PsGadget

function Initialize-PsGadgetEnvironment {
    [CmdletBinding()]
    param()
    
    try {
        # Get user home directory using .NET method for cross-platform compatibility
        $UserHome = [Environment]::GetFolderPath("UserProfile")
        
        # Define paths
        $PsGadgetRoot = Join-Path -Path $UserHome -ChildPath ".psgadget" 
        $LogsDirectory = Join-Path -Path $PsGadgetRoot -ChildPath "logs"
        
        # Create .psgadget directory if it doesn't exist
        if (-not (Test-Path -Path $PsGadgetRoot)) {
            $null = New-Item -Path $PsGadgetRoot -ItemType Directory -Force -ErrorAction Stop
        }
        
        # Create logs subdirectory if it doesn't exist  
        if (-not (Test-Path -Path $LogsDirectory)) {
            $null = New-Item -Path $LogsDirectory -ItemType Directory -Force -ErrorAction Stop
        }

        # Load user configuration from ~/.psgadget/config.json (creates defaults if missing)
        Initialize-PsGadgetConfig

    } catch {
        # Log error but don't fail module import
        Write-Warning "Failed to initialize PsGadget environment: $($_.Exception.Message)"
    }
}