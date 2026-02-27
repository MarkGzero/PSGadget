# Get-PsGadgetConfig.ps1
# Returns the current in-memory PSGadget configuration.

#Requires -Version 5.1

function Get-PsGadgetConfig {
    <#
    .SYNOPSIS
    Returns the current PSGadget user configuration.

    .DESCRIPTION
    Returns the PSCustomObject loaded from ~/.psgadget/config.json at module import.
    Missing keys are always filled in from built-in defaults, so the returned object
    is fully populated even if config.json only contains a subset of settings.

    Use dot notation to inspect a specific setting:
        (Get-PsGadgetConfig).ftdi.highDriveIOs

    Use Set-PsGadgetConfig to change a value and persist it to disk.
    Use the -Section parameter to restrict output to a named section (ftdi, logging).

    .PARAMETER Section
    Optional. Return only the named section ('ftdi' or 'logging') instead of the
    full config object. Useful for quickly inspecting a group of related settings.

    .EXAMPLE
    # Show the full config
    Get-PsGadgetConfig

    .EXAMPLE
    # Show only FTDI-related settings
    Get-PsGadgetConfig -Section ftdi

    .EXAMPLE
    # Read a single value
    (Get-PsGadgetConfig).ftdi.highDriveIOs

    .EXAMPLE
    # Pipe to Format-List for readable display
    Get-PsGadgetConfig | Format-List

    .NOTES
    Configuration is stored at:  ~/.psgadget/config.json
    See:  Get-Help about_PsGadgetConfig   for a full description of every setting.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('ftdi', 'logging')]
        [string]$Section
    )

    if (-not $script:PsGadgetConfig) {
        Write-Warning "PSGadget config is not initialized. Re-importing the module should fix this."
        return $null
    }

    if ($Section) {
        return $script:PsGadgetConfig.$Section
    }

    return $script:PsGadgetConfig
}
