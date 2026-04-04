#Requires -Version 5.1
function Get-PsGadgetGpio {
    <#
    .SYNOPSIS
    Reads the current logic level of GPIO pins on a connected FTDI device.

    .DESCRIPTION
    Reads the instantaneous pin state for CBUS (FT232R) or ACBUS (FT232H) GPIO
    pins. Returns a byte representing all pin states, or a bool[] when -Pins is
    specified.

    For FT232R CBUS:  bits 0-3 of the returned byte = CBUS0-CBUS3 levels.
    For FT232H MPSSE: bits 0-7 of the returned byte = ACBUS0-ACBUS7 levels.

    A 1 bit = HIGH (3.3 V), 0 bit = LOW (GND). Input and output pin levels are
    both readable; the value reflects the actual logic level on the pin.

    .PARAMETER Connection
    An already-open raw connection object (e.g. from Connect-PsGadgetFtdi).
    The caller is responsible for closing the connection.

    .PARAMETER Pins
    Optional. One or more pin numbers to read. When specified, returns a bool[]
    in the same order as Pins (true = HIGH). When omitted, returns the raw byte.

    .EXAMPLE
    # Read all CBUS pin states as a byte
    $ft.SetPins(@(3), $true)          # CBUS3=output HIGH; CBUS0-2 become inputs
    $byte = Get-PsGadgetGpio -Connection $conn
    $sensorHigh = [bool]($byte -band 0x01)   # check CBUS0

    .EXAMPLE
    # Read a single pin as bool (via class method)
    $triggered = $ft.ReadPin(0)

    .EXAMPLE
    # Read multiple pins
    $states = Get-PsGadgetGpio -Connection $conn -Pins @(0, 2)
    if ($states[0]) { Write-Host "Pin 0 is HIGH" }

    .NOTES
    Requires FTDI D2XX drivers and FTD2XX_NET.dll.
    For FT232R: Set-PsGadgetGpio must have been called at least once to put the
    device in CBUS bit-bang mode before reads will return valid data.
    For FT232H: reads the ACBUS state via MPSSE command 0x83.
    Stub mode returns 0x00 (all pins LOW) when hardware is unavailable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$Connection,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 7)]
        [int[]]$Pins
    )

    try {
        if (-not $Connection -or -not $Connection.IsOpen) {
            throw "Connection is not open"
        }

        $gpioMethod = $Connection.GpioMethod
        [byte]$rawByte = 0

        switch ($gpioMethod) {
            'CBUS'  { $rawByte = Get-FtdiCbusBits -Connection $Connection }
            'MPSSE' { $rawByte = Get-FtdiGpioPins -DeviceHandle $Connection -BypassCache }
            'IoT'   {
                if (-not $Connection.GpioController) {
                    Write-Warning ("Get-PsGadgetGpio: IoT connection is missing GpioController for device '{0}'" -f $Connection.Type)
                    break
                }
                $rawByte = Get-FtdiIotGpioPins -GpioController $Connection.GpioController
            }
            default {
                Write-Warning ("Get-PsGadgetGpio: unsupported GpioMethod '{0}' for device '{1}'" -f $gpioMethod, $Connection.Type)
            }
        }

        if ($Pins) {
            $result = [bool[]]::new($Pins.Length)
            for ($i = 0; $i -lt $Pins.Length; $i++) {
                $result[$i] = [bool](($rawByte -band (1 -shl $Pins[$i])) -ne 0)
            }
            return $result
        }
        return $rawByte

    } catch {
        Write-Error "Get-PsGadgetGpio failed: $_"
    }
}
