# PsGadget.psm1
Write-Verbose "PsGadget module loaded"

function Get-PsGadgetInfo {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        Name    = 'PsGadget'
        Status  = 'Under Development'
        Version = '0.0.3'
    }
}

Export-ModuleMember -Function Get-PsGadgetInfo