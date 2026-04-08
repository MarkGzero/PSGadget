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

    Each unique connection object appears exactly once. If multiple variables
    reference the same object (aliases), the first variable name is shown in
    Variable and the rest appear in Aliases.

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
    PSCustomObject with Variable, Aliases, SerialNumber, Type, GpioMethod, IsOpen.
    #>

    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [switch]$IncludeClosed
    )

    # Phase 1: harvest all (label, object) pairs from global scope.
    # Multiple variables may alias the same underlying object instance.
    $candidates = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($var in (Get-Variable -Scope Global -ErrorAction SilentlyContinue)) {
        $val = $var.Value
        if ($null -eq $val) { continue }

        # Direct PsGadgetFtdi variable
        if ($val -is [PsGadgetFtdi]) {
            $candidates.Add([PSCustomObject]@{ Label = "`$$($var.Name)"; Obj = $val })
            continue
        }

        # Array containing PsGadgetFtdi instances
        if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
            try {
                $idx = 0
                foreach ($item in $val) {
                    if ($item -is [PsGadgetFtdi]) {
                        $candidates.Add([PSCustomObject]@{ Label = "`$$($var.Name)[$idx]"; Obj = $item })
                    }
                    $idx++
                }
            } catch { }
            continue
        }

        # Hashtable containing PsGadgetFtdi instances
        if ($val -is [System.Collections.IDictionary]) {
            try {
                foreach ($key in $val.Keys) {
                    $item = $val[$key]
                    if ($item -is [PsGadgetFtdi]) {
                        $candidates.Add([PSCustomObject]@{ Label = "`$$($var.Name)['$key']"; Obj = $item })
                    }
                }
            } catch { }
        }
    }

    # Phase 2: deduplicate by object identity.
    # Group all variable labels that alias the same underlying object instance.
    $uniqueObjects = [System.Collections.Generic.List[object]]::new()
    $uniqueLabels  = [System.Collections.Generic.List[System.Collections.Generic.List[string]]]::new()

    foreach ($c in $candidates) {
        $found = $false
        for ($i = 0; $i -lt $uniqueObjects.Count; $i++) {
            if ([object]::ReferenceEquals($uniqueObjects[$i], $c.Obj)) {
                $uniqueLabels[$i].Add($c.Label)
                $found = $true
                break
            }
        }
        if (-not $found) {
            $uniqueObjects.Add($c.Obj)
            $labelList = [System.Collections.Generic.List[string]]::new()
            $labelList.Add($c.Label)
            $uniqueLabels.Add($labelList)
        }
    }

    # Phase 3: build results -- one row per unique object, filtered by IsOpen.
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($i = 0; $i -lt $uniqueObjects.Count; $i++) {
        $obj    = $uniqueObjects[$i]
        $labels = $uniqueLabels[$i]

        if (-not $IncludeClosed -and -not $obj.IsOpen) { continue }

        $results.Add([PSCustomObject]@{
            Variable     = $labels[0]
            Aliases      = if ($labels.Count -gt 1) { ($labels | Select-Object -Skip 1) -join ', ' } else { '' }
            SerialNumber = $obj.SerialNumber
            Type         = $obj.Type
            GpioMethod   = $obj.GpioMethod
            IsOpen       = $obj.IsOpen
        })
    }

    if ($results.Count -eq 0 -and -not $IncludeClosed) {
        Write-Verbose "No open PsGadgetFtdi devices found. Use -IncludeClosed to include closed handles."
    }

    return $results.ToArray()
}
