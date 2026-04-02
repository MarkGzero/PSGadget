#Requires -Version 5.1
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
    step.  The returned object is already open -- call .ScanI2CBus(), .Display(),
    .SetPin() etc. directly.  Call .Close() when done, or wrap in try/finally
    for deterministic cleanup.

    Mirrors MicroPython convention where construction implies connection:
        i2c = I2C(0, scl=Pin(1), sda=Pin(0))   # MicroPython - connected immediately
        $dev = New-PsGadgetFtdi -Index 0         # PSGadget   - connected immediately

    .PARAMETER SerialNumber
    FTDI device serial number (e.g. "FT9ZLJ51").
    Preferred: stable across USB re-plugs regardless of port order.
    Use Get-FtdiDevice to find the serial number.

    .PARAMETER Index
    FTDI device index (0-based) from Get-FtdiDevice.
    May change if devices are plugged in different order.

    .PARAMETER LocationId
    FTDI USB LocationId (hub+port address) from Get-FtdiDevice.
    Stable for a fixed physical USB port - useful for demo rigs.

    .PARAMETER DisplayHeight
    SSD1306 OLED display height in pixels. Use 32 for 128x32 displays, 64 (default) for 128x64.
    Sets $dev.DisplayHeight before the first GetDisplay() call.  Can also be changed afterwards:
        $dev.DisplayHeight = 32

    .EXAMPLE
    # 128x32 OLED
    $dev = New-PsGadgetFtdi -Index 0 -DisplayHeight 32
    $dev.Display('hello')

    .EXAMPLE
    # Minimal - index workflow
    $dev = New-PsGadgetFtdi -Index 0
    $dev.ScanI2CBus() | Format-Table
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

    [CmdletBinding(DefaultParameterSetName = 'ByIndex', SupportsShouldProcess = $true)]
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
        [string]$LocationId,

        [Parameter(Mandatory = $false)]
        [ValidateSet(32, 64)]
        [int]$DisplayHeight = 64
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
    $dev.DisplayHeight = $DisplayHeight
    if ($PSCmdlet.ShouldProcess($dev.Description, 'Connect')) {
        # FT232R CBUS pins have internal 200k pull-ups to VCCIO (datasheet section 6, Note 1).
        # They float HIGH after power-up/reset regardless of software state.
        # EEPROM read opens its own D2XX handle -- must happen BEFORE Connect() to avoid conflict.
        # Suppress verbose on internal calls; only our summary message is relevant to the user.
        $cbusIoPins = [int[]]@()
        $savedVerbose = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        try {
            $devices = @(Get-FtdiDeviceList)
            $preConnectDev = switch ($PSCmdlet.ParameterSetName) {
                'ByIndex'    { $devices | Where-Object { $_.Index -eq $Index } | Select-Object -First 1 }
                'BySerial'   { $devices | Where-Object { $_.SerialNumber -eq $SerialNumber } | Select-Object -First 1 }
                'ByLocation' { $devices | Where-Object { "$($_.LocationId)" -eq $LocationId } | Select-Object -First 1 }
            }
            if ($preConnectDev -and $preConnectDev.Type -match '^FT232R') {
                $eeprom = Get-FtdiEeprom -Index $preConnectDev.Index
                if ($eeprom) {
                    $cbusIoPins = [int[]](0..3 | Where-Object { $eeprom."Cbus$_" -eq 'FT_CBUS_IOMODE' })
                }
            }
        } finally {
            $VerbosePreference = $savedVerbose
        }

        $dev.Connect()

        if ($cbusIoPins.Count -gt 0) {
            $pinList = ($cbusIoPins | ForEach-Object { "CBUS$_" }) -join ', '
            Write-Verbose "FT232R: CBUS pins float HIGH on power-up due to internal 200k ohm pull-ups (datasheet section 6, Note 1). This is safe for signal/LED use but could trigger relays or actuators. Auto-driving $pinList LOW."
            $dev.SetPins($cbusIoPins, $false)
        }
    }
    return $dev
}
