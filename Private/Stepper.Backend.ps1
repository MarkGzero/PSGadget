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

        # Output direction mask.  Bits correspond to the target GPIO bank pins.
        # Default 0x0F = pins 0-3 all outputs (IN1-IN4 via ULN2003).
        [byte]$PinMask = 0x0F,

        # Shift IN1-IN4 bits left by this many positions.
        # Use when motor is wired on upper ADBUS pins (D4-D7).
        [ValidateRange(0, 4)]
        [byte]$PinOffset = 0,

        # Use ACBUS (C-bank) instead of ADBUS (D-bank) for the MPSSE step writes.
        # ADBUS (default): SET_BITS_LOW  (0x80) -- pins D0-D7
        # ACBUS:           SET_BITS_HIGH (0x82) -- pins C0-C7 (FT232H only)
        # Required when stepper is wired to ACBUS C0-C3 alongside I2C on ADBUS D0/D1.
        [switch]$AcBus
    )

    $log = $Ftdi.Logger
    $bankLabel = if ($AcBus) { 'ACBUS' } else { 'ADBUS' }
    $log.WriteDebug("StepperMove: $Steps $StepMode steps / $Direction / delay=${DelayMs}ms / mask=0x$($PinMask.ToString('X2')) / offset=$PinOffset / bank=$bankLabel")

    # --- build phase sequence ---
    $seq    = Get-PsGadgetStepSequence -StepMode $StepMode -Direction $Direction -PinOffset $PinOffset
    $seqLen = $seq.Length

    $buf = [byte[]]::new($Steps)
    for ($i = 0; $i -lt $Steps; $i++) {
        $buf[$i] = [byte]($seq[$i % $seqLen] -band $PinMask)
    }

    $log.WriteTrace("StepperMove: phase buffer $Steps bytes built")
    $script:PsGadgetLogger.WriteProto('STEPPER',
            "MOVE  $Steps steps  $StepMode  $Direction  ${DelayMs}ms/step  bank=$bankLabel")

    $conn      = $Ftdi._connection
    $gpioMethod = if ($conn -and $conn.PSObject.Properties['GpioMethod']) { $conn.GpioMethod } else { '' }

    # --- write per-step loop ---
    # Three hardware paths:
    #
    # MPSSE (FT232H, Windows/Linux with libftd2xx): three-byte MPSSE command per step.
    #   ADBUS (default, -AcBus not set): SET_BITS_LOW  (0x80, value, direction)
    #     D0-D3 reserved for MPSSE I2C; use D4-D7 with PinOffset=4 / PinMask=0xF0.
    #   ACBUS (-AcBus switch):           SET_BITS_HIGH (0x82, value, direction)
    #     C0-C7 independent of ADBUS; use when stepper is on C0-C3 alongside I2C.
    #   Both keep the device in MPSSE mode; I2C (SSD1306) continues to work.
    #   Reference: FTDI AN_108 section 3.6.1 (SET_DATA_BITS_LOW_BYTE / HIGH_BYTE).
    #
    # IoT (FT232H on macOS/Linux via dotnet IoT backend): uses GpioController.
    #   Coils must be wired to ACBUS0-3 (C0-C3). ADBUS is the MPSSE protocol bus.
    #   IoT GpioController maps ACBUS pin N to controller pin N+8.
    #
    # AsyncBitBang (FT232R or explicit override): 1-byte direct pin state write.
    #   Requires prior SetBitMode(AsyncBitBang). Mode switch handled below.
    #
    # Both paths use a Stopwatch spin-wait instead of Start-Sleep.
    # Start-Sleep has a ~15ms minimum granularity on Windows; the spin-wait
    # achieves sub-millisecond accuracy at the cost of one CPU core spinning
    # for the duration of the move.

    if ($conn -and $conn.PSObject.Properties['Device'] -and $conn.Device) {

        $sw          = [System.Diagnostics.Stopwatch]::new()
        $targetTicks = [long]($DelayMs * ([System.Diagnostics.Stopwatch]::Frequency / 1000.0))

        if ($gpioMethod -eq 'MPSSE' -or $gpioMethod -eq 'MpsseI2c') {
            # MPSSE GPIO path.  Command byte selects the GPIO bank:
            #   0x80 (SET_BITS_LOW)  = ADBUS D0-D7  (default)
            #   0x82 (SET_BITS_HIGH) = ACBUS C0-C7  (-AcBus)
            # Direction byte = PinMask (bits in mask are outputs).
            # No mode switch; device remains MPSSE-capable for I2C/SSD1306 after call.
            $mpsseCmdByte = if ($AcBus) { [byte]0x82 } else { [byte]0x80 }
            $log.WriteInfo("StepperMove: MPSSE $bankLabel path, $Steps steps @ ${DelayMs}ms")
            $mpsseCmd = [byte[]]@($mpsseCmdByte, 0x00, $PinMask)
            try {
                for ($i = 0; $i -lt $Steps; $i++) {
                    $mpsseCmd[1] = $buf[$i]
                    [uint32]$written = 0
                    $sw.Restart()
                    $conn.Device.Write($mpsseCmd, 3, [ref]$written) | Out-Null
                    while ($sw.ElapsedTicks -lt $targetTicks) {}
                }
                $log.WriteInfo("StepperMove: completed $Steps steps (MPSSE/$bankLabel)")
                $script:PsGadgetLogger.WriteProto('STEPPER', "DONE  $Steps steps  MPSSE/$bankLabel")
            } catch [System.NotImplementedException] {
                $log.WriteTrace("StepperMove stub: FT_Write not implemented (no hardware)")
            } catch {
                $log.WriteError("StepperMove FT_Write error: $($_.Exception.Message)")
                throw
            }
            # De-energize: set all coil pins low, keep direction mask
            try {
                $mpsseCmd[1] = 0x00
                [uint32]$zw = 0
                $conn.Device.Write($mpsseCmd, 3, [ref]$zw) | Out-Null
                $log.WriteTrace("StepperMove: coils de-energized (MPSSE)")
            } catch {
                $log.WriteTrace("StepperMove de-energize stub: $($_.Exception.Message)")
            }

        } elseif ($gpioMethod -eq 'IoT') {
            # IoT GpioController path (FT232H on macOS/Linux via dotnet IoT backend).
            # Coils must be wired to ACBUS0-3 (C0-C3); IoT maps these to pins 8-11.
            $gpioCtrl = $conn.GpioController
            if (-not $gpioCtrl) { throw "IoT connection is missing GpioController" }
            $log.WriteInfo("StepperMove: IoT ACBUS path, $Steps steps @ ${DelayMs}ms")
            for ($p = 0; $p -le 3; $p++) {
                $iotPin = $p + 8
                if (-not $gpioCtrl.IsPinOpen($iotPin)) {
                    $gpioCtrl.OpenPin($iotPin, [System.Device.Gpio.PinMode]::Output)
                }
            }
            try {
                for ($i = 0; $i -lt $Steps; $i++) {
                    $stepByte = $buf[$i]
                    $sw.Restart()
                    for ($p = 0; $p -le 3; $p++) {
                        $pinVal = if ($stepByte -band (1 -shl $p)) {
                            [System.Device.Gpio.PinValue]::High
                        } else {
                            [System.Device.Gpio.PinValue]::Low
                        }
                        $gpioCtrl.Write($p + 8, $pinVal)
                    }
                    while ($sw.ElapsedTicks -lt $targetTicks) {}
                }
                $log.WriteInfo("StepperMove: completed $Steps steps (IoT/ACBUS)")
                $script:PsGadgetLogger.WriteProto('STEPPER', "DONE  $Steps steps  IoT/ACBUS")
            } catch {
                $log.WriteError("StepperMove IoT error: $($_.Exception.Message)")
                throw
            }
            # De-energize
            try {
                for ($p = 0; $p -le 3; $p++) { $gpioCtrl.Write($p + 8, [System.Device.Gpio.PinValue]::Low) }
                $log.WriteTrace("StepperMove: coils de-energized (IoT)")
            } catch {
                $log.WriteTrace("StepperMove de-energize stub: $($_.Exception.Message)")
            }

        } else {
            # AsyncBitBang path (FT232R or devices not in MPSSE mode).
            # Switch mode if needed; FT232H opened in MPSSE requires a reset first.
            $activeMode = if ($conn.PSObject.Properties['ActiveMode']) { $conn.ActiveMode } else { '' }
            if ($activeMode -ne 'AsyncBitBang') {
                $log.WriteInfo("StepperMove: switching to AsyncBitBang (was '$activeMode')")
                try {
                    $conn.Device.ResetDevice() | Out-Null
                    $log.WriteTrace("StepperMove: ResetDevice before mode switch")
                    Start-Sleep -Milliseconds 50
                    $conn.Device.Purge(3) | Out-Null
                    Start-Sleep -Milliseconds 10
                } catch {
                    $log.WriteTrace("StepperMove: ResetDevice/Purge not available: $($_.Exception.Message)")
                }
                Set-PsGadgetFtdiMode -PsGadget $Ftdi -Mode AsyncBitBang -Mask $PinMask | Out-Null
            }

            $log.WriteInfo("StepperMove: AsyncBitBang path, $Steps steps @ ${DelayMs}ms")
            $stepBuf = [byte[]]@(0x00)
            try {
                for ($i = 0; $i -lt $Steps; $i++) {
                    $stepBuf[0] = $buf[$i]
                    [uint32]$written = 0
                    $sw.Restart()
                    $conn.Device.Write($stepBuf, 1, [ref]$written) | Out-Null
                    while ($sw.ElapsedTicks -lt $targetTicks) {}
                }
                $log.WriteInfo("StepperMove: completed $Steps steps (AsyncBitBang)")
                $script:PsGadgetLogger.WriteProto('STEPPER', "DONE  $Steps steps  AsyncBitBang")
            } catch [System.NotImplementedException] {
                $log.WriteTrace("StepperMove stub: FT_Write not implemented (no hardware)")
            } catch {
                $log.WriteError("StepperMove FT_Write error: $($_.Exception.Message)")
                throw
            }
            try {
                $stepBuf[0] = 0x00
                [uint32]$zw = 0
                $conn.Device.Write($stepBuf, 1, [ref]$zw) | Out-Null
                $log.WriteTrace("StepperMove: coils de-energized (AsyncBitBang)")
            } catch {
                $log.WriteTrace("StepperMove de-energize stub: $($_.Exception.Message)")
            }
        }

    } else {
        # Stub mode: no device handle
        $log.WriteTrace("StepperMove stub: no Device handle (Steps=$Steps, Mode=$StepMode, Dir=$Direction)")
    }
}
