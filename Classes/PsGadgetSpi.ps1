#Requires -Version 5.1
# Classes/PsGadgetSpi.ps1
# SPI device handle returned by PsGadgetFtdi.GetSpi().
# Wraps an FTDI connection for MPSSE SPI transactions and exposes
# Write(), Read(), and Transfer() methods backed by Ftdi.Spi.ps1.
#
# Obtain via:
#   $spi = $dev.GetSpi()                          # 1 MHz, Mode 0, CS=ADBUS3
#   $spi = $dev.GetSpi(10000000)                  # 10 MHz, Mode 0, CS=ADBUS3
#   $spi = $dev.GetSpi(5000000, 3, 3)             # 5 MHz, Mode 3, CS=ADBUS3

class PsGadgetSpi {
    [PsGadgetLogger]$Logger
    [System.Object]$FtdiDevice
    [int]$ClockHz
    [int]$SpiMode      # 0-3 (CPOL/CPHA)
    [int]$CsPin        # ADBUS pin number for CS (3-7)
    [bool]$IsInitialized

    PsGadgetSpi([System.Object]$ftdiConnection, [int]$clockHz, [int]$spiMode, [int]$csPin) {
        $this.Logger         = Get-PsGadgetModuleLogger
        $this.FtdiDevice     = $ftdiConnection
        $this.ClockHz        = $clockHz
        $this.SpiMode        = $spiMode
        $this.CsPin          = $csPin
        $this.IsInitialized  = $false
        $this.Logger.WriteInfo("PsGadgetSpi created: clock=${clockHz}Hz  mode=${spiMode}  CS=ADBUS${csPin}")
    }

    [bool] Initialize() {
        return $this.Initialize($false)
    }

    [bool] Initialize([bool]$force) {
        if ($this.IsInitialized -and -not $force) {
            $this.Logger.WriteInfo("SPI already initialized")
            return $true
        }
        if (-not $this.FtdiDevice) {
            $this.Logger.WriteError("No FTDI device assigned to SPI instance")
            return $false
        }
        $result = Initialize-MpsseSpi `
            -DeviceHandle    $this.FtdiDevice `
            -ClockFrequency  $this.ClockHz    `
            -SpiMode         $this.SpiMode    `
            -CsPin           $this.CsPin
        if ($result) {
            $this.IsInitialized = $true
            $this.Logger.WriteInfo("SPI initialized: clock=$($this.ClockHz)Hz  mode=$($this.SpiMode)  CS=ADBUS$($this.CsPin)")
        } else {
            $this.Logger.WriteError("SPI initialization failed")
        }
        return $result
    }

    # Write bytes to SPI device. CS is asserted for the entire payload.
    [bool] Write([byte[]]$data) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SPI not initialized. Call Initialize() first.")
            return $false
        }
        return (Invoke-MpsseSpiWrite `
            -DeviceHandle $this.FtdiDevice `
            -Data         $data            `
            -SpiMode      $this.SpiMode    `
            -CsPin        $this.CsPin)
    }

    # Read N bytes from SPI device. MOSI stays LOW during the read.
    [byte[]] Read([int]$count) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SPI not initialized. Call Initialize() first.")
            return [byte[]]@()
        }
        return (Invoke-MpsseSpiRead `
            -DeviceHandle $this.FtdiDevice `
            -Count        $count           `
            -SpiMode      $this.SpiMode    `
            -CsPin        $this.CsPin)
    }

    # Full-duplex transfer: write Data bytes while simultaneously clocking in the same count.
    # Returns the bytes received from MISO. Use this for ADC reads, register reads with dummy
    # write, and any device that requires MOSI activity during readback.
    [byte[]] Transfer([byte[]]$data) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SPI not initialized. Call Initialize() first.")
            return [byte[]]@()
        }
        return (Invoke-MpsseSpiTransfer `
            -DeviceHandle $this.FtdiDevice `
            -Data         $data            `
            -SpiMode      $this.SpiMode    `
            -CsPin        $this.CsPin)
    }
}
