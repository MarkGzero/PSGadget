#Requires -Version 5.1
# Ftdi.Spi.ps1
# MPSSE SPI backend for FT232H.
#
# ADBUS pin assignment (fixed by FTDI MPSSE hardware):
#   bit 0 = ADBUS0 = SCK   (clock output)
#   bit 1 = ADBUS1 = MOSI  (data output, Master Out Slave In)
#   bit 2 = ADBUS2 = MISO  (data input,  Master In Slave Out)
#   bit 3 = ADBUS3 = CS0   (default chip-select, active low)
#   bit 4-7          optional additional CS pins
#
# Wire guide:
#   FT232H D0 -> SCK    FT232H D1 -> MOSI
#   FT232H D2 -> MISO   FT232H D3 -> CS (with 10k pull-up to VCC)
#
# SPI mode table:
#   Mode 0 (CPOL=0 CPHA=0) — most common. Clock idle LOW, sample rising edge.
#   Mode 1 (CPOL=0 CPHA=1) — Clock idle LOW, sample falling edge.
#   Mode 2 (CPOL=1 CPHA=0) — Clock idle HIGH, sample falling edge.
#   Mode 3 (CPOL=1 CPHA=1) — Clock idle HIGH, sample rising edge.
#
# MPSSE command mapping:
#   CPHA=0: write 0x11 (out -ve edge), read 0x20 (in +ve edge), xfer 0x31
#   CPHA=1: write 0x10 (out +ve edge), read 0x24 (in -ve edge), xfer 0x34
#   CPOL sets CLK idle level in the ADBUS state byte only (bit0 of value byte).

function Initialize-MpsseSpi {
    <#
    .SYNOPSIS
    Initializes FTDI device for SPI communication via MPSSE.

    .PARAMETER DeviceHandle
    Open connection object from Connect-PsGadgetFtdi.

    .PARAMETER ClockFrequency
    SPI clock in Hz. Default 1 MHz. Max 30 MHz.

    .PARAMETER SpiMode
    SPI mode 0-3 (CPOL/CPHA). Default 0.

    .PARAMETER CsPin
    ADBUS pin number for chip select (active low). Default 3.
    Must be 3-7 to avoid conflict with SCK(0), MOSI(1), MISO(2).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$DeviceHandle,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1000, 30000000)]
        [int]$ClockFrequency = 1000000,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3)]
        [int]$SpiMode = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(3, 7)]
        [int]$CsPin = 3
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        # CPOL = bit 1 of SpiMode;  CPHA = bit 0 of SpiMode
        $cpol = ($SpiMode -band 2) -ne 0
        $cpha = ($SpiMode -band 1) -ne 0

        # ADBUS direction mask: CLK(0)+MOSI(1)+CS(CsPin) = output; MISO(2) = input
        $csBit   = [byte](1 -shl $CsPin)
        $dirMask = [byte](0x03 -bor $csBit)

        # Clock idle state: CS deasserted (high), CLK at CPOL level, MOSI=0
        $clkIdle = [byte](if ($cpol) { 0x01 } else { 0x00 })
        $csHigh  = [byte]($csBit -bor $clkIdle)   # CS deasserted + CLK at idle

        # SPI clock divisor (no 3-phase — that is I2C-only):
        #   f = 60 MHz / ((1 + divisor) * 2)   [with divide-by-5 disabled]
        #   divisor = 60 MHz / (2 * f) - 1
        $divisor   = [int][Math]::Floor(60000000 / (2.0 * [double]$ClockFrequency) - 1)
        $divisor   = [Math]::Max(0, [Math]::Min(65535, $divisor))
        $divisorLo = [byte]($divisor -band 0xFF)
        $divisorHi = [byte](($divisor -shr 8) -band 0xFF)

        if ($isReal) {
            # Low latency timer for SPI (1 ms vs default 16 ms)
            $rawDevice.SetLatency(1) | Out-Null

            $writeCmd = {
                param([byte[]]$cmd, [string]$label)
                [uint32]$bw = 0
                $st = $rawDevice.Write($cmd, [uint32]$cmd.Length, [ref]$bw)
                if ([int]$st -ne 0) { throw "$label failed: status=$st" }
            }

            $rawDevice.Purge(3) | Out-Null
            Start-Sleep -Milliseconds 30

            # MPSSE synchronization handshake (same pattern as GPIO/I2C init)
            [uint32]$sw = 0
            $rawDevice.Write([byte[]](0xAA), 1, [ref]$sw) | Out-Null
            Start-Sleep -Milliseconds 30
            [byte[]]$sb = [byte[]]::new(2); [uint32]$sr = 0
            $rawDevice.Read($sb, 2, [ref]$sr) | Out-Null
            if ($sr -ne 2 -or $sb[0] -ne 0xFA -or $sb[1] -ne 0xAA) {
                throw ("MPSSE SPI sync failed (0xAA): got {0} bytes: 0x{1:X2} 0x{2:X2}" -f $sr, $sb[0], $sb[1])
            }
            $rawDevice.Write([byte[]](0xAB), 1, [ref]$sw) | Out-Null
            Start-Sleep -Milliseconds 30
            $rawDevice.Read($sb, 2, [ref]$sr) | Out-Null
            if ($sr -ne 2 -or $sb[0] -ne 0xFA -or $sb[1] -ne 0xAB) {
                throw ("MPSSE SPI sync failed (0xAB): got {0} bytes: 0x{1:X2} 0x{2:X2}" -f $sr, $sb[0], $sb[1])
            }

            # SPI MPSSE configuration:
            #   0x8A  Disable clock divide-by-5 (60 MHz base)
            #   0x97  Disable adaptive clocking
            #   (no 0x8C 3-phase — I2C only)
            #   (no 0x9E drive-zero — I2C open-drain only)
            #   0x86  Set clock divisor (lo, hi)
            #   0x85  Loopback off
            #   0x80  Set ADBUS: CS=1 (idle), CLK=CPOL, MOSI=0
            [byte[]]$spiCfg = @(
                0x8A,
                0x97,
                0x86, $divisorLo, $divisorHi,
                0x85,
                0x80, $csHigh, $dirMask
            )
            & $writeCmd $spiCfg 'SPI config'
            Start-Sleep -Milliseconds 30

            $hexStr = ($spiCfg | ForEach-Object { $_.ToString('X2') }) -join ' '
            $script:PsGadgetLogger.WriteProto('SPI.INIT',
                "clock=${ClockFrequency}Hz  divisor=${divisor}  mode=${SpiMode}  CS=ADBUS${CsPin}",
                $hexStr)
            Write-Verbose "MPSSE SPI initialized: clock=$ClockFrequency Hz, mode=$SpiMode, CS=ADBUS$CsPin (divisor=$divisor)"
        } else {
            $script:PsGadgetLogger.WriteProto('SPI.INIT',
                "clock=${ClockFrequency}Hz  mode=${SpiMode}  CS=ADBUS${CsPin}  (STUB)")
            Write-Verbose "MPSSE SPI initialized (STUB MODE)"
        }

        # Cache SPI config on connection object so transfer functions can retrieve it
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'SpiClockHz' -Value $ClockFrequency -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'SpiMode'    -Value $SpiMode        -Force
        $DeviceHandle | Add-Member -MemberType NoteProperty -Name 'SpiCsPin'   -Value $CsPin          -Force
        return $true

    } catch {
        Write-Error "Failed to initialize MPSSE SPI: $_"
        return $false
    }
}

function Invoke-MpsseSpiWrite {
    <#
    .SYNOPSIS
    Writes bytes to a SPI device via MPSSE (write-only, no data returned).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]  [System.Object]$DeviceHandle,
        [Parameter(Mandatory = $true)]  [byte[]]$Data,
        [Parameter(Mandatory = $false)] [ValidateRange(0, 3)] [int]$SpiMode = 0,
        [Parameter(Mandatory = $false)] [ValidateRange(3, 7)] [int]$CsPin   = 3
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }
        if ($Data.Length -eq 0) { return $true }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        $cpol      = ($SpiMode -band 2) -ne 0
        $cpha      = ($SpiMode -band 1) -ne 0
        $csBit     = [byte](1 -shl $CsPin)
        $dirMask   = [byte](0x03 -bor $csBit)
        $clkIdle   = [byte](if ($cpol) { 0x01 } else { 0x00 })
        $csHigh    = [byte]($csBit -bor $clkIdle)
        $csLow     = $clkIdle   # CS asserted (low), CLK stays at idle level

        # CPHA=0 -> write on -ve/falling edge (0x11); CPHA=1 -> write on +ve/rising edge (0x10)
        $writeCmdByte = if ($cpha) { [byte]0x10 } else { [byte]0x11 }

        $lenMinus1 = [uint16]($Data.Length - 1)
        $lenLo     = [byte]($lenMinus1 -band 0xFF)
        $lenHi     = [byte](($lenMinus1 -shr 8) -band 0xFF)

        # Full transaction: CS assert + data write + CS deassert
        $buf = [System.Collections.Generic.List[byte]]::new()
        $buf.AddRange([byte[]](0x80, $csLow,  $dirMask))          # CS assert (low)
        $buf.Add($writeCmdByte); $buf.Add($lenLo); $buf.Add($lenHi)
        $buf.AddRange($Data)
        $buf.AddRange([byte[]](0x80, $csHigh, $dirMask))          # CS deassert (high)
        [byte[]]$txBuf = $buf.ToArray()

        $hexStr = $script:PsGadgetLogger.FormatHex($Data)

        if ($isReal) {
            [uint32]$bw = 0
            $st = $rawDevice.Write($txBuf, [uint32]$txBuf.Length, [ref]$bw)
            if ([int]$st -ne 0) { throw "SPI write failed: D2XX status=$st" }
            $script:PsGadgetLogger.WriteProto('SPI.WRITE',
                "$($Data.Length)B  mode=$SpiMode  CS=ADBUS$CsPin",
                $hexStr)
        } else {
            $script:PsGadgetLogger.WriteProto('SPI.WRITE',
                "$($Data.Length)B  mode=$SpiMode  CS=ADBUS$CsPin  (STUB)",
                $hexStr)
        }
        return $true

    } catch {
        Write-Error "SPI write failed: $_"
        return $false
    }
}

function Invoke-MpsseSpiRead {
    <#
    .SYNOPSIS
    Reads bytes from a SPI device via MPSSE (MOSI stays low during read).
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]  [System.Object]$DeviceHandle,
        [Parameter(Mandatory = $true)]  [ValidateRange(1, 65536)] [int]$Count,
        [Parameter(Mandatory = $false)] [ValidateRange(0, 3)] [int]$SpiMode = 0,
        [Parameter(Mandatory = $false)] [ValidateRange(3, 7)] [int]$CsPin   = 3
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        $cpol     = ($SpiMode -band 2) -ne 0
        $cpha     = ($SpiMode -band 1) -ne 0
        $csBit    = [byte](1 -shl $CsPin)
        $dirMask  = [byte](0x03 -bor $csBit)
        $clkIdle  = [byte](if ($cpol) { 0x01 } else { 0x00 })
        $csHigh   = [byte]($csBit -bor $clkIdle)
        $csLow    = $clkIdle

        # CPHA=0 -> read on +ve/rising edge (0x20); CPHA=1 -> read on -ve/falling edge (0x24)
        $readCmdByte = if ($cpha) { [byte]0x24 } else { [byte]0x20 }

        $lenMinus1 = [uint16]($Count - 1)
        $lenLo     = [byte]($lenMinus1 -band 0xFF)
        $lenHi     = [byte](($lenMinus1 -shr 8) -band 0xFF)

        # CS assert + read command + SEND_IMMEDIATE + CS deassert
        $buf = [System.Collections.Generic.List[byte]]::new()
        $buf.AddRange([byte[]](0x80, $csLow, $dirMask))           # CS assert
        $buf.Add($readCmdByte); $buf.Add($lenLo); $buf.Add($lenHi)
        $buf.Add(0x87)                                             # SEND_IMMEDIATE: flush to host
        $buf.AddRange([byte[]](0x80, $csHigh, $dirMask))          # CS deassert
        [byte[]]$txBuf = $buf.ToArray()

        if ($isReal) {
            [uint32]$bw = 0
            $st = $rawDevice.Write($txBuf, [uint32]$txBuf.Length, [ref]$bw)
            if ([int]$st -ne 0) { throw "SPI read command failed: D2XX status=$st" }

            [byte[]]$rxBuf = [byte[]]::new($Count)
            [uint32]$br    = 0
            $st = $rawDevice.Read($rxBuf, [uint32]$Count, [ref]$br)
            if ([int]$st -ne 0) { throw "SPI read data failed: D2XX status=$st" }

            if ($br -lt $Count) {
                $trimmed = [byte[]]::new($br)
                [Array]::Copy($rxBuf, $trimmed, [int]$br)
                $rxBuf = $trimmed
            }

            $hexStr = $script:PsGadgetLogger.FormatHex($rxBuf)
            $script:PsGadgetLogger.WriteProto('SPI.READ',
                "$br/$Count B  mode=$SpiMode  CS=ADBUS$CsPin",
                $hexStr)
            return $rxBuf
        } else {
            [byte[]]$stub = [byte[]]::new($Count)
            $script:PsGadgetLogger.WriteProto('SPI.READ',
                "${Count}B  mode=$SpiMode  CS=ADBUS$CsPin  (STUB)")
            return $stub
        }

    } catch {
        Write-Error "SPI read failed: $_"
        return [byte[]]@()
    }
}

function Invoke-MpsseSpiTransfer {
    <#
    .SYNOPSIS
    Full-duplex SPI transfer: writes Data bytes and simultaneously reads the same count.
    MOSI and MISO are active for the entire transaction length.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]  [System.Object]$DeviceHandle,
        [Parameter(Mandatory = $true)]  [byte[]]$Data,
        [Parameter(Mandatory = $false)] [ValidateRange(0, 3)] [int]$SpiMode = 0,
        [Parameter(Mandatory = $false)] [ValidateRange(3, 7)] [int]$CsPin   = 3
    )

    try {
        if (-not $DeviceHandle -or -not $DeviceHandle.IsOpen) {
            throw "Device handle is invalid or not open"
        }
        if ($Data.Length -eq 0) { return [byte[]]@() }

        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $DeviceHandle
        $isReal    = $script:FtdiInitialized -and ($null -ne $rawDevice)

        $cpol     = ($SpiMode -band 2) -ne 0
        $cpha     = ($SpiMode -band 1) -ne 0
        $csBit    = [byte](1 -shl $CsPin)
        $dirMask  = [byte](0x03 -bor $csBit)
        $clkIdle  = [byte](if ($cpol) { 0x01 } else { 0x00 })
        $csHigh   = [byte]($csBit -bor $clkIdle)
        $csLow    = $clkIdle

        # CPHA=0: write on -ve, read on +ve -> 0x31
        # CPHA=1: write on +ve, read on -ve -> 0x34
        $xferCmd  = if ($cpha) { [byte]0x34 } else { [byte]0x31 }

        $lenMinus1 = [uint16]($Data.Length - 1)
        $lenLo     = [byte]($lenMinus1 -band 0xFF)
        $lenHi     = [byte](($lenMinus1 -shr 8) -band 0xFF)

        # CS assert + full-duplex shift + SEND_IMMEDIATE + CS deassert
        $buf = [System.Collections.Generic.List[byte]]::new()
        $buf.AddRange([byte[]](0x80, $csLow, $dirMask))
        $buf.Add($xferCmd); $buf.Add($lenLo); $buf.Add($lenHi)
        $buf.AddRange($Data)
        $buf.Add(0x87)
        $buf.AddRange([byte[]](0x80, $csHigh, $dirMask))
        [byte[]]$txBuf = $buf.ToArray()

        $txHex = $script:PsGadgetLogger.FormatHex($Data)

        if ($isReal) {
            [uint32]$bw = 0
            $st = $rawDevice.Write($txBuf, [uint32]$txBuf.Length, [ref]$bw)
            if ([int]$st -ne 0) { throw "SPI transfer write failed: D2XX status=$st" }

            [byte[]]$rxBuf = [byte[]]::new($Data.Length)
            [uint32]$br    = 0
            $st = $rawDevice.Read($rxBuf, [uint32]$Data.Length, [ref]$br)
            if ([int]$st -ne 0) { throw "SPI transfer read failed: D2XX status=$st" }

            if ($br -lt $Data.Length) {
                $trimmed = [byte[]]::new($br)
                [Array]::Copy($rxBuf, $trimmed, [int]$br)
                $rxBuf = $trimmed
            }

            $rxHex = $script:PsGadgetLogger.FormatHex($rxBuf)
            $script:PsGadgetLogger.WriteProto('SPI.XFER',
                "TX=$($Data.Length)B  RX=${br}B  mode=$SpiMode  CS=ADBUS$CsPin",
                "TX: $txHex  ->  RX: $rxHex")
            return $rxBuf
        } else {
            [byte[]]$stub = [byte[]]::new($Data.Length)
            $script:PsGadgetLogger.WriteProto('SPI.XFER',
                "TX=$($Data.Length)B  RX=$($Data.Length)B  mode=$SpiMode  CS=ADBUS$CsPin  (STUB)")
            return $stub
        }

    } catch {
        Write-Error "SPI transfer failed: $_"
        return [byte[]]@()
    }
}
