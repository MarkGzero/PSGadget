#Requires -Version 5.1
# Invoke-PsGadgetUart.ps1
# High-level UART dispatch cmdlet for FTDI FT232R, FT232H, and compatible devices.

function Invoke-PsGadgetUart {
    <#
    .SYNOPSIS
    Performs a UART write, read, or readline on an FTDI device.

    .DESCRIPTION
    Opens an FTDI device (or reuses an existing one), configures it for D2XX UART,
    then performs the requested operation:

        -Data only          Write-only: sends bytes or a string to the device.
        -ReadCount only     Read-only:  waits for N bytes (up to ReadTimeout).
        -ReadLine           Read-only:  waits for a newline-terminated line.
        -Data + -ReadCount  Write then read: sends Data, then reads ReadCount bytes.
        -Data + -ReadLine   Write then readline: sends Data, then waits for a line.

    The FTDI device is opened and closed automatically unless -PsGadget is supplied,
    in which case the caller retains ownership and the device stays open after the call.

    .PARAMETER PsGadget
    An already-open PsGadgetFtdi object. Device will NOT be closed after the call.

    .PARAMETER Index
    FTDI device index (0-based). Default 0.

    .PARAMETER SerialNumber
    FTDI device serial number (preferred over Index for stable identification).

    .PARAMETER Data
    Bytes or a string to write. Strings are UTF-8 encoded. No line ending is added
    automatically — include "`r`n" or "`n" in the string as needed.

    .PARAMETER ReadCount
    Number of raw bytes to read after the optional write.

    .PARAMETER ReadLine
    After the optional write, read bytes until a newline (\n) is received or
    LineTimeout elapses. Returns $null on timeout, "" if device sent a bare \n,
    or the received line (with \r stripped) otherwise.

    .PARAMETER BaudRate
    Baud rate in bits per second. Default 9600.

    .PARAMETER DataBits
    Word length: 7 or 8. Default 8.

    .PARAMETER StopBits
    Stop bits: 1 or 2. Default 1.

    .PARAMETER Parity
    Parity: 'None', 'Odd', 'Even', 'Mark', 'Space'. Default 'None'.

    .PARAMETER FlowControl
    Flow control: 'None', 'RtsCts', 'DtrDsr', 'XonXoff'. Default 'None'.

    .PARAMETER ReadTimeout
    Milliseconds to wait for read data. Default 500.

    .PARAMETER WriteTimeout
    Milliseconds allowed for write completion. Default 500.

    .PARAMETER LineTimeout
    Milliseconds to wait for a newline when -ReadLine is used. Default 2000.

    .PARAMETER MaxLineLength
    Maximum bytes to buffer per ReadLine call before giving up. Default 1024.

    .EXAMPLE
    # Send "AT\r\n" and read the response line
    Invoke-PsGadgetUart -Index 0 -Data "AT`r`n" -ReadLine -BaudRate 9600

    .EXAMPLE
    # Raw read of 16 bytes at 115200 baud
    $bytes = Invoke-PsGadgetUart -Index 0 -ReadCount 16 -BaudRate 115200

    .EXAMPLE
    # Write binary bytes (no read)
    Invoke-PsGadgetUart -Index 0 -Data ([byte[]](0x01, 0x02, 0x03)) -BaudRate 57600

    .EXAMPLE
    # Reuse an open device (device stays open after the call)
    $dev  = New-PsGadgetFtdi -SerialNumber 'FTAXBFCQ'
    $line = Invoke-PsGadgetUart -PsGadget $dev -Data "STATUS`r`n" -ReadLine

    .EXAMPLE
    # Polling loop — keep device open to avoid per-call open/close overhead
    $dev = New-PsGadgetFtdi -SerialNumber 'FTAXBFCQ'
    try {
        while ($true) {
            $resp = Invoke-PsGadgetUart -PsGadget $dev -Data "READ`r`n" -ReadLine
            # $null = timeout (no \n received); "" = device sent bare \n; else = response line
            if ($null -ne $resp) {
                Write-Host "$(Get-Date -Format 'HH:mm:ss')  $resp"
            }
            Start-Sleep -Seconds 30
        }
    } finally {
        $dev.Close()
    }

    .OUTPUTS
    Write-only:   [bool] $true on success, $false on failure.
    Read-only:    [byte[]] for -ReadCount.
                  [string] for -ReadLine when a newline was received (may be "" for bare \n).
                  $null for -ReadLine when LineTimeout elapsed without receiving a newline.
    Write+Read:   [byte[]] or [string]/$null depending on read mode.

    .NOTES
    Supported on FT232R, FT232H, FT2232H, FT4232H in UART mode (SetBitMode 0x00).
    UART is the factory-default mode; no mode-switch is required.
    Wire guide (FT232R):  TX(D0)->RX of target  RX(D1)<-TX of target  GND->GND
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

        # Accept byte[] or string
        [Parameter(Mandatory = $false)]
        [object]$Data,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65536)]
        [int]$ReadCount,

        [Parameter(Mandatory = $false)]
        [switch]$ReadLine,

        [Parameter(Mandatory = $false)]
        [ValidateRange(300, 12000000)]
        [int]$BaudRate = 9600,

        [Parameter(Mandatory = $false)]
        [ValidateSet(7, 8)]
        [int]$DataBits = 8,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1, 2)]
        [int]$StopBits = 1,

        [Parameter(Mandatory = $false)]
        [ValidateSet('None', 'Odd', 'Even', 'Mark', 'Space')]
        [string]$Parity = 'None',

        [Parameter(Mandatory = $false)]
        [ValidateSet('None', 'RtsCts', 'DtrDsr', 'XonXoff')]
        [string]$FlowControl = 'None',

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 60000)]
        [int]$ReadTimeout = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 60000)]
        [int]$WriteTimeout = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 60000)]
        [int]$LineTimeout = 2000,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65536)]
        [int]$MaxLineLength = 1024
    )

    if (-not $PSBoundParameters.ContainsKey('Data') -and
        -not $PSBoundParameters.ContainsKey('ReadCount') -and
        -not $ReadLine) {
        throw "At least one of -Data, -ReadCount, or -ReadLine must be specified."
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

        # --- get or create UART instance ---
        $uart = $ftdi.GetUart($BaudRate, $DataBits, $StopBits, $Parity, $FlowControl,
                              [uint32]$ReadTimeout, [uint32]$WriteTimeout)
        if (-not $uart.IsInitialized) {
            throw "UART initialization failed"
        }

        # --- write phase ---
        $hasData = $PSBoundParameters.ContainsKey('Data')
        if ($hasData) {
            if ($Data -is [string]) {
                if (-not $uart.Write([string]$Data)) {
                    throw "UART write failed"
                }
            } elseif ($Data -is [byte[]]) {
                if (-not $uart.Write([byte[]]$Data)) {
                    throw "UART write failed"
                }
            } else {
                # Try converting to byte array
                [byte[]]$byteData = $Data
                if (-not $uart.Write($byteData)) {
                    throw "UART write failed"
                }
            }
        }

        # --- read phase ---
        $hasReadCount = $PSBoundParameters.ContainsKey('ReadCount')

        if ($hasReadCount) {
            return $uart.Read($ReadCount)
        } elseif ($ReadLine) {
            return $uart.ReadLine($MaxLineLength, $LineTimeout)
        } elseif ($hasData) {
            # write-only: return success bool already confirmed above
            return $true
        }

    } finally {
        if ($ownsDevice -and $ftdi -and $ftdi.IsOpen) {
            $ftdi.Close()
        }
    }
}
