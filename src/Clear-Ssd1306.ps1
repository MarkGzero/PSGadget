function Clear-Ssd1306 {
<#
.SYNOPSIS
Clears the SSD1306 display.

.DESCRIPTION
Writes zeros to every page and column of the display so that all pixels are
turned off.

.PARAMETER i2c
The I2C device handle used for communication.

.PARAMETER address
The I2C address of the SSD1306 display.

.EXAMPLE
Clear-Ssd1306 -i2c $device

Clears the entire screen attached to the supplied device.
#>
    param (
        [Parameter(Mandatory = $true)][object]$i2c,
        [byte]$address = 0x3C
    )
    
    # send 0x00 to all 128*64

    for ($page = 0; $page -lt 8; $page++) {
        Set-Ssd1306Cursor -i2c $i2c -col 0 -page $page -address $address
        Send-Ssd1306Data -i2c $i2c -data ([byte[]]@(0x00) * 128) -address $address
    }
}