#Requires -Version 5.1

function Invoke-PsGadgetStepper {
    <#
    .SYNOPSIS
    Drive a stepper motor connected to an FTDI device in a single command.

    .DESCRIPTION
    High-level stepper motor dispatch.  Supports two driver types selected by
    -DriverType:

    ULN2003 (default) — coil-sequence driver for unipolar motors (e.g. 28BYJ-48).
        Opens the FTDI device, switches to async bit-bang on ADBUS0-3, pre-computes
        the full coil sequence as a byte buffer, and issues a single USB write so
        the D2XX baud-rate timer paces each transition.  Supports FT232R and FT232H.

        Pin wiring (default):
            ADBUS0 (D0) -> IN1
            ADBUS1 (D1) -> IN2
            ADBUS2 (D2) -> IN3
            ADBUS3 (D3) -> IN4

        StepsPerRevolution default: ~4075.77 half-steps (28BYJ-48 empirical,
        NOT exactly 4096).  Calibrate and pass -StepsPerRevolution to override.

    TB6600 — step/direction driver for bipolar motors (e.g. NEMA 17/23, VEXTA).
        Uses MPSSE SET_BITS_HIGH (0x82) to toggle ACBUS/CBUS pins.  Requires
        FT232H in MPSSE or IoT mode.  The driver handles all phase sequencing;
        the host only pulses PUL+ once per step.

        Default pin wiring (ACBUS/CBUS on FT232H):
            CBUS0 (C0) -> PUL+    (pulse: rising edge = 1 step)
            CBUS1 (C1) -> DIR+    (direction: HIGH=forward)
            CBUS2 (C2) -> ENA+    (enable; omit with -NoEnable when looped/GND)
            CBUS4 (C4) -> Left limit switch  (input; LOW = triggered, active-low default)
            CBUS5 (C5) -> Right limit switch (input; LOW = triggered, active-low default)
        Override with -EnaPin / -DirPin / -PulPin / -LeftLimitPin / -RightLimitPin.

        StepsPerRevolution default: 200 (1.8-degree motor, full-step).
        Change to match your TB6600 microstep DIP setting, e.g. 400 for 1/2 step,
        800 for 1/4 step, 1600 for 1/8 step, 3200 for 1/16 step, 6400 for 1/32 step.

    .PARAMETER PsGadget
    An already-open PsGadgetFtdi object (from New-PsGadgetFtdi).
    When supplied the device is NOT closed after the call.

    .PARAMETER Index
    FTDI device index (0-based) from Get-FtdiDevice.  Default is 0.

    .PARAMETER SerialNumber
    FTDI device serial number (e.g. "FTAXBFCQ").
    Preferred over Index for stable identification across USB re-plugs.

    .PARAMETER Steps
    Number of individual step pulses to issue.
    Mutually exclusive with -Degrees.  Provide exactly one.

    .PARAMETER Degrees
    Rotate the output shaft by this many degrees.
    Converted to steps using StepsPerRevolution (calibrated or default).
    Mutually exclusive with -Steps.  Provide exactly one.

    .PARAMETER StepsPerRevolution
    Number of step pulses per full output-shaft revolution for the
    configured StepMode.  Default 0 = use built-in calibration value:
        Half mode: ~4075.77 (28BYJ-48 empirical, NOT exactly 4096)
        Full mode: ~2037.89 (half of above; each full-step moves twice as far)
    Supply your measured value to override.  Valid range: 100-100000.

    .PARAMETER Direction
    'Forward' (default) or 'Reverse'.

    .PARAMETER StepMode
    'Half' (default, smoother, higher resolution) or 'Full' (higher torque).
    Half-step is recommended for 28BYJ-48.

    .PARAMETER DelayMs
    Inter-step delay in milliseconds.  Controls baud rate timing.
    Minimum recommended for 28BYJ-48: 1 ms.  Default: 2 ms.
    Lower values increase speed but risk stall on slower geared motors.

    .PARAMETER PinMask
    Output direction mask byte for ADBUS pins.
    Default 0x0F = ADBUS0-3 all outputs (IN1-IN4 on ULN2003).

    .PARAMETER PinOffset
    Shift coil byte left by N bits.  Use when motor is wired on upper ADBUS pins.
    Default 0 (IN1=bit0 = ADBUS0).

    .PARAMETER AcBus
    (ULN2003 only) Target ACBUS (C-bank, pins C0-C7) instead of ADBUS (D-bank).
    Required when the stepper is wired to ACBUS C0-C3 on an FT232H that is
    also running I2C on ADBUS D0/D1 (e.g. combined stepper + SSD1306).
    Uses MPSSE SET_BITS_HIGH (0x82) instead of SET_BITS_LOW (0x80).

    .PARAMETER DriverType
    'ULN2003' (default) for coil-sequence unipolar drivers (28BYJ-48).
    'TB6600' for step/direction bipolar drivers (NEMA 17/23, VEXTA PK-series).

    .PARAMETER EnaPin
    (TB6600 only) ACBUS pin number for ENA+.  Default 2 (CBUS2).

    .PARAMETER DirPin
    (TB6600 only) ACBUS pin number for DIR+.  Default 1 (CBUS1).

    .PARAMETER PulPin
    (TB6600 only) ACBUS pin number for PUL+.  Default 0 (CBUS0).

    .PARAMETER PulseWidthUs
    (TB6600 only) PUL+ high-pulse width in microseconds.
    TB6600 minimum is 2.5 µs; default 5 µs gives a safe margin.

    .PARAMETER NoEnable
    (TB6600 only) Skip ENA pin control entirely.
    Use when ENA+/ENA- are looped together or ENA+ is tied to GND (always-enabled).

    .PARAMETER UseLimits
    (TB6600 only) Enable limit switch checking after each step pulse.
    When set, ACBUS pins LeftLimitPin and RightLimitPin are sampled.
    A Forward move stops when the right limit fires; a Reverse move stops on the left.
    Default polarity: LOW = triggered (active-low, typical for optical interruptors).
    Use -LimitActiveHigh for switches that pull the pin HIGH when triggered.

    .PARAMETER LimitActiveHigh
    (TB6600 only) Switch trigger polarity.  Default (not set) = active-low.
    Optical interruptors (photointerruptors) are active-low: beam broken -> LOW.
    Set this switch when your hardware pulls the pin HIGH when the limit is reached.

    .PARAMETER LeftLimitPin
    (TB6600 only) ACBUS pin for the left limit switch.  Default 4 (CBUS4).

    .PARAMETER RightLimitPin
    (TB6600 only) ACBUS pin for the right limit switch.  Default 5 (CBUS5).

    .EXAMPLE
    # Move forward 1000 half-steps (about 88 degrees)  [ULN2003]
    Invoke-PsGadgetStepper -Index 0 -Steps 1000

    .EXAMPLE
    # Rotate 90 degrees using calibrated StepsPerRevolution  [ULN2003]
    Invoke-PsGadgetStepper -Index 0 -Degrees 90

    .EXAMPLE
    # Reverse 180 degrees, full-step mode, faster speed  [ULN2003]
    Invoke-PsGadgetStepper -Index 0 -Degrees 180 -Direction Reverse -StepMode Full -DelayMs 1

    .EXAMPLE
    # TB6600 - full step (200 steps/rev), forward 1 revolution
    # Wiring: ENA+=CBUS0, DIR+=CBUS1, PUL+=CBUS2  (defaults)
    Invoke-PsGadgetStepper -Index 0 -Steps 200 -DriverType TB6600

    .EXAMPLE
    # TB6600 - rotate 90 degrees, 1/8 microstep (1600 steps/rev), 5ms/step
    Invoke-PsGadgetStepper -Index 0 -Degrees 90 -DriverType TB6600 -StepsPerRevolution 1600 -DelayMs 5

    .EXAMPLE
    # TB6600 - reverse 180 degrees, 1/4 microstep
    Invoke-PsGadgetStepper -Index 0 -Degrees 180 -DriverType TB6600 -Direction Reverse -StepsPerRevolution 800

    .EXAMPLE
    # Use an already-open device (device stays open after call)
    $dev = New-PsGadgetFtdi -Index 0
    Invoke-PsGadgetStepper -PsGadget $dev -Steps 2048

    .OUTPUTS
    PSCustomObject with DriverType, Direction, Steps, Degrees, StepsPerRevolution,
    DelayMs, and Device.

    .NOTES
    When using -Index or -SerialNumber the FTDI device is opened and closed
    within this call.  When using -PsGadget the caller retains ownership and
    the device is NOT closed after the call.

    ULN2003: device is left in AsyncBitBang mode after the call.
    TB6600:  device stays in MPSSE mode; I2C/SPI can be used before or after.
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    [OutputType('PSCustomObject')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByDevice', Position = 0)]
        [ValidateNotNull()]
        [object]$PsGadget,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByIndex')]
        [ValidateRange(0, 127)]
        [int]$Index = 0,

        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        # Motion specification - exactly one of -Steps or -Degrees is required
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 2147483647)]
        [int]$Steps = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0.001, 36000.0)]
        [double]$Degrees = -1,

        # Calibration: 0 = use mode-appropriate default from
        # Get-PsGadgetStepperDefaultStepsPerRev (~4075.77 half / ~2037.89 full)
        [Parameter(Mandatory = $false)]
        [ValidateRange(0.0, 100000.0)]
        [double]$StepsPerRevolution = 0,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Forward', 'Reverse')]
        [string]$Direction = 'Forward',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Full', 'Half')]
        [string]$StepMode = 'Half',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$DelayMs = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0x01, 0xFF)]
        [byte]$PinMask = 0x0F,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 4)]
        [byte]$PinOffset = 0,

        [Parameter(Mandatory = $false)]
        [switch]$AcBus,

        # --- TB6600 / step-dir parameters ---

        [Parameter(Mandatory = $false)]
        [ValidateSet('ULN2003', 'TB6600')]
        [string]$DriverType = 'ULN2003',

        # ACBUS pin numbers for ENA+, DIR+, PUL+ on the TB6600.
        # Defaults match: CBUS0=ENA+, CBUS1=DIR+, CBUS2=PUL+
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 7)]
        [byte]$EnaPin = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 7)]
        [byte]$DirPin = 1,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 7)]
        [byte]$PulPin = 0,

        # TB6600 PUL+ high-pulse width.  Minimum 2.5 µs per datasheet; 5 µs default.
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$PulseWidthUs = 5,

        # Skip ENA pin control when ENA+/ENA- are looped or tied to GND (always-enabled).
        [Parameter(Mandatory = $false)]
        [switch]$NoEnable,

        # Limit switch support (TB6600 only).
        # When set, ACBUS pins LeftLimitPin / RightLimitPin are sampled after each step.
        # HIGH (~4.8V) = switch triggered.  Move aborts when the relevant limit is hit.
        [Parameter(Mandatory = $false)]
        [switch]$UseLimits,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 7)]
        [byte]$LeftLimitPin = 4,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 7)]
        [byte]$RightLimitPin = 5,

        # Trigger polarity.  Default (not set) = active-low: LOW = limit triggered.
        # Optical/photointerruptor switches are typically active-low (beam broken -> LOW).
        # Set -LimitActiveHigh when your switches pull the pin HIGH when triggered.
        [Parameter(Mandatory = $false)]
        [switch]$LimitActiveHigh
    )

    process {
        # --- validate that exactly one motion spec was provided ---
        if ($Steps -le 0 -and $Degrees -lt 0) {
            throw "Invoke-PsGadgetStepper: supply either -Steps or -Degrees."
        }
        if ($Steps -gt 0 -and $Degrees -ge 0) {
            throw "Invoke-PsGadgetStepper: supply -Steps or -Degrees, not both."
        }

        # --- resolve StepsPerRevolution ---
        $spr = if ($StepsPerRevolution -gt 0) {
            $StepsPerRevolution
        } elseif ($DriverType -eq 'TB6600') {
            200.0    # 1.8-degree NEMA motor, full-step; override for microstep DIP setting
        } else {
            Get-PsGadgetStepperDefaultStepsPerRev -StepMode $StepMode
        }

        # --- convert degrees to steps ---
        $resolvedDegrees = -1.0
        if ($Degrees -ge 0) {
            $resolvedDegrees = $Degrees
            $Steps = [Math]::Max(1, [int][Math]::Round($Degrees / 360.0 * $spr))
            Write-Verbose "Invoke-PsGadgetStepper: $Degrees deg -> $Steps steps (spr=$spr)"
        }

        $ownsDevice = $PSCmdlet.ParameterSetName -ne 'ByDevice'
        $ftdi = $null
        try {
            # --- open device ---
            if ($PSCmdlet.ParameterSetName -eq 'ByDevice') {
                $ftdi = $PsGadget
                if (-not $ftdi -or -not $ftdi.IsOpen) {
                    throw "PsGadgetFtdi object is not open."
                }
                Write-Verbose "Invoke-PsGadgetStepper: using provided PsGadgetFtdi device"
            } elseif ($PSCmdlet.ParameterSetName -eq 'BySerial') {
                Write-Verbose "Invoke-PsGadgetStepper: opening FTDI device serial '$SerialNumber'"
                $ftdi = New-PsGadgetFtdi -SerialNumber $SerialNumber
            } else {
                Write-Verbose "Invoke-PsGadgetStepper: opening FTDI device index $Index"
                $ftdi = New-PsGadgetFtdi -Index $Index
            }

            if (-not $ftdi -or -not $ftdi.IsOpen) {
                throw "Failed to open FTDI device"
            }

            # --- execute move ---
            $moveResult = $null
            if ($DriverType -eq 'TB6600') {
                $moveResult = Invoke-PsGadgetStepDirMove `
                    -Ftdi          $ftdi `
                    -Steps         $Steps `
                    -Direction     $Direction `
                    -DelayMs       $DelayMs `
                    -EnaPin        $EnaPin `
                    -DirPin        $DirPin `
                    -PulPin        $PulPin `
                    -PulseWidthUs  $PulseWidthUs `
                    -NoEnable:$NoEnable `
                    -UseLimits:$UseLimits `
                    -LeftLimitPin    $LeftLimitPin `
                    -RightLimitPin   $RightLimitPin `
                    -LimitActiveHigh:$LimitActiveHigh
            } else {
                Invoke-PsGadgetStepperMove `
                    -Ftdi      $ftdi `
                    -Steps     $Steps `
                    -Direction $Direction `
                    -StepMode  $StepMode `
                    -DelayMs   $DelayMs `
                    -PinMask   $PinMask `
                    -PinOffset $PinOffset `
                    -AcBus:$AcBus
            }

            # --- return summary ---
            return [PSCustomObject]@{
                DriverType        = $DriverType
                StepMode          = if ($DriverType -eq 'TB6600') { $null } else { $StepMode }
                Direction         = $Direction
                Steps             = $Steps
                StepsActual       = if ($moveResult) { $moveResult.StepsActual } else { $Steps }
                LimitHit          = if ($moveResult) { $moveResult.LimitHit }   else { $false }
                Degrees           = if ($resolvedDegrees -ge 0) { [Math]::Round($resolvedDegrees, 4) } else { $null }
                StepsPerRevolution = [Math]::Round($spr, 4)
                DelayMs           = $DelayMs
                Device            = "$($ftdi.Description) ($($ftdi.SerialNumber))"
            }
        } finally {
            if ($ownsDevice -and $ftdi -and $ftdi.IsOpen) {
                Write-Verbose "Invoke-PsGadgetStepper: closing FTDI device"
                $ftdi.Close()
            }
        }
    }
}
