#Requires -Version 5.1
# Get-PsGadgetModuleLogger.ps1
# Returns the module-level PsGadgetLogger singleton.
# Called from class constructors (PsGadgetFtdi, PsGadgetI2CDevice, PsGadgetMpy)
# so all device instances share one log file.
# Falls back to a new instance when running outside the module (tests, dot-source).

function Get-PsGadgetModuleLogger {
    if ($script:PsGadgetLogger) {
        return $script:PsGadgetLogger
    }
    # Fallback: create a standalone instance (test/dot-source scenarios)
    return [PsGadgetLogger]::new()
}
