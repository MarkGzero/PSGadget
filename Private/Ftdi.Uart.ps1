#Requires -Version 5.1
# Ftdi.Uart.ps1
# D2XX UART backend for FTDI FT232R, FT232H, and compatible devices.
#
# All FTDI chips support UART (serial) as their default mode (SetBitMode 0x00).
# This backend configures baud rate, data format, and flow control via the D2XX
# API, then provides Write/Read/ReadLine helpers with [PROTO] tracing.
#
# Parity map:    None=0  Odd=1  Even=2  Mark=3  Space=4
# Stop bits map: 1 stop bit=0  2 stop bits=2   (FTD2XX_NET byte values)
# Flow control:  None=0x0000  RtsCts=0x0100  DtrDsr=0x0200  XonXoff=0x0400
#
# Wire guide (FT232R as USB-UART adapter):
#   TX (pin 1 / ADBUS0) -> RX of target device
#   RX (pin 5 / ADBUS1) <- TX of target device
#   GND -> common ground

function Initialize-FtdiUart {
    <#
    .SYNOPSIS
    Configures an FTDI device for UART (serial) communication via D2XX.

    .PARAMETER DeviceHandle
    Open connection object from Connect-PsGadgetFtdi / PsGadgetFtdi._connection.

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
    Read timeout in milliseconds. 0 = non-blocking, 4294967295 = infinite. Default 500.

    .PARAMETER WriteTimeout
    Write timeout in milliseconds. Default 500.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle,

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
        [ValidateRange(0, 4294967295)]
        [uint32]$ReadTimeout = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 4294967295)]
        [uint32]$WriteTimeout = 500
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        # D2XX numeric values
        $parityMap = @{ None=0; Odd=1; Even=2; Mark=3; Space=4 }
        $stopMap   = @{ 1=0; 2=2 }   # FT_STOP_BITS_1=0, FT_STOP_BITS_2=2
        $flowMap   = @{ None=0x0000; RtsCts=0x0100; DtrDsr=0x0200; XonXoff=0x0400 }

        $parityByte   = [byte]$parityMap[$Parity]
        $stopByte     = [byte]$stopMap[$StopBits]
        $flowWord     = [uint16]$flowMap[$FlowControl]

        # Human-readable format string e.g. "8N1", "7E2"
        $parityChar = @{ None='N'; Odd='O'; Even='E'; Mark='M'; Space='S' }[$Parity]
        $formatStr  = "${DataBits}${parityChar}${StopBits}"

        if ($isReal) {
            $ftdi_ok = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK

            $st = $rawDevice.SetBaudRate([uint32]$BaudRate)
            if ($st -ne $ftdi_ok) { throw "SetBaudRate failed: status=$st" }

            $st = $rawDevice.SetDataCharacteristics([byte]$DataBits, $stopByte, $parityByte)
            if ($st -ne $ftdi_ok) { throw "SetDataCharacteristics failed: status=$st" }

            $st = $rawDevice.SetFlowControl($flowWord, [byte]0x11, [byte]0x13)
            if ($st -ne $ftdi_ok) { throw "SetFlowControl failed: status=$st" }

            $st = $rawDevice.SetTimeouts($ReadTimeout, $WriteTimeout)
            if ($st -ne $ftdi_ok) { throw "SetTimeouts failed: status=$st" }

            $rawDevice.Purge(3) | Out-Null   # purge RX+TX

            $script:PsGadgetLogger.WriteProto('UART.INIT',
                "baud=${BaudRate}  ${formatStr}  flow=${FlowControl}  rto=${ReadTimeout}ms  wto=${WriteTimeout}ms")
            Write-Verbose "UART initialized: ${BaudRate} ${formatStr} flow=${FlowControl}"
        } else {
            $script:PsGadgetLogger.WriteProto('UART.INIT',
                "baud=${BaudRate}  ${formatStr}  flow=${FlowControl}  (STUB)")
            Write-Verbose "UART initialized (STUB MODE)"
        }

        # Cache UART config on connection object
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'UartBaudRate'    -Value $BaudRate     -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'UartDataBits'    -Value $DataBits     -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'UartStopBits'    -Value $StopBits     -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'UartParity'      -Value $Parity       -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'UartFlowControl' -Value $FlowControl  -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'UartReadTimeout' -Value $ReadTimeout  -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'UartWriteTimeout'-Value $WriteTimeout -Force
        return $true

    } catch {
        Write-Error "Failed to initialize UART: $_"
        return $false
    }
}

