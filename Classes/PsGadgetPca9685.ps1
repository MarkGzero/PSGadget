#Requires -Version 5.1

# Classes/PsGadgetPca9685.ps1
# PCA9685 16-Channel PWM Controller Class

class PsGadgetPca9685 : PsGadgetI2CDevice {
    [int]$Frequency                    # PWM frequency in Hz (default 50 for RC servos)
    [hashtable]$ChannelState           # Cache of last known degrees per channel (0-15)

    # PCA9685 Register Addresses
    [byte]static hidden $REG_MODE1 = 0x00
    [byte]static hidden $REG_MODE2 = 0x01
    [byte]static hidden $REG_SUBADR1 = 0x02
    [byte]static hidden $REG_SUBADR2 = 0x03
    [byte]static hidden $REG_SUBADR3 = 0x04
    [byte]static hidden $REG_ALLCALL = 0x05
    [byte]static hidden $REG_LED0_ON_L = 0x06
    [byte]static hidden $REG_LED0_ON_H = 0x07
    [byte]static hidden $REG_LED0_OFF_L = 0x08
    [byte]static hidden $REG_LED0_OFF_H = 0x09
    [byte]static hidden $REG_PRESCALE = 0xFE
    [byte]static hidden $REG_TESTMODE = 0xFF

    # PCA9685 Configuration Constants
    [int]static hidden $OSC_CLOCK = 25000000      # 25 MHz internal oscillator
    [int]static hidden $PWM_STEPS = 4096          # 12-bit PWM resolution (0-4095)
    [int]static hidden $CHANNELS = 16             # 16 independent PWM channels

    # Servo pulse mapping (standard RC: 500µs–2500µs for 0–180 degrees)
    # Store in microseconds as integers to avoid float static member issues in PS5.1.
    [int]static hidden $PULSE_MIN_US = 500    # 0.5 ms at 0 degrees
    [int]static hidden $PULSE_MAX_US = 2500   # 2.5 ms at 180 degrees
    [int]static hidden $DEGREE_MIN = 0
    [int]static hidden $DEGREE_MAX = 180

    PsGadgetPca9685() {
        $this.Logger.WriteInfo("Creating PsGadgetPca9685 instance")

        $this.I2CAddress = 0x40         # Standard PCA9685 base address
        $this.Frequency = 50             # RC servo default frequency
        $this.IsInitialized = $false
        $this.ChannelState = @{}

        # Initialize channel cache
        for ($i = 0; $i -lt [PsGadgetPca9685]::CHANNELS; $i++) {
            $this.ChannelState[$i] = 90  # Default to center position
        }
    }

    PsGadgetPca9685([System.Object]$ftdiDevice) {
        $this.Logger.WriteInfo("Creating PsGadgetPca9685 instance with FTDI device")

        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = 0x40
        $this.Frequency = 50
        $this.IsInitialized = $false
        $this.ChannelState = @{}

        for ($i = 0; $i -lt [PsGadgetPca9685]::CHANNELS; $i++) {
            $this.ChannelState[$i] = 90
        }
    }

    PsGadgetPca9685([System.Object]$ftdiDevice, [byte]$address) {
        $this.Logger.WriteInfo("Creating PsGadgetPca9685 instance with FTDI device and address 0x$($address.ToString('X2'))")

        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = $address
        $this.Frequency = 50
        $this.IsInitialized = $false
        $this.ChannelState = @{}

        for ($i = 0; $i -lt [PsGadgetPca9685]::CHANNELS; $i++) {
            $this.ChannelState[$i] = 90
        }
    }

