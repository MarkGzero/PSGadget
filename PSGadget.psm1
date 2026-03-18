# PsGadget Module Loader
# PowerShell 5.1+ compatible module bootstrapper

#Requires -Version 5.1

# Get the module root directory
$ModuleRoot = $PSScriptRoot

# 1. Load all Class files first (dependency order matters)
$ClassFiles = @(
    'PsGadgetLogger.ps1',
    'PsGadgetI2CDevice.ps1',
    'PsGadgetSsd1306.ps1',
    'PsGadgetFtdi.ps1',
    'PsGadgetMpy.ps1',
    'PsGadgetPca9685.ps1'
)

foreach ($ClassFile in $ClassFiles) {
    $ClassPath = Join-Path -Path $ModuleRoot -ChildPath "Classes/$ClassFile"
    if (Test-Path -Path $ClassPath) {
        . $ClassPath
    } else {
        Write-Warning "Class file not found: $ClassPath"
    }
}

# 2. Load all Private functions
$PrivateFiles = Get-ChildItem -Path "$ModuleRoot/Private" -Filter "*.ps1" -ErrorAction SilentlyContinue

foreach ($PrivateFile in $PrivateFiles) {
    . $PrivateFile.FullName
}

# 3. Load all Public functions
$PublicFiles = Get-ChildItem -Path "$ModuleRoot/Public" -Filter "*.ps1" -ErrorAction SilentlyContinue

foreach ($PublicFile in $PublicFiles) {
    . $PublicFile.FullName
}

# 4. Initialize FTDI assembly loading
$script:FtdiInitialized = $false
try {
    $script:FtdiInitialized = Initialize-FtdiAssembly -ModuleRoot $ModuleRoot -Verbose:($VerbosePreference -ne 'SilentlyContinue')
    if ($script:FtdiInitialized) {
        Write-Verbose "FTDI D2XX assembly loaded successfully"
    } else {
        Write-Verbose "FTDI assembly not available - using stub mode"
    }
} catch {
    Write-Warning "Failed to initialize FTDI assembly: $_"
    $script:FtdiInitialized = $false
}

# 5. Initialize the PsGadget environment
try {
    Initialize-PsGadgetEnvironment
} catch {
    Write-Warning "Failed to initialize PsGadget environment: $_"
}