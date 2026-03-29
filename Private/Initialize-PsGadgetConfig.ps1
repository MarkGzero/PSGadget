# Initialize-PsGadgetConfig.ps1
# Loads ~/.psgadget/config.json into $script:PsGadgetConfig.
# Creates config.json with defaults if it does not exist.
# Called by Initialize-PsGadgetEnvironment on module import.

#Requires -Version 5.1

# Default configuration values. Any key missing from config.json is filled in from here.
$script:PsGadgetConfigDefaults = [PSCustomObject]@{
    ftdi = [PSCustomObject]@{
        # Double the CBUS output drive strength from 4 mA to 8 mA.
        # Apply with Set-PsGadgetFt232rCbusMode when writing EEPROM.
        highDriveIOs    = $false

        # Add weak pull-downs on all I/O pins during USB suspend so pins go LOW
        # rather than floating when the host suspends the USB bus.
        pullDownEnable  = $false

        # Set the device's default driver mode to D2XX instead of VCP (COM port).
        # When true, the device enumerates only once (no duplicate COM port entry).
        # Requires a USB replug after EEPROM write to take effect.
        rIsD2XX         = $false
    }
    logging = [PSCustomObject]@{
        # Minimum severity level written to log files.
        # Valid values (ascending verbosity): ERROR, WARN, INFO, DEBUG, TRACE
        level      = 'INFO'

        # Maximum size of psgadget.log in megabytes before it is rolled to psgadget.1.log.
        maxSizeMb  = 50
    }
}

function Initialize-PsGadgetConfig {
    <#
    .SYNOPSIS
    Loads or creates the PSGadget user configuration file.

    .DESCRIPTION
    Reads ~/.psgadget/config.json into the module-scope $script:PsGadgetConfig
    variable. Any key not present in config.json is filled in from the built-in
    defaults so the config object is always fully populated.

    If config.json does not exist it is created with all default values.
    If config.json is malformed JSON a warning is emitted and defaults are used;
    the file is not overwritten so the user can fix it manually.

    Called automatically by Initialize-PsGadgetEnvironment on module import.
    Do not call this directly -- use Get-PsGadgetConfig / Set-PsGadgetConfig instead.
    #>
    [CmdletBinding()]
    param()

    $UserHome      = [Environment]::GetFolderPath("UserProfile")
    $ConfigDir     = Join-Path $UserHome ".psgadget"
    $ConfigFile    = Join-Path $ConfigDir "config.json"

    # Start with a deep copy of defaults
    $config = [PSCustomObject]@{
        ftdi    = [PSCustomObject]@{
            highDriveIOs   = $script:PsGadgetConfigDefaults.ftdi.highDriveIOs
            pullDownEnable = $script:PsGadgetConfigDefaults.ftdi.pullDownEnable
            rIsD2XX        = $script:PsGadgetConfigDefaults.ftdi.rIsD2XX
        }
        logging = [PSCustomObject]@{
            level     = $script:PsGadgetConfigDefaults.logging.level
            maxSizeMb = $script:PsGadgetConfigDefaults.logging.maxSizeMb
        }
    }

    if (Test-Path $ConfigFile) {
        try {
            $raw  = Get-Content -Path $ConfigFile -Raw -Encoding UTF8
            $disk = $raw | ConvertFrom-Json

            # Merge disk values over defaults -- only recognized keys are applied
            if ($null -ne $disk.ftdi) {
                if ($null -ne $disk.ftdi.highDriveIOs)   { $config.ftdi.highDriveIOs   = [bool]$disk.ftdi.highDriveIOs }
                if ($null -ne $disk.ftdi.pullDownEnable)  { $config.ftdi.pullDownEnable  = [bool]$disk.ftdi.pullDownEnable }
                if ($null -ne $disk.ftdi.rIsD2XX)         { $config.ftdi.rIsD2XX         = [bool]$disk.ftdi.rIsD2XX }
            }
            if ($null -ne $disk.logging) {
                if ($null -ne $disk.logging.level)         {
                    $validLevels = @('ERROR','WARN','INFO','DEBUG','TRACE')
                    if ($validLevels -contains $disk.logging.level.ToUpper()) {
                        $config.logging.level = $disk.logging.level.ToUpper()
                    } else {
                        Write-Warning ("PSGadget config: logging.level '$($disk.logging.level)' is not valid. " +
                                       "Valid values: $($validLevels -join ', '). Using default 'INFO'.")
                    }
                }
                # Accept both new key (maxSizeMb) and old key (maxFileSizeMb) for migration
                if ($null -ne $disk.logging.maxSizeMb)     { $config.logging.maxSizeMb = [int]$disk.logging.maxSizeMb }
                elseif ($null -ne $disk.logging.maxFileSizeMb) { $config.logging.maxSizeMb = [int]$disk.logging.maxFileSizeMb }
            }

            Write-Verbose "PSGadget: loaded config from $ConfigFile"

        } catch {
            Write-Warning "PSGadget config: failed to parse '$ConfigFile' -- using defaults. Error: $($_.Exception.Message)"
        }
    } else {
        # Write the defaults to disk so the user has a file to edit
        try {
            $json = $config | ConvertTo-Json -Depth 4
            [System.IO.File]::WriteAllText($ConfigFile, $json, [System.Text.Encoding]::UTF8)
            Write-Verbose "PSGadget: created default config at $ConfigFile"
        } catch {
            Write-Warning "PSGadget config: could not write default config to '$ConfigFile': $($_.Exception.Message)"
        }
    }

    $script:PsGadgetConfig     = $config
    $script:PsGadgetConfigFile = $ConfigFile
}