function Invoke-FtdiUartWrite {
    <#
    .SYNOPSIS
    Writes bytes to the UART TX line via D2XX.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]  [System.Object]$DeviceHandle,
        [Parameter(Mandatory = $true)]  [byte[]]$Data
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }
        if ($Data.Length -eq 0) { return $true }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        $hexStr = $script:PsGadgetLogger.FormatHex($Data)

        # Attempt ASCII decode for summary (printable chars only)
        $summary = "$($Data.Length)B"
        $ascii = [System.Text.Encoding]::ASCII.GetString($Data)
        $isPrintable = ($ascii -cmatch '^[\x20-\x7E\r\n\t]+$')
        if ($isPrintable) {
            $escaped = $ascii -replace '\r','\\r' -replace '\n','\\n' -replace '\t','\\t'
            $summary += "  `"$escaped`""
        }

        if ($isReal) {
            [uint32]$bw = 0
            $st = $rawDevice.Write($Data, [uint32]$Data.Length, [ref]$bw)
            $ftdi_ok = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK
            if ($st -ne $ftdi_ok) { throw "UART write failed: D2XX status=$st" }
            $script:PsGadgetLogger.WriteProto('UART.TX', $summary, $hexStr)
        } else {
            $script:PsGadgetLogger.WriteProto('UART.TX', "$summary  (STUB)", $hexStr)
        }
        return $true

    } catch {
        Write-Error "UART write failed: $_"
        return $false
    }
}

function Invoke-FtdiUartRead {
    <#
    .SYNOPSIS
    Reads up to Count bytes from the UART RX line via D2XX.
    Waits up to the configured read timeout for data to arrive.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]  [System.Object]$DeviceHandle,
        [Parameter(Mandatory = $true)]  [ValidateRange(1, 65536)] [int]$Count
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        if ($isReal) {
            [byte[]]$rxBuf = [byte[]]::new($Count)
            [uint32]$br    = 0
            $st = $rawDevice.Read($rxBuf, [uint32]$Count, [ref]$br)
            $ftdi_ok = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK
            if ($st -ne $ftdi_ok) { throw "UART read failed: D2XX status=$st" }

            if ($br -lt [uint32]$Count) {
                $trimmed = [byte[]]::new($br)
                if ($br -gt 0) { [Array]::Copy($rxBuf, $trimmed, [int]$br) }
                $rxBuf = $trimmed
            }

            $summary = "$br/${Count}B"
            if ($br -gt 0) {
                $hexStr = $script:PsGadgetLogger.FormatHex($rxBuf)
                $ascii = [System.Text.Encoding]::ASCII.GetString($rxBuf)
                $isPrintable = ($ascii -cmatch '^[\x20-\x7E\r\n\t]+$')
                if ($isPrintable) {
                    $escaped = $ascii -replace '\r','\\r' -replace '\n','\\n' -replace '\t','\\t'
                    $summary += "  `"$escaped`""
                }
                $script:PsGadgetLogger.WriteProto('UART.RX', $summary, $hexStr)
            } else {
                $script:PsGadgetLogger.WriteProto('UART.RX', "$summary  (timeout/empty)")
            }
            return $rxBuf
        } else {
            $script:PsGadgetLogger.WriteProto('UART.RX', "${Count}B  (STUB)")
            return [byte[]]::new($Count)
        }

    } catch {
        Write-Error "UART read failed: $_"
        return [byte[]]@()
    }
}

function Invoke-FtdiUartReadLine {
    <#
    .SYNOPSIS
    Reads bytes from UART until a newline (\n) is received or timeout elapses.
    Returns the line as a string (decoded UTF-8, newline stripped).

    .PARAMETER DeviceHandle
    Open connection object.

    .PARAMETER MaxLength
    Maximum line length in bytes before aborting. Default 1024.

    .PARAMETER TimeoutMs
    Maximum milliseconds to wait for a complete line. Default 2000.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]  [System.Object]$DeviceHandle,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 65536)] [int]$MaxLength  = 1024,
        [Parameter(Mandatory = $false)] [ValidateRange(0, 60000)] [int]$TimeoutMs  = 2000
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        if ($isReal) {
            $ftdi_ok  = [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK
            $deadline = [System.Diagnostics.Stopwatch]::StartNew()
            $lineBytes = [System.Collections.Generic.List[byte]]::new()
            [byte[]]$oneByte = [byte[]]::new(1)
            [bool]$gotNewline = $false

            while ($deadline.ElapsedMilliseconds -lt $TimeoutMs -and $lineBytes.Count -lt $MaxLength) {
                [uint32]$available = 0
                $rawDevice.GetRxBytesAvailable([ref]$available) | Out-Null
                if ($available -eq 0) {
                    Start-Sleep -Milliseconds 5
                    continue
                }
                [uint32]$br = 0
                $st = $rawDevice.Read($oneByte, 1, [ref]$br)
                if ($st -ne $ftdi_ok -or $br -eq 0) { break }
                $b = $oneByte[0]
                if ($b -eq 0x0A) { $gotNewline = $true; break }   # newline -- end of line
                if ($b -ne 0x0D) {            # strip \r, keep everything else
                    $lineBytes.Add($b)
                }
            }

            $deadline.Stop()
            [byte[]]$lineArr = $lineBytes.ToArray()
            $elapsed = $deadline.ElapsedMilliseconds

            if (-not $gotNewline) {
                # Timed out without receiving a newline. Return $null so callers can
                # distinguish timeout from a device that sent an empty line (bare \n).
                $script:PsGadgetLogger.WriteProto('UART.RX', "ReadLine  timeout=${elapsed}ms  (no newline received)")
                return $null
            }

            $line = [System.Text.Encoding]::UTF8.GetString($lineArr)
            $hexStr = $script:PsGadgetLogger.FormatHex($lineArr)
            $script:PsGadgetLogger.WriteProto('UART.RX',
                "$($lineArr.Length)B  line=${elapsed}ms  `"$($line -replace '"','\"')`"",
                $hexStr)
            return $line
        } else {
            $script:PsGadgetLogger.WriteProto('UART.RX', "ReadLine  (STUB)")
            return $null
        }

    } catch {
        Write-Error "UART ReadLine failed: $_"
        return $null
    }
}

function Get-FtdiUartBytesAvailable {
    <#
    .SYNOPSIS
    Returns the number of bytes waiting in the UART RX buffer.
    #>
    [CmdletBinding()]
    [OutputType([uint32])]
    param(
        [Parameter(Mandatory = $true)] [System.Object]$DeviceHandle
    )

    try {
        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        if (-not $rawDevice) { return [uint32]0 }

        [uint32]$available = 0
        $rawDevice.GetRxBytesAvailable([ref]$available) | Out-Null
        return $available
    } catch {
        return [uint32]0
    }
}
