function Start-Ssd1306Initialize {
<#
.SYNOPSIS
Runs the standard SSD1306 initialization sequence.

.DESCRIPTION
Sends the recommended set of setup commands to prepare the display for use.

.PARAMETER i2c
The I2C device used for communication.

.PARAMETER address
I2C address of the display.

.EXAMPLE
Start-Ssd1306Initialize -i2c $dev

Initializes the SSD1306 connected to the provided device.
#>
    param (
        [Parameter(Mandatory = $true)]
        [object]$i2c,
        [byte]$address = 0x3C
    )

    $commands = @(
        0xAE,       # Display OFF
        0xD5, 0x80, # Set Display Clock Divide Ratio / Oscillator Frequency
        0xA8, 0x3F, # Set Multiplex Ratio (1/64 duty)
        0xD3, 0x00, # Set Display Offset (no offset)
        0x40,       # Set Display Start Line = 0
        0x8D, 0x14, # Charge Pump Setting (Enable)
        0x20, 0x00, # Memory Addressing Mode = Horizontal
        0xA1,       # Set Segment Re-map (column address 127 is SEG0)
        0xC8,       # Set COM Output Scan Direction (remapped mode)
        0xDA, 0x12, # Set COM Pins Hardware Configuration
        0x81, 0xCF, # Set Contrast Control (0xCF = high)
        0xD9, 0xF1, # Set Pre-charge Period
        0xDB, 0x40, # Set VCOMH Deselect Level
        0xA4,       # Resume to RAM content display
        0xA6,       # Normal display (non-inverted)
        0xAF        # Display ON
    )

    foreach ($cmd in $commands) {
        $i2c.Write($address, [byte[]]@(0x00, $cmd))
        Start-Sleep -Milliseconds 1
    }
}

    