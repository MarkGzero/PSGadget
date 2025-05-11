function Set-Ssd1306Cursor {
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