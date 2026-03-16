#Requires -Version 5.1

function Invoke-PsGadgetStepper {
    <#
    .SYNOPSIS
    Drive a stepper motor connected to an FTDI device in a single command.

    .DESCRIPTION
    High-level stepper motor dispatch.  Opens an FTDI device, switches it to
    async bit-bang mode on ADBUS0-3, drives the attached stepper motor the
    requested number of steps or degrees, then closes the connection.

    Jitter reduction: the full step sequence is pre-computed as a byte buffer
    and written in a single USB transfer.  The D2XX baud-rate timer paces each
    coil transition, eliminating per-step USB round-trip latency.

    Supports FT232R and FT232H (both use ADBUS async bit-bang for stepper).

    Pin wiring (default, ULN2003 driver board):
        ADBUS0 (D0) -> IN1
        ADBUS1 (D1) -> IN2
        ADBUS2 (D2) -> IN3
        ADBUS3 (D3) -> IN4

    StepsPerRevolution calibration note:
        The 28BYJ-48 is NOT exactly 2048 full-steps or 4096 half-steps per
        revolution.  Empirical measurement yields ~4075.77 half-steps/rev.
        The default is that value.  Calibrate your specific unit and pass
        -StepsPerRevolution to use your measured value.  Angle-based moves
        (-Degrees) always use the configured calibration.

    .PARAMETER PsGadget
    An already-open PsGadgetFtdi object (from New-PsGadgetFtdi).
    When supplied the device is NOT closed after the call.

    .PARAMETER Index
    FTDI device index (0-based) from Get-PsGadgetFtdi.  Default is 0.

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
    Target ACBUS (C-bank, pins C0-C7) instead of ADBUS (D-bank).
    Required when the stepper is wired to ACBUS C0-C3 on an FT232H that is
    also running I2C on ADBUS D0/D1 (e.g. combined stepper + SSD1306).
    Uses MPSSE SET_BITS_HIGH (0x82) instead of SET_BITS_LOW (0x80).

    .EXAMPLE
    # Move forward 1000 half-steps (about 88 degrees)
    Invoke-PsGadgetStepper -Index 0 -Steps 1000

    .EXAMPLE
    # Rotate 90 degrees using calibrated StepsPerRevolution
    Invoke-PsGadgetStepper -Index 0 -Degrees 90

    .EXAMPLE
    # Rotate 90 degrees using a measured calibration value
    Invoke-PsGadgetStepper -Index 0 -Degrees 90 -StepsPerRevolution 4082.5

    .EXAMPLE
    # Reverse 180 degrees, full-step mode, faster speed
    Invoke-PsGadgetStepper -Index 0 -Degrees 180 -Direction Reverse -StepMode Full -DelayMs 1

    .EXAMPLE
    # Use an already-open device (device stays open after call)
    $dev = New-PsGadgetFtdi -Index 0
    Invoke-PsGadgetStepper -PsGadget $dev -Steps 2048

    .EXAMPLE
    # Shorthand via PsGadgetFtdi object methods
    $dev = New-PsGadgetFtdi -Index 0
    $dev.Step(1000)                          # 1000 half-steps forward
    $dev.StepDegrees(90)                     # ~90 degrees using default calibration
    $dev.StepDegrees(90, 'Reverse')          # 90 degrees reverse
    $dev.StepsPerRevolution = 4082.5         # apply measured calibration
    $dev.StepDegrees(180)                    # uses calibrated value

    .OUTPUTS
    PSCustomObject with StepMode, Direction, Steps, Degrees, StepsPerRevolution,
    DelayMs, and Device.

    .NOTES
    When using -Index or -SerialNumber the FTDI device is opened and closed
    within this call.  When using -PsGadget the caller retains ownership and
    the device is NOT closed after the call.

    The device is left in AsyncBitBang mode after the call.  If you need to
    reuse the device for I2C or other protocols, call:
        Set-PsGadgetFtdiMode -PsGadget $dev -Mode UART
    before the next operation.
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
        [switch]$AcBus
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
            Invoke-PsGadgetStepperMove `
                -Ftdi      $ftdi `
                -Steps     $Steps `
                -Direction $Direction `
                -StepMode  $StepMode `
                -DelayMs   $DelayMs `
                -PinMask   $PinMask `
                -PinOffset $PinOffset `
                -AcBus:$AcBus

            # --- return summary ---
            return [PSCustomObject]@{
                StepMode          = $StepMode
                Direction         = $Direction
                Steps             = $Steps
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
