function Set-Ssd1306Cursor {
<#
.SYNOPSIS
Positions the SSD1306 memory cursor.

.DESCRIPTION
Sets the column and page addresses so that subsequent data writes begin at the
requested location.

.PARAMETER i2c
The I2C device handle used for communication.

.PARAMETER col
Column address between 0 and 127.

.PARAMETER page
Page index between 0 and 7.

.PARAMETER address
I2C address of the display.

.EXAMPLE
Set-Ssd1306Cursor -i2c $dev -col 64 -page 3

Moves the write position to column 64 on page 3.
#>
    param (
        [Parameter(Mandatory = $true)][object]$i2c,
        [Parameter(Mandatory = $true)][int]$col,
        [Parameter(Mandatory = $true)][int]$page,
        [byte]$address = 0x3C
    )
    
    $i2c.Write($address, [byte[]]@(0x00, (0xB0 + $page)))
    $i2c.Write($address, [byte[]]@(0x00, (0x00 + ($col -band 0x0F))))
    $i2c.Write($address, [byte[]]@(0x00, (0x10 + (($col -shr 4) -band 0x0F))))
}