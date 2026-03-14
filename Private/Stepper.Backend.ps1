#Requires -Version 5.1

# ---------------------------------------------------------------------------
# Stepper.Backend.ps1
# Platform-agnostic stepper motor backend for PsGadget.
#
# Supports FT232R and FT232H via async bit-bang mode (ADBUS0-3).
# Reduces jitter by pre-computing the full step sequence as a byte buffer
# and issuing a single bulk USB write, letting the chip's built-in baud-rate
# timer pace each coil state at the requested step rate.
#
# Coil byte layout (lower nibble, IN1-IN4 via ULN2003 driver board):
#   bit 0 = IN1   bit 1 = IN2   bit 2 = IN3   bit 3 = IN4
#
# 28BYJ-48 calibration note:
#   Empirical measurements: ~508-509 output steps/rev.
#   Gear-ratio derivation:  4075.7728 / 8 = ~509.47 half-step blocks/rev
#   Source: http://www.jangeox.be/2013/10/stepper-motor-28byj-48_25.html
#   This value is NOT exactly 4096. Do NOT hardcode 2048/4096.
#   Use Get-PsGadgetStepperDefaultStepsPerRev for mode-appropriate defaults,
#   or pass a -StepsPerRevolution override when the motor has been calibrated.
# ---------------------------------------------------------------------------

# Module-level calibration constant.  Expose via Get-PsGadgetStepperDefaultStepsPerRev.
$script:Stepper_HalfStepsPerRev_28BYJ48 = 4075.7728395061727

# ---------------------------------------------------------------------------
# Get-PsGadgetStepperDefaultStepsPerRev
# Returns the calibrated default steps-per-revolution for the specified step
# mode.  For 28BYJ-48:
#   Half: ~4075.77 individual half-step pulses per output-shaft revolution
#   Full: ~2037.89 (half of the above; each full-step moves twice as far)
#
# Pass your measured value via -StepsPerRevolution to Invoke-PsGadgetStepper
# or set $dev.StepsPerRevolution on the PsGadgetFtdi object to override.
# ---------------------------------------------------------------------------
function Get-PsGadgetStepperDefaultStepsPerRev {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [ValidateSet('Full', 'Half')]
        [string]$StepMode = 'Half'
    )

    if ($StepMode -eq 'Full') {
        return ($script:Stepper_HalfStepsPerRev_28BYJ48 / 2.0)
    }
    return $script:Stepper_HalfStepsPerRev_28BYJ48
}

# ---------------------------------------------------------------------------
# Get-PsGadgetStepSequence
# Returns the ordered phase byte sequence for the given step mode and
# direction.  Each byte encodes the coil state for one step position.
#
# PinOffset shifts all bytes left by N bits to accommodate motors wired to
# higher ADBUS pins (e.g. PinOffset=4 maps IN1-IN4 to bits 4-7).
# ---------------------------------------------------------------------------
function Get-PsGadgetStepSequence {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [ValidateSet('Full', 'Half')]
        [string]$StepMode = 'Half',

        [ValidateSet('Forward', 'Reverse')]
        [string]$Direction = 'Forward',

        [ValidateRange(0, 4)]
        [byte]$PinOffset = 0
    )

    # Half-step 8-phase (smoother, higher resolution, default for 28BYJ-48)
    # Drives single coils then adjacent coil pairs in rotation.
    # Phase order: IN4, IN4+IN3, IN3, IN3+IN2, IN2, IN2+IN1, IN1, IN1+IN4
    $halfStep = [byte[]]@(0x08, 0x0C, 0x04, 0x06, 0x02, 0x03, 0x01, 0x09)

    # Full-step 4-phase (two coils energised simultaneously - higher torque)
    # Phase order: IN1+IN3, IN2+IN3, IN2+IN4, IN1+IN4
    $fullStep = [byte[]]@(0x05, 0x06, 0x0A, 0x09)

    [byte[]]$seq = if ($StepMode -eq 'Half') { $halfStep } else { $fullStep }

    if ($Direction -eq 'Reverse') {
        [System.Array]::Reverse($seq)
    }

    if ($PinOffset -gt 0) {
        $shifted = [byte[]]::new($seq.Length)
        for ($i = 0; $i -lt $seq.Length; $i++) {
            $shifted[$i] = [byte](($seq[$i] -shl $PinOffset) -band 0xFF)
        }
        return $shifted
    }

    return $seq
}

