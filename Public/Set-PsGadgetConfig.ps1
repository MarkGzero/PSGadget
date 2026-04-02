# Set-PsGadgetConfig.ps1
# Updates a PSGadget configuration value and persists it to ~/.psgadget/config.json.

#Requires -Version 5.1

function Set-PsGadgetConfig {
    <#
    .SYNOPSIS
    Sets a PSGadget configuration value and saves it to disk.

    .DESCRIPTION
    Updates a single setting identified by a dot-path Key (e.g. 'ftdi.highDriveIOs')
    and immediately writes the updated config back to ~/.psgadget/config.json.

    The change takes effect for the current session right away (no module reload
    needed). Settings that feed into EEPROM operations (ftdi.highDriveIOs, etc.)
    are applied the next time Set-PsGadgetFt232rCbusMode is called; they do not
    retroactively change what is already written to a device's EEPROM.

    .PARAMETER Key
    Dot-path to the setting to change. Format: '<section>.<name>'
    Examples:
        ftdi.highDriveIOs
        ftdi.pullDownEnable
        ftdi.rIsD2XX
        logging.level
        logging.maxSizeMb

    .PARAMETER Value
    New value for the setting. PowerShell will coerce the type if possible
    (e.g. $true/$false for booleans, integers for numeric fields).

    .EXAMPLE
    # Enable 8 mA drive strength for future EEPROM writes
    Set-PsGadgetConfig -Key ftdi.highDriveIOs -Value $true

    .EXAMPLE
    # Switch device default mode to D2XX (no COM port duplicate)
    Set-PsGadgetConfig -Key ftdi.rIsD2XX -Value $true

    .EXAMPLE
    # Increase log verbosity
    Set-PsGadgetConfig -Key logging.level -Value DEBUG

    .EXAMPLE
    # Increase log max size to 100 MB before rolling
    Set-PsGadgetConfig -Key logging.maxSizeMb -Value 100

    .NOTES
    Configuration is stored at:  ~/.psgadget/config.json
    See:  Get-Help about_PsGadgetConfig   for a full description of every setting.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet(
            'ftdi.highDriveIOs',
            'ftdi.pullDownEnable',
            'ftdi.rIsD2XX',
            'logging.level',
            'logging.maxSizeMb'
        )]
        [string]$Key,

        [Parameter(Mandatory = $true, Position = 1)]
        [object]$Value
    )

    if (-not $script:PsGadgetConfig) {
        throw "PSGadget config is not initialized. Re-import the module first."
    }

    $parts   = $Key.Split('.')
    $section = $parts[0]
    $name    = $parts[1]

    # Type-validate and coerce per known key
    $coerced = switch ($Key) {
        'ftdi.highDriveIOs'     { [bool]$Value }
        'ftdi.pullDownEnable'   { [bool]$Value }
        'ftdi.rIsD2XX'          { [bool]$Value }
        'logging.level'         {
            $upper = $Value.ToString().ToUpper()
            $valid = @('ERROR','WARN','INFO','DEBUG','TRACE')
            if ($valid -notcontains $upper) {
                throw "Invalid logging.level '$Value'. Valid values: $($valid -join ', ')"
            }
            $upper
        }
        'logging.maxSizeMb'     { [int]$Value }
        default                 { $Value }
    }

    $current = $script:PsGadgetConfig.$section.$name
    $action  = "Set $Key = $coerced (was: $current)"

    if (-not $PSCmdlet.ShouldProcess($script:PsGadgetConfigFile, $action)) {
        return
    }

    # Apply to in-memory config
    $script:PsGadgetConfig.$section.$name = $coerced

    # Persist to disk
    try {
        $json = $script:PsGadgetConfig | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($script:PsGadgetConfigFile, $json, [System.Text.Encoding]::UTF8)
        Write-Verbose "PSGadget config saved: $Key = $coerced -> $($script:PsGadgetConfigFile)"
    } catch {
        Write-Error "PSGadget config: failed to write '$($script:PsGadgetConfigFile)': $($_.Exception.Message)"
    }
}
