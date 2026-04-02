#Requires -Version 5.1
# Invoke-PsGadgetSpi.ps1
# High-level SPI dispatch cmdlet for FT232H via MPSSE.

function Invoke-PsGadgetSpi {
    <#
    .SYNOPSIS
    Performs a SPI write, read, or full-duplex transfer on an FTDI device.

    .DESCRIPTION
    Opens an FTDI device (or reuses an existing one), configures it for MPSSE SPI,
    then performs the requested operation:

        -Data only          Write-only: sends bytes to the SPI device.
        -ReadCount only     Read-only:  clocks in N bytes (MOSI stays LOW).
        -Data + -ReadCount  Full-duplex: writes Data while clocking in ReadCount bytes.
                            Data and ReadCount must be equal for true full-duplex.
                            If ReadCount < Data.Length only the first ReadCount bytes
                            are returned; if ReadCount > Data.Length, Data is zero-padded.

    The FTDI device is opened and closed automatically unless -PsGadget is supplied,
    in which case the caller retains ownership and the device stays open after the call.

    .PARAMETER PsGadget
    An already-open PsGadgetFtdi object. Device will NOT be closed after the call.

    .PARAMETER Index
    FTDI device index (0-based). Default 0.

    .PARAMETER SerialNumber
    FTDI device serial number (preferred over Index for stable identification).

    .PARAMETER Data
    Bytes to write to MOSI. Required for write and full-duplex operations.

    .PARAMETER ReadCount
    Number of bytes to read from MISO. Required for read and full-duplex operations.

    .PARAMETER ClockHz
    SPI clock frequency in Hz. Default 1 MHz (1000000). Max 30 MHz.

    .PARAMETER SpiMode
    SPI mode 0-3 (CPOL/CPHA). Default 0 (most common: clock idle LOW, sample rising edge).
        Mode 0: CPOL=0 CPHA=0 -- idle LOW,  sample rising,  shift falling
        Mode 1: CPOL=0 CPHA=1 -- idle LOW,  sample falling, shift rising
        Mode 2: CPOL=1 CPHA=0 -- idle HIGH, sample falling, shift rising
        Mode 3: CPOL=1 CPHA=1 -- idle HIGH, sample rising,  shift falling

    .PARAMETER CsPin
    ADBUS pin number used for chip select (active low). Default 3 (ADBUS3 / D3).
    Valid range 3-7. Pins 0-2 are reserved for SCK, MOSI, MISO.

    .EXAMPLE
    # Write 3 bytes to a SPI register
    Invoke-PsGadgetSpi -Index 0 -Data @(0x02, 0x00, 0xFF)

    .EXAMPLE
    # Read 4 bytes (MOSI=0x00 during read)
    $bytes = Invoke-PsGadgetSpi -Index 0 -ReadCount 4

    .EXAMPLE
    # Full-duplex transfer: write command byte, read 3-byte response
    $response = Invoke-PsGadgetSpi -Index 0 -Data @(0x01, 0x00, 0x00, 0x00) -ReadCount 4

    .EXAMPLE
    # 10 MHz SPI Mode 3, custom CS pin
    Invoke-PsGadgetSpi -Index 0 -Data @(0xAB) -ClockHz 10000000 -SpiMode 3 -CsPin 4

    .EXAMPLE
    # Reuse an open device (device stays open)
    $dev = New-PsGadgetFtdi -Index 0
    $rx  = Invoke-PsGadgetSpi -PsGadget $dev -Data @(0x9F) -ReadCount 3

    .EXAMPLE
    # Polling loop -- keep device open to avoid per-call open/close overhead
    $dev = New-PsGadgetFtdi -SerialNumber 'FT4ABCDE'
    try {
        while ($true) {
            # MCP3208 8-ch ADC: start=1, single-ended ch0, pad=0x00
            $raw = Invoke-PsGadgetSpi -PsGadget $dev -Data @(0x01, 0x80, 0x00) -ReadCount 3
            $value = (($raw[1] -band 0x0F) -shl 8) -bor $raw[2]
            Write-Host "ADC ch0: $value"
            Start-Sleep -Seconds 5
        }
    } finally {
        $dev.Close()
    }

    .OUTPUTS
    Write-only:   [bool] $true on success, $false on failure.
                  To suppress the bool from the pipeline use [void]: [void](Invoke-PsGadgetSpi ...)
    Read-only:    [byte[]] received bytes.
    Full-duplex:  [byte[]] received bytes (length = ReadCount).

    .NOTES
    Requires FT232H in MPSSE mode. FT232R does not support MPSSE SPI.
    Wire guide: D0=SCK  D1=MOSI  D2=MISO  D3=CS (10k pull-up to VCC)
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory = $true,  ParameterSetName = 'ByDevice', Position = 0)]
        [ValidateNotNull()]
        [object]$PsGadget,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByIndex')]
        [ValidateRange(0, 127)]
        [int]$Index = 0,

        [Parameter(Mandatory = $true,  ParameterSetName = 'BySerial')]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$Data,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65536)]
        [int]$ReadCount,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1000, 30000000)]
        [int]$ClockHz = 1000000,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3)]
        [int]$SpiMode = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(3, 7)]
        [int]$CsPin = 3
    )

    if (-not $PSBoundParameters.ContainsKey('Data') -and -not $PSBoundParameters.ContainsKey('ReadCount')) {
        throw "At least one of -Data or -ReadCount must be specified."
    }

    $ownsDevice = $PSCmdlet.ParameterSetName -ne 'ByDevice'
    $ftdi       = $null

    try {
        # --- open device ---
        if ($PSCmdlet.ParameterSetName -eq 'ByDevice') {
            $ftdi = $PsGadget
            if (-not $ftdi -or -not $ftdi.IsOpen) {
                throw "PsGadgetFtdi object is not open."
            }
        } elseif ($PSCmdlet.ParameterSetName -eq 'BySerial') {
            $ftdi = New-PsGadgetFtdi -SerialNumber $SerialNumber
        } else {
            $ftdi = New-PsGadgetFtdi -Index $Index
        }

        if (-not $ftdi -or -not $ftdi.IsOpen) {
            throw "Failed to open FTDI device"
        }

        # --- get or create SPI instance ---
        $spi = $ftdi.GetSpi($ClockHz, $SpiMode, $CsPin)
        if (-not $spi.IsInitialized) {
            throw "SPI initialization failed"
        }

        # --- dispatch ---
        $hasData      = $PSBoundParameters.ContainsKey('Data')
        $hasReadCount = $PSBoundParameters.ContainsKey('ReadCount')

        if ($hasData -and $hasReadCount) {
            # Full-duplex: pad or trim Data to match ReadCount
            $txData = $Data
            if ($txData.Length -ne $ReadCount) {
                $padded = [byte[]]::new($ReadCount)
                $copy   = [Math]::Min($txData.Length, $ReadCount)
                [Array]::Copy($txData, $padded, $copy)
                $txData = $padded
            }
            return $spi.Transfer($txData)
        } elseif ($hasData) {
            return $spi.Write($Data)
        } else {
            return $spi.Read($ReadCount)
        }

    } finally {
        if ($ownsDevice -and $ftdi -and $ftdi.IsOpen) {
            $ftdi.Close()
        }
    }
}
