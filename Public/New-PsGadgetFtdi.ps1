# New-PsGadgetFtdi.ps1
# Factory function to create a PsGadgetFtdi class instance.
# Because PowerShell module classes are not exported to the caller's type scope,
# consumers cannot write [PsGadgetFtdi]::new() directly.  Use this function
# instead.  The returned object is a live PsGadgetFtdi instance whose methods
# (.Connect, .SetPin, .SetPins, .PulsePin, .Close, .Write, .Read) work normally.

function New-PsGadgetFtdi {
    <#
    .SYNOPSIS
    Creates a PsGadgetFtdi device object ready for use.

    .DESCRIPTION
    Instantiates a PsGadgetFtdi class object identified by serial number or
    device index.  Call .Connect() on the returned object to open the hardware
    connection, then use .SetPin() / .SetPins() for GPIO control.

    .PARAMETER SerialNumber
    FTDI device serial number (e.g. "BG01X3GX").
    Use List-PsGadgetFtdi to find the serial number.

    .PARAMETER Index
    FTDI device index (0-based) from List-PsGadgetFtdi.

    .PARAMETER LocationId
    FTDI USB LocationId (hub+port address) from List-PsGadgetFtdi.
    More stable than Index across re-plugs when using a fixed USB port.

    .EXAMPLE
    # Serial number workflow (preferred - stable regardless of port)
    $dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"
    $dev.Connect()
    $dev.SetPin(0, "HIGH")   # CBUS0 HIGH
    $dev.SetPin(0, "LOW")    # CBUS0 LOW
    $dev.SetPins(@(0,1), "HIGH")
    $dev.PulsePin(0, "HIGH", 500)  # 500 ms pulse
    $dev.Close()

    .EXAMPLE
    # Index workflow
    $dev = New-PsGadgetFtdi -Index 0
    $dev.Connect()
    $dev.SetPin(2, $true)    # bool overload - $true = HIGH
    $dev.Close()

    .EXAMPLE
    # LocationId workflow (stable for fixed USB port, e.g. demo rigs)
    List-PsGadgetFtdi | Select-Object Index, SerialNumber, LocationId
    $dev = New-PsGadgetFtdi -LocationId 197634
    $dev.Connect()
    $dev.SetPin(0, "HIGH")
    $dev.Close()

    .OUTPUTS
    PsGadgetFtdi
    #>

    [CmdletBinding(DefaultParameterSetName = 'BySerial')]
    [OutputType('PsGadgetFtdi')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByIndex', Position = 0)]
        [ValidateRange(0, 127)]
        [int]$Index,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByLocation', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$LocationId
    )

    if ($PSCmdlet.ParameterSetName -eq 'BySerial') {
        return [PsGadgetFtdi]::new($SerialNumber)
    } elseif ($PSCmdlet.ParameterSetName -eq 'ByIndex') {
        return [PsGadgetFtdi]::new($Index)
    } else {
        # ByLocation: create via index constructor with -1, then set LocationId property
        $dev = [PsGadgetFtdi]::new(-1)
        $dev.LocationId   = $LocationId
        $dev.Description  = "FTDI @ Location $LocationId"
        return $dev
    }
}