# ---------------------------------------------------------------------------
# Invoke-PsGadgetStepperMove
# Core step dispatch.  Called by Invoke-PsGadgetStepper and
# PsGadgetFtdi.Step() / PsGadgetFtdi.StepDegrees().
#
# Jitter-reduction strategy:
#   1. Build the complete step sequence as a contiguous byte[] ($Steps entries)
#   2. Configure FT232R/FT232H async bit-bang mode (ADBUS0-3)
#   3. Set baud rate = 16000 / DelayMs so the baud-rate timer paces each
#      pin-state transition at the requested interval
#   4. Issue a single FT_Write() call with the full buffer
#   5. De-energize coils (write 0x00) to prevent heat buildup at rest
#
# On stub/no-hardware machines the write is logged but not executed.
# ---------------------------------------------------------------------------
function Invoke-PsGadgetStepperMove {
    [CmdletBinding(SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Ftdi,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Steps,

        [ValidateSet('Forward', 'Reverse')]
        [string]$Direction = 'Forward',

        [ValidateSet('Full', 'Half')]
        [string]$StepMode = 'Half',

        # Inter-step delay in milliseconds.
        # Translates to baud rate: baud = 16000 / DelayMs
        # Minimum recommended for 28BYJ-48: 1ms (may stall at higher speeds)
        # Safe default:                      2ms
        [ValidateRange(1, 1000)]
        [int]$DelayMs = 2,

        # Output direction mask.  Bits correspond to ADBUS pins.
        # Default 0x0F = ADBUS0-3 all outputs (IN1-IN4 via ULN2003).
        [byte]$PinMask = 0x0F,

        # Shift IN1-IN4 bits left by this many positions.
        # Use when motor is wired on upper ADBUS pins.
        [ValidateRange(0, 4)]
        [byte]$PinOffset = 0
    )

    $log = $Ftdi.Logger
    $log.WriteDebug("StepperMove: $Steps $StepMode steps / $Direction / delay=${DelayMs}ms / mask=0x$($PinMask.ToString('X2')) / offset=$PinOffset")

    # --- build phase sequence ---
    $seq    = Get-PsGadgetStepSequence -StepMode $StepMode -Direction $Direction -PinOffset $PinOffset
    $seqLen = $seq.Length

    $buf = [byte[]]::new($Steps)
    for ($i = 0; $i -lt $Steps; $i++) {
        $buf[$i] = [byte]($seq[$i % $seqLen] -band $PinMask)
    }

    $log.WriteTrace("StepperMove: phase buffer $Steps bytes built")

    # --- enter async bit-bang mode (sets ADBUS direction mask) ---
    # Re-uses Set-PsGadgetFtdiMode so the connection's ActiveMode/GpioMethod
    # are updated consistently with the rest of the module.
    $conn       = $Ftdi._connection
    $activeMode = if ($conn -and $conn.PSObject.Properties['ActiveMode']) { $conn.ActiveMode } else { '' }

    if ($activeMode -ne 'AsyncBitBang') {
        $log.WriteInfo("StepperMove: switching to AsyncBitBang (was '$activeMode')")
        Set-PsGadgetFtdiMode -PsGadget $Ftdi -Mode AsyncBitBang -Mask $PinMask | Out-Null
    }

    # --- write bulk buffer ---
    if ($conn -and $conn.PSObject.Properties['Device'] -and $conn.Device) {
        # Baud rate controls byte-output rate in async bit-bang mode.
        # D2XX timer:  byte_rate = baud / 16
        # Required:    baud = 16000 / DelayMs
        # Clamp to 300 bps minimum (D2XX lower limit).
        $baud = [uint32]([Math]::Max(300, [int](16000 / $DelayMs)))
        $log.WriteDebug("StepperMove: SetBaudRate $baud bps (${DelayMs}ms/step)")

        try {
            $baudStatus = $conn.Device.SetBaudRate($baud)
            $log.WriteTrace("SetBaudRate $baud -> $baudStatus")
        } catch {
            $log.WriteTrace("SetBaudRate not available (stub): $($_.Exception.Message)")
        }

        try {
            [uint32]$written = 0
            $conn.Device.Write($buf, [uint32]$buf.Length, [ref]$written) | Out-Null
            $log.WriteInfo("StepperMove: wrote $written/$($buf.Length) bytes @ ${baud} bps")
        } catch [System.NotImplementedException] {
            $log.WriteTrace("StepperMove stub: FT_Write not implemented (no hardware)")
        } catch {
            $log.WriteError("StepperMove FT_Write error: $($_.Exception.Message)")
            throw
        }

        # De-energize coils after move to prevent heat at rest
        try {
            $zeroBuf = [byte[]]@(0x00)
            [uint32]$zw = 0
            $conn.Device.Write($zeroBuf, 1, [ref]$zw) | Out-Null
            $log.WriteTrace("StepperMove: coils de-energized")
        } catch {
            $log.WriteTrace("StepperMove de-energize stub: $($_.Exception.Message)")
        }
    } else {
        # Stub mode: no device handle
        $log.WriteTrace("StepperMove stub: no Device handle (Steps=$Steps, Mode=$StepMode, Dir=$Direction)")
    }
}