    [bool] Initialize([bool]$force) {
        if (-not $this.BeginInitialize($force)) {
            return $this.IsInitialized
        }

        $this.Logger.WriteInfo("Initializing PCA9685 at address 0x$($this.I2CAddress.ToString('X2')) with frequency $($this.Frequency) Hz")

        try {
            # Calculate prescaler for desired frequency
            # Formula: prescale_value = round(25MHz / (4096 * frequency)) - 1
            $prescaleValue = [math]::Round(([PsGadgetPca9685]::OSC_CLOCK / ([PsGadgetPca9685]::PWM_STEPS * $this.Frequency))) - 1

            # Clamp prescale value to valid range (0-255)
            if ($prescaleValue -lt 0) { $prescaleValue = 0 }
            if ($prescaleValue -gt 255) { $prescaleValue = 255 }

            $this.Logger.WriteDebug("Calculated prescaler value: $prescaleValue for $($this.Frequency) Hz")

            # Step 1: Reset device to known state
            $this.Logger.WriteTrace("Writing MODE1=0x00 (reset)")
            if (-not $this.I2CWrite(@([PsGadgetPca9685]::REG_MODE1, 0x00))) {
                throw "Failed to reset MODE1"
            }

            # Step 2: Put device to SLEEP so prescaler can be written
            # MODE1 bit4 = SLEEP; bit7 (RESTART) must be 0 during prescale write
            # 0x10 = 0001 0000 = SLEEP only
            $this.Logger.WriteTrace("Writing MODE1=0x10 (sleep for prescale write)")
            if (-not $this.I2CWrite(@([PsGadgetPca9685]::REG_MODE1, 0x10))) {
                throw "Failed to write MODE1 sleep command"
            }

            # Step 3: Write Prescaler register (must be done while SLEEP bit is set)
            $this.Logger.WriteTrace("Writing PRESCALE register=$prescaleValue")
            if (-not $this.I2CWrite(@([PsGadgetPca9685]::REG_PRESCALE, [byte]$prescaleValue))) {
                throw "Failed to write prescaler"
            }

            # Step 4: Restore MODE1 without SLEEP bit (wake device)
            $this.Logger.WriteTrace("Writing MODE1=0x00 (wake device)")
            if (-not $this.I2CWrite(@([PsGadgetPca9685]::REG_MODE1, 0x00))) {
                throw "Failed to write MODE1 wake command"
            }

            # Step 5: Wait for oscillator to stabilize (datasheet min 500 us; use 5 ms per Adafruit)
            Start-Sleep -Milliseconds 5

            # Step 6: Enable auto-increment (AI, bit5) and set RESTART (bit7)
            # 0xA0 = 1010 0000 = RESTART(bit7) + AI(bit5)
            # AI is REQUIRED for multi-byte channel register writes to advance correctly.
            # Without AI, all bytes in a 5-byte write go to the same register.
            $this.Logger.WriteTrace("Writing MODE1=0xA0 (RESTART + auto-increment enabled)")
            if (-not $this.I2CWrite(@([PsGadgetPca9685]::REG_MODE1, 0xA0))) {
                throw "Failed to enable auto-increment"
            }

            # Step 5: Initialize all channels to OFF state
            $this.Logger.WriteTrace("Initializing all 16 channels to OFF")
            for ($ch = 0; $ch -lt [PsGadgetPca9685]::CHANNELS; $ch++) {
                $regBase = [PsGadgetPca9685]::REG_LED0_ON_L + ($ch * 4)
                # Write all zeros: ON_L=0, ON_H=0, OFF_L=0, OFF_H=0
                if (-not $this.I2CWrite(@([byte]$regBase, 0x00, 0x00, 0x00, 0x00))) {
                    throw "Failed to initialize channel $ch"
                }
            }

            $this.IsInitialized = $true
            $this.Logger.WriteInfo("PCA9685 initialization completed successfully")
            return $true

        } catch {
            $this.Logger.WriteError("PCA9685 initialization failed: $_")
            $this.IsInitialized = $false
            return $false
        }
    }

    # Calculate PWM OFF-count for a given servo angle in degrees.
    # Uses microsecond arithmetic throughout to avoid PS5.1 float constant issues.
    # Returns object with OnCount (always 0) and OffCount properties.
    hidden [PSCustomObject] DegreesToCounts([int]$degrees) {
        # Clamp degrees to valid range
        if ($degrees -lt [PsGadgetPca9685]::DEGREE_MIN) { $degrees = [PsGadgetPca9685]::DEGREE_MIN }
        if ($degrees -gt [PsGadgetPca9685]::DEGREE_MAX) { $degrees = [PsGadgetPca9685]::DEGREE_MAX }

        # Map degrees -> pulse width in microseconds
        # e.g. 0° -> 500µs, 90° -> 1500µs, 180° -> 2500µs at standard RC range
        $pulseUs = [PsGadgetPca9685]::PULSE_MIN_US + [int][math]::Round(
            ([double]$degrees / [double][PsGadgetPca9685]::DEGREE_MAX) *
            ([PsGadgetPca9685]::PULSE_MAX_US - [PsGadgetPca9685]::PULSE_MIN_US)
        )

        # Convert microseconds to 12-bit PWM step count.
        # offCount = pulseUs * frequency * 4096 / 1_000_000
        # e.g. at 50Hz: 2500µs -> 2500 * 50 * 4096 / 1000000 = 512
        $offCount = [int][math]::Round(
            [double]$pulseUs * [double]$this.Frequency * [double][PsGadgetPca9685]::PWM_STEPS / 1000000.0
        )

        return [PSCustomObject]@{
            Degrees  = $degrees
            PulseUs  = $pulseUs
            OnCount  = 0          # pulse always starts at counter zero
            OffCount = $offCount
        }
    }

