#Requires -Version 5.1
# Get-ConnectedPsGadget.ps1
# Lists all PsGadgetFtdi instances currently held in session variables.

function Get-ConnectedPsGadget {
    <#
    .SYNOPSIS
    Lists all PsGadgetFtdi objects currently held in session variables.

    .DESCRIPTION
    Scans all variables in the global scope for PsGadgetFtdi instances and
    returns a summary showing the variable name, serial number, device type,
    GPIO method, and open state.

    Useful for auditing which devices are open, identifying stale handles
    (IsOpen = False), and finding the variable name for a given device.

    Arrays and hashtables containing PsGadgetFtdi instances are also scanned.

    .PARAMETER IncludeClosed
    Include PsGadgetFtdi instances where IsOpen = False. By default only
    open devices are returned.

    .EXAMPLE
    Get-ConnectedPsGadget

    .EXAMPLE
    # Include stale closed handles
    Get-ConnectedPsGadget -IncludeClosed

    .OUTPUTS
    PSCustomObject with Variable, SerialNumber, Type, GpioMethod, IsOpen.
    #>

    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [switch]$IncludeClosed
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($var in (Get-Variable -Scope Global -ErrorAction SilentlyContinue)) {
        $val = $var.Value
        if ($null -eq $val) { continue }

        # Direct PsGadgetFtdi variable
        if ($val -is [PsGadgetFtdi]) {
            if ($IncludeClosed -or $val.IsOpen) {
                $results.Add([PSCustomObject]@{
                    Variable     = "`$$($var.Name)"
                    SerialNumber = $val.SerialNumber
                    Type         = $val.Type
                    GpioMethod   = $val.GpioMethod
                    IsOpen       = $val.IsOpen
                })
            }
            continue
        }

        # Array containing PsGadgetFtdi instances
        if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
            try {
                $idx = 0
                foreach ($item in $val) {
                    if ($item -is [PsGadgetFtdi] -and ($IncludeClosed -or $item.IsOpen)) {
                        $results.Add([PSCustomObject]@{
                            Variable     = "`$$($var.Name)[$idx]"
                            SerialNumber = $item.SerialNumber
                            Type         = $item.Type
                            GpioMethod   = $item.GpioMethod
                            IsOpen       = $item.IsOpen
                        })
                    }
                    $idx++
                }
            } catch { continue }
            continue
        }

        # Hashtable containing PsGadgetFtdi instances
        if ($val -is [System.Collections.IDictionary]) {
            try {
                foreach ($key in $val.Keys) {
                    $item = $val[$key]
                    if ($item -is [PsGadgetFtdi] -and ($IncludeClosed -or $item.IsOpen)) {
                        $results.Add([PSCustomObject]@{
                            Variable     = "`$$($var.Name)['$key']"
                            SerialNumber = $item.SerialNumber
                            Type         = $item.Type
                            GpioMethod   = $item.GpioMethod
                            IsOpen       = $item.IsOpen
                        })
                    }
                }
            } catch { continue }
        }
    }

    if ($results.Count -eq 0 -and -not $IncludeClosed) {
        Write-Verbose "No open PsGadgetFtdi devices found. Use -IncludeClosed to include closed handles."
    }

    return $results.ToArray()
}
