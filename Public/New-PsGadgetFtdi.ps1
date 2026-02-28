# New-PsGadgetFtdi.ps1
# Factory function to create and connect a PsGadgetFtdi instance.
# Because PowerShell module classes are not exported to the caller's type scope,
# consumers cannot write [PsGadgetFtdi]::new() directly.  Use this function
# instead.  The returned object is already connected - no .Connect() call needed.
# Mirrors MicroPython convention: construction = connection.

function New-PsGadgetFtdi {
    <#
    .SYNOPSIS
    Creates and connects a PsGadgetFtdi device object, ready to use immediately.

    .DESCRIPTION
    Instantiates a PsGadgetFtdi object and opens the hardware connection in one
    step.  The returned object is already open -- call .Scan(), .Display(),
    .SetPin() etc. directly.  Call .Close() when done, or wrap in try/finally
    for deterministic cleanup.

    Mirrors MicroPython convention where construction implies connection:
        i2c = I2C(0, scl=Pin(1), sda=Pin(0))   # MicroPython - connected immediately
        $dev = New-PsGadgetFtdi -Index 0         # PSGadget   - connected immediately

    .PARAMETER SerialNumber
    FTDI device serial number (e.g. "FT9ZLJ51").
    Preferred: stable across USB re-plugs regardless of port order.
    Use List-PsGadgetFtdi to find the serial number.

    .PARAMETER Index
    FTDI device index (0-based) from List-PsGadgetFtdi.
    May change if devices are plugged in different order.

    .PARAMETER LocationId
    FTDI USB LocationId (hub+port address) from List-PsGadgetFtdi.
    Stable for a fixed physical USB port - useful for demo rigs.

    .EXAMPLE
    # Minimal - index workflow
    $dev = New-PsGadgetFtdi -Index 0
    $dev.Scan() | Format-Table
    $dev.Display("Hello", 0)
    $dev.Close()

    .EXAMPLE
    # Preferred - serial number (stable across replug / hub reorder)
    $dev = New-PsGadgetFtdi -SerialNumber "FT9ZLJ51"
    $dev.SetPin(0, "HIGH")
    $dev.Close()

    .EXAMPLE
    # LocationId - best for fixed-port demo rigs
    $dev = New-PsGadgetFtdi -LocationId 197634
    $dev.Display("Ready", 0)
    $dev.Close()

    .EXAMPLE
    # try/finally for deterministic cleanup in scripts
    $dev = New-PsGadgetFtdi -Index 0
    try {
        $dev.Display("Running", 0)
        Start-Sleep -Seconds 2
        $dev.ClearDisplay()
    } finally {
        $dev.Close()
    }

    .OUTPUTS
    PsGadgetFtdi  (already connected, IsOpen = $true)
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
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
        $dev = [PsGadgetFtdi]::new($SerialNumber)
    } elseif ($PSCmdlet.ParameterSetName -eq 'ByIndex') {
        $dev = [PsGadgetFtdi]::new($Index)
    } else {
        # ByLocation: create via index constructor with -1, then set LocationId property
        $dev = [PsGadgetFtdi]::new(-1)
        $dev.LocationId  = $LocationId
        $dev.Description = "FTDI @ Location $LocationId"
    }

    # Connect immediately - mirrors MicroPython construction-implies-connection convention.
    # .Connect() is idempotent: if already open it returns immediately; if closed it reconnects.
    $dev.Connect()
    return $dev
}