    # Set servo position on a specific channel
    [bool] SetChannel([int]$channel, [int]$degrees) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("PCA9685 not initialized")
            return $false
        }

        if ($channel -lt 0 -or $channel -ge [PsGadgetPca9685]::CHANNELS) {
            $this.Logger.WriteError("Invalid channel: $channel (valid range: 0-$([PsGadgetPca9685]::CHANNELS - 1))")
            return $false
        }

        # Clamp degrees to valid range
        if ($degrees -lt [PsGadgetPca9685]::DEGREE_MIN) { $degrees = [PsGadgetPca9685]::DEGREE_MIN }
        if ($degrees -gt [PsGadgetPca9685]::DEGREE_MAX) { $degrees = [PsGadgetPca9685]::DEGREE_MAX }

        try {
            $counts = $this.DegreesToCounts($degrees)

            # Calculate register address for this channel
            # Each channel uses 4 consecutive bytes: ON_L, ON_H, OFF_L, OFF_H
            # Channel 0: 0x06-0x09, Channel 1: 0x0A-0x0D, etc.
            $regBase = [PsGadgetPca9685]::REG_LED0_ON_L + ($channel * 4)

            # Write ON_L, ON_H, OFF_L, OFF_H
            # Using auto-increment so all 4 bytes are written in one I2C transaction
            $onL = $counts.OnCount -band 0xFF
            $onH = ($counts.OnCount -shr 8) -band 0xFF
            $offL = $counts.OffCount -band 0xFF
            $offH = ($counts.OffCount -shr 8) -band 0xFF

            $this.Logger.WriteTrace("Channel ${channel}: degrees=$degrees pulse=$($counts.PulseUs)us on=$($counts.OnCount) off=$($counts.OffCount)")

            if (-not $this.I2CWrite(@([byte]$regBase, $onL, $onH, $offL, $offH))) {
                throw "Failed to set channel $channel"
            }

            # Cache the degree value
            $this.ChannelState[$channel] = $degrees

            return $true

        } catch {
            $this.Logger.WriteError("Failed to set channel $channel to $degrees degrees: $_")
            return $false
        }
    }

    # Set multiple channels at once
    [bool] SetChannels([int[]]$degreesArray) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("PCA9685 not initialized")
            return $false
        }

        $this.Logger.WriteTrace("Setting $($degreesArray.Count) channels")

        # Set each channel sequentially for now
        # (Could be optimized with batched I2C writes if performance needed)
        for ($i = 0; $i -lt $degreesArray.Count; $i++) {
            if ($i -ge [PsGadgetPca9685]::CHANNELS) {
                $this.Logger.WriteDebug("Ignoring degree values beyond channel 15")
                break
            }

            if (-not $this.SetChannel($i, $degreesArray[$i])) {
                return $false
            }
        }

        return $true
    }

    # Get current cached degree value for a channel
    [int] GetChannel([int]$channel) {
        if ($channel -lt 0 -or $channel -ge [PsGadgetPca9685]::CHANNELS) {
            $this.Logger.WriteError("Invalid channel: $channel (valid range: 0-$([PsGadgetPca9685]::CHANNELS - 1))")
            return 0
        }

        return $this.ChannelState[$channel]
    }

    # Get current frequency
    [int] GetFrequency() {
        return $this.Frequency
    }

    # Set new frequency and reinitialize (requires SLEEP mode access)
    [bool] SetFrequency([int]$hz) {
        $this.Logger.WriteDebug("Changing frequency from $($this.Frequency) Hz to $hz Hz")

        if ($hz -lt 23 -or $hz -gt 1526) {
            $this.Logger.WriteError("Invalid frequency: $hz (valid range: 23-1526 Hz per PCA9685 datasheet)")
            return $false
        }

        $this.Frequency = $hz

        # Re-initialize with new frequency
        return $this.Initialize($true)   # Force reinit with new frequency
    }
}
