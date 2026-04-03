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
    'PsGadgetSpi.ps1',
    'PsGadgetUart.ps1',
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
# Initialize-FtdiAssembly sets $script:FtdiInitialized = $script:D2xxLoaded (true only when
# FTD2XX_NET.dll loads -- Windows only).  Its return value is the broader "any backend ready"
# flag ($script:IotBackendAvailable -or $script:D2xxLoaded).  Do NOT assign the return value
# back to $script:FtdiInitialized or it will be $true on macOS/Linux (IoT available, D2XX not),
# causing Set-FtdiFt232rCbusPinMode to skip the native path and crash on [FTD2XX_NET.FTDI].
$script:FtdiInitialized = $false
try {
    $backendReady = Initialize-FtdiAssembly -ModuleRoot $ModuleRoot -Verbose:($VerbosePreference -ne 'SilentlyContinue')
    # $script:FtdiInitialized is now set correctly by Initialize-FtdiAssembly
    if ($backendReady) {
        Write-Verbose "FTDI backend ready (D2XX=$($script:FtdiInitialized) IoT=$($script:IotBackendAvailable))"
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

# 6. Singleton session logger — shared by all device instances.
# Created after Initialize-PsGadgetEnvironment so config (logging.maxSizeMb) is ready.
# All class constructors call Get-PsGadgetModuleLogger() to reference this instance.
$script:PsGadgetLogger = [PsGadgetLogger]::new()

# 7. Convenience aliases
Set-Alias -Name Get-PsGadgetOption -Value Get-PsGadgetConfig -Scope Script
Set-Alias -Name Set-PsGadgetOption -Value Set-PsGadgetConfig -Scope Script