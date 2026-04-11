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

# ---------------------------------------------------------------------------
# Invoke-PsGadgetStepDirMove
# Step/direction driver backend for TB6600 and similar dedicated stepper drivers.
#
# Unlike the coil-sequence path (Invoke-PsGadgetStepperMove), step/dir drivers
# handle all phase sequencing internally.  The host only needs to:
#   1. Assert ENA+ to enable the driver
#   2. Set DIR+ for direction
#   3. Pulse PUL+ once per step (rising edge triggers the driver)
#
# Default pin wiring (matches TB6600 on FT232H ACBUS/CBUS):
#   CBUS0 (C0) -> PUL+    rising edge per step
#   CBUS1 (C1) -> DIR+    forward = HIGH
#   ENA+/ENA-  -> looped  (always enabled; use -NoEnable to skip ENA control)
#
# If ENA+ is wired to a CBUS pin set -EnaPin and omit -NoEnable.
#
# TB6600 minimum timing (from datasheet):
#   PUL+ high time: 2.5 µs minimum (default 5 µs gives safe margin)
#   DIR setup time: 5 µs before first PUL rising edge
#
# Hardware paths supported:
#   MPSSE  (FT232H on Windows/Linux):  SET_BITS_HIGH 0x82 on ACBUS
#   IoT    (FT232H on macOS/Linux via dotnet IoT):  GpioController pins N+8
#
# AsyncBitBang (FT232R) is NOT supported for TB6600 — CBUS on FT232R uses a
# separate bit-bang mode (0x20) unrelated to ACBUS and is too slow for step/dir.
# ---------------------------------------------------------------------------
function Invoke-PsGadgetStepDirMove {
    [CmdletBinding(SupportsShouldProcess = $false)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Ftdi,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Steps,

        [ValidateSet('Forward', 'Reverse')]
        [string]$Direction = 'Forward',

        # Inter-step delay from PUL falling edge to next PUL rising edge.
        [ValidateRange(1, 10000)]
        [int]$DelayMs = 2,

        # ACBUS pin numbers for the TB6600 signal lines.
        # Defaults match: CBUS0=PUL+, CBUS1=DIR+, ENA looped (-NoEnable).
        [ValidateRange(0, 7)]
        [byte]$PulPin = 0,

        [ValidateRange(0, 7)]
        [byte]$DirPin = 1,

        # When ENA+/ENA- are looped (always-enabled), set -NoEnable to skip ENA control.
        # When ENA+ is wired to a CBUS pin, omit -NoEnable and set -EnaPin accordingly.
        [switch]$NoEnable,

        [ValidateRange(0, 7)]
        [byte]$EnaPin = 2,

        # PUL+ high-pulse width in microseconds.
        # TB6600 minimum is 2.5 µs; 5 µs default gives a safe margin.
        [ValidateRange(1, 1000)]
        [int]$PulseWidthUs = 5,

        # Limit switch support.  When -UseLimits is set, ACBUS pins LeftLimitPin
        # and RightLimitPin are sampled after each step pulse.
        # The move aborts immediately when the relevant limit for the current
        # direction is hit (Forward checks right; Reverse checks left).
        [switch]$UseLimits,

        [ValidateRange(0, 7)]
        [byte]$LeftLimitPin = 4,

        [ValidateRange(0, 7)]
        [byte]$RightLimitPin = 5,

        # Trigger polarity.  Default (not set) = active-low: LOW = limit triggered.
        # Set -LimitActiveHigh when the switch pulls the pin HIGH when triggered.
        # Optical interrupters (photointerruptors) are typically active-low.
        [switch]$LimitActiveHigh
    )

    $log = $Ftdi.Logger

    # Compute bit positions
    [byte]$dirBit = [byte](1 -shl $DirPin)
    [byte]$pulBit = [byte](1 -shl $PulPin)

    [byte]$dirVal = if ($Direction -eq 'Forward') { $dirBit } else { [byte]0 }

    if ($NoEnable) {
        [byte]$outMask   = [byte]($dirBit -bor $pulBit)
        [byte]$baseByte  = [byte]$dirVal                        # DIR=set, PUL=0
        [byte]$pulseByte = [byte]($dirVal -bor $pulBit)         # DIR=set, PUL=1
    } else {
        [byte]$enaBit    = [byte](1 -shl $EnaPin)
        [byte]$outMask   = [byte]($enaBit -bor $dirBit -bor $pulBit)
        [byte]$baseByte  = [byte]($enaBit -bor $dirVal)         # ENA=1, DIR=set, PUL=0
        [byte]$pulseByte = [byte]($baseByte -bor $pulBit)       # ENA=1, DIR=set, PUL=1
    }

    $enaLabel = if ($NoEnable) { 'looped' } else { "C$EnaPin" }
    $log.WriteDebug("StepDirMove: $Steps steps / $Direction / delay=${DelayMs}ms / pulse=${PulseWidthUs}us / ENA=$enaLabel DIR=C$DirPin PUL=C$PulPin")
    $script:PsGadgetLogger.WriteProto('STEPPER',
        "STEPDIR  $Steps steps  $Direction  ${DelayMs}ms/step  ${PulseWidthUs}us pulse  ENA=$enaLabel DIR=C$DirPin PUL=C$PulPin")

    $dirForward  = $Direction -eq 'Forward'
    $limitHit    = $false
    $stepsActual = $Steps

    $conn       = $Ftdi._connection
    $gpioMethod = if ($conn -and $conn.PSObject.Properties['GpioMethod']) { $conn.GpioMethod } else { '' }

    if ($conn -and $conn.PSObject.Properties['Device'] -and $conn.Device) {

        $sw            = [System.Diagnostics.Stopwatch]::new()
        $freq          = [System.Diagnostics.Stopwatch]::Frequency
        $stepTicks     = [long]($DelayMs      * ($freq / 1000.0))
        $pulseTicks    = [long]($PulseWidthUs * ($freq / 1000000.0))
        $dirSetupTicks = [long](5             * ($freq / 1000000.0))   # 5 µs DIR setup

        if ($gpioMethod -eq 'MPSSE' -or $gpioMethod -eq 'MpsseI2c') {
            # SET_BITS_HIGH (0x82) drives ACBUS C0-C7 while keeping ADBUS for I2C/SPI.
            $log.WriteInfo("StepDirMove: MPSSE ACBUS path, $Steps steps @ ${DelayMs}ms")
            $mpsseHigh = [byte[]]@(0x82, $pulseByte, $outMask)
            $mpsseLow  = [byte[]]@(0x82, $baseByte,  $outMask)
            [uint32]$written = 0
            [uint32]$read    = 0
            $readBuf         = [byte[]]::new(1)
            try {
                # Set initial state and wait DIR setup time before first pulse
                $conn.Device.Write($mpsseLow, 3, [ref]$written) | Out-Null
                $sw.Restart()
                while ($sw.ElapsedTicks -lt $dirSetupTicks) {}

                # Helper: given raw ACBUS byte, return $true if the specified pin is triggered.
                # Active-low (default): bit clear = triggered.  Active-high: bit set = triggered.
                $isTriggered = if ($LimitActiveHigh) {
                    [scriptblock]{ param($b, $pin) ($b -band (1 -shl $pin)) -ne 0 }
                } else {
                    [scriptblock]{ param($b, $pin) ($b -band (1 -shl $pin)) -eq 0 }
                }

                # Pre-check: read limits before first step so we don't pulse into a hard stop
                if ($UseLimits) {
                    $conn.Device.Write([byte[]](0x83, 0x87), 2, [ref]$written) | Out-Null
                    $conn.Device.Read($readBuf, 1, [ref]$read) | Out-Null
                    $acbus = $readBuf[0]
                    if (($dirForward      -and (& $isTriggered $acbus $RightLimitPin)) -or
                        (-not $dirForward -and (& $isTriggered $acbus $LeftLimitPin))) {
                        $limitHit    = $true
                        $stepsActual = 0
                        $log.WriteInfo("StepDirMove: limit already triggered, no steps issued (MPSSE/ACBUS)")
                    }
                }

                if (-not $limitHit) {
                    for ($i = 0; $i -lt $Steps; $i++) {
                        $conn.Device.Write($mpsseHigh, 3, [ref]$written) | Out-Null
                        $sw.Restart()
                        while ($sw.ElapsedTicks -lt $pulseTicks) {}
                        $conn.Device.Write($mpsseLow, 3, [ref]$written) | Out-Null
                        $sw.Restart()
                        while ($sw.ElapsedTicks -lt $stepTicks) {}
                        if ($UseLimits) {
                            $conn.Device.Write([byte[]](0x83, 0x87), 2, [ref]$written) | Out-Null
                            $conn.Device.Read($readBuf, 1, [ref]$read) | Out-Null
                            $acbus = $readBuf[0]
                            if (($dirForward      -and (& $isTriggered $acbus $RightLimitPin)) -or
                                (-not $dirForward -and (& $isTriggered $acbus $LeftLimitPin))) {
                                $limitHit    = $true
                                $stepsActual = $i + 1
                                break
                            }
                        }
                    }
                }
                $log.WriteInfo("StepDirMove: completed $stepsActual/$Steps steps (MPSSE/ACBUS)$(if ($limitHit) { ' [limit hit]' })")
                $script:PsGadgetLogger.WriteProto('STEPPER', "DONE  $stepsActual/$Steps steps  MPSSE/ACBUS STEPDIR$(if ($limitHit) { ' LIMIT' })")
            } catch [System.NotImplementedException] {
                $log.WriteTrace("StepDirMove stub: FT_Write not implemented (no hardware)")
            } catch {
                $log.WriteError("StepDirMove FT_Write error: $($_.Exception.Message)")
                throw
            }

        } elseif ($gpioMethod -eq 'IoT') {
            # IoT GpioController: ACBUS pin N -> controller pin N+8
            $gpioCtrl = $conn.GpioController
            if (-not $gpioCtrl) { throw "StepDirMove: IoT connection is missing GpioController" }
            $dirIot = $DirPin + 8
            $pulIot = $PulPin + 8
            $iotPins = @($dirIot, $pulIot)
            if (-not $NoEnable) { $iotPins += ($EnaPin + 8) }
            foreach ($p in $iotPins) {
                if (-not $gpioCtrl.IsPinOpen($p)) {
                    $gpioCtrl.OpenPin($p, [System.Device.Gpio.PinMode]::Output)
                }
            }
            $log.WriteInfo("StepDirMove: IoT ACBUS path, $Steps steps @ ${DelayMs}ms")
            $high      = [System.Device.Gpio.PinValue]::High
            $low       = [System.Device.Gpio.PinValue]::Low
            $dirPinVal = if ($Direction -eq 'Forward') { $high } else { $low }

            # Open limit input pins once before the move
            if ($UseLimits) {
                $leftIot  = $LeftLimitPin  + 8
                $rightIot = $RightLimitPin + 8
                foreach ($lp in @($leftIot, $rightIot)) {
                    if (-not $gpioCtrl.IsPinOpen($lp)) {
                        $gpioCtrl.OpenPin($lp, [System.Device.Gpio.PinMode]::Input)
                    }
                }
            }

            try {
                if (-not $NoEnable) { $gpioCtrl.Write($EnaPin + 8, $high) }
                $gpioCtrl.Write($dirIot, $dirPinVal)
                $gpioCtrl.Write($pulIot, $low)
                $sw.Restart()
                while ($sw.ElapsedTicks -lt $dirSetupTicks) {}

                # Helper: return $true when the IoT pin reads the triggered state.
                # Active-low (default): Low = triggered.  Active-high: High = triggered.
                $iotTriggered = if ($LimitActiveHigh) {
                    [scriptblock]{ param($pin) $gpioCtrl.Read($pin) -eq [System.Device.Gpio.PinValue]::High }
                } else {
                    [scriptblock]{ param($pin) $gpioCtrl.Read($pin) -eq [System.Device.Gpio.PinValue]::Low }
                }

                # Pre-check: read limits before first step
                if ($UseLimits) {
                    if (($dirForward      -and (& $iotTriggered $rightIot)) -or
                        (-not $dirForward -and (& $iotTriggered $leftIot))) {
                        $limitHit    = $true
                        $stepsActual = 0
                        $log.WriteInfo("StepDirMove: limit already triggered, no steps issued (IoT/ACBUS)")
                    }
                }

                if (-not $limitHit) {
                    for ($i = 0; $i -lt $Steps; $i++) {
                        $gpioCtrl.Write($pulIot, $high)
                        $sw.Restart()
                        while ($sw.ElapsedTicks -lt $pulseTicks) {}
                        $gpioCtrl.Write($pulIot, $low)
                        $sw.Restart()
                        while ($sw.ElapsedTicks -lt $stepTicks) {}
                        if ($UseLimits) {
                            if (($dirForward      -and (& $iotTriggered $rightIot)) -or
                                (-not $dirForward -and (& $iotTriggered $leftIot))) {
                                $limitHit    = $true
                                $stepsActual = $i + 1
                                break
                            }
                        }
                    }
                }
                $log.WriteInfo("StepDirMove: completed $stepsActual/$Steps steps (IoT/ACBUS)$(if ($limitHit) { ' [limit hit]' })")
                $script:PsGadgetLogger.WriteProto('STEPPER', "DONE  $stepsActual/$Steps steps  IoT/ACBUS STEPDIR$(if ($limitHit) { ' LIMIT' })")
            } catch {
                $log.WriteError("StepDirMove IoT error: $($_.Exception.Message)")
                throw
            }

        } else {
            throw ("StepDirMove: DriverType TB6600 requires MPSSE or IoT connection " +
                   "(current GpioMethod='$gpioMethod').  AsyncBitBang does not support ACBUS step/dir.")
        }

    } else {
        $log.WriteTrace("StepDirMove stub: no Device handle (Steps=$Steps, Dir=$Direction)")
    }

    return [PSCustomObject]@{
        Steps        = $Steps
        StepsActual  = $stepsActual
        Direction    = $Direction
        LimitHit     = $limitHit
        DelayMs      = $DelayMs
    }
}
