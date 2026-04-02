#Requires -Version 5.1
# Classes/PsGadgetUart.ps1
# UART device handle returned by PsGadgetFtdi.GetUart().
# Wraps an FTDI connection for D2XX UART transactions and exposes
# Write(), Read(), ReadLine(), and Flush() methods backed by Ftdi.Uart.ps1.
#
# Obtain via:
#   $uart = $dev.GetUart()                              # 9600 8N1, no flow
#   $uart = $dev.GetUart(115200)                        # 115200 8N1, no flow
#   $uart = $dev.GetUart(115200, 8, 1, 'None')          # full control
#
# Typical usage:
#   $uart = $dev.GetUart(9600)
#   $uart.Write("AT`r`n")                               # string overload
#   $line = $uart.ReadLine()                            # read until \n
#   $bytes = $uart.Read(4)                              # read 4 raw bytes

class PsGadgetUart {
    [PsGadgetLogger]$Logger
    [System.Object]$FtdiDevice
    [int]$BaudRate
    [int]$DataBits
    [int]$StopBits
    [string]$Parity
    [string]$FlowControl
    [uint32]$ReadTimeout
    [uint32]$WriteTimeout
    [bool]$IsInitialized

    PsGadgetUart(
        [System.Object]$ftdiConnection,
        [int]$baudRate,
        [int]$dataBits,
        [int]$stopBits,
        [string]$parity,
        [string]$flowControl,
        [uint32]$readTimeout,
        [uint32]$writeTimeout
    ) {
        $this.Logger        = Get-PsGadgetModuleLogger
        $this.FtdiDevice    = $ftdiConnection
        $this.BaudRate      = $baudRate
        $this.DataBits      = $dataBits
        $this.StopBits      = $stopBits
        $this.Parity        = $parity
        $this.FlowControl   = $flowControl
        $this.ReadTimeout   = $readTimeout
        $this.WriteTimeout  = $writeTimeout
        $this.IsInitialized = $false

        $parityChar = @{ None='N'; Odd='O'; Even='E'; Mark='M'; Space='S' }[$parity]
        $this.Logger.WriteInfo(
            "PsGadgetUart created: baud=${baudRate}  ${dataBits}${parityChar}${stopBits}  flow=${flowControl}")
    }

    [bool] Initialize() {
        return $this.Initialize($false)
    }

    [bool] Initialize([bool]$force) {
        if ($this.IsInitialized -and -not $force) {
            $this.Logger.WriteInfo("UART already initialized")
            return $true
        }
        if (-not $this.FtdiDevice) {
            $this.Logger.WriteError("No FTDI device assigned to UART instance")
            return $false
        }
        $result = Initialize-FtdiUart `
            -DeviceHandle  $this.FtdiDevice   `
            -BaudRate      $this.BaudRate      `
            -DataBits      $this.DataBits      `
            -StopBits      $this.StopBits      `
            -Parity        $this.Parity        `
            -FlowControl   $this.FlowControl   `
            -ReadTimeout   $this.ReadTimeout   `
            -WriteTimeout  $this.WriteTimeout
        if ($result) {
            $this.IsInitialized = $true
            $this.Logger.WriteInfo("UART initialized: baud=$($this.BaudRate)")
        } else {
            $this.Logger.WriteError("UART initialization failed")
        }
        return $result
    }

    # Write raw bytes to UART TX.
    [bool] Write([byte[]]$data) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("UART not initialized. Call Initialize() first.")
            return $false
        }
        return (Invoke-FtdiUartWrite -DeviceHandle $this.FtdiDevice -Data $data)
    }

    # Write a string to UART TX (UTF-8 encoded). Line endings are the caller's responsibility.
    # Use "AT`r`n" to send CR+LF, or just "AT`n" for LF-only devices.
    [bool] Write([string]$text) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("UART not initialized. Call Initialize() first.")
            return $false
        }
        [byte[]]$encoded = [System.Text.Encoding]::UTF8.GetBytes($text)
        return (Invoke-FtdiUartWrite -DeviceHandle $this.FtdiDevice -Data $encoded)
    }

    # Read Count raw bytes from UART RX. Waits up to ReadTimeout milliseconds.
    [byte[]] Read([int]$count) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("UART not initialized. Call Initialize() first.")
            return [byte[]]@()
        }
        return (Invoke-FtdiUartRead -DeviceHandle $this.FtdiDevice -Count $count)
    }

    # Read bytes until a newline (\n) arrives or TimeoutMs elapses.
    # Returns the line as a UTF-8 string (\r stripped, \n not included).
    # Returns $null when no newline was received within the timeout (distinguishable
    # from a device that sent a bare \n, which returns "").
    [object] ReadLine() {
        return $this.ReadLine(1024, 2000)
    }

    [object] ReadLine([int]$maxLength) {
        return $this.ReadLine($maxLength, 2000)
    }

    [object] ReadLine([int]$maxLength, [int]$timeoutMs) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("UART not initialized. Call Initialize() first.")
            return $null
        }
        return (Invoke-FtdiUartReadLine `
            -DeviceHandle $this.FtdiDevice `
            -MaxLength    $maxLength       `
            -TimeoutMs    $timeoutMs)
    }

    # Return the number of bytes currently waiting in the RX buffer.
    [uint32] BytesAvailable() {
        if (-not $this.FtdiDevice) { return [uint32]0 }
        return (Get-FtdiUartBytesAvailable -DeviceHandle $this.FtdiDevice)
    }

    # Purge TX and RX buffers.
    [void] Flush() {
        if (-not $this.FtdiDevice) { return }
        $rawDevice = Get-FtdiD2xxHandle -DeviceHandle $this.FtdiDevice
        if ($rawDevice) {
            $rawDevice.Purge(3) | Out-Null
            $this.Logger.WriteProto('UART.FLUSH', 'TX+RX purged')
        }
    }
}
