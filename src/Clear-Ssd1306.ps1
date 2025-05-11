function Clear-Ssd1306 {
    param (
        [Parameter(Mandatory = $true)][object]$i2c,
        [byte]$address = 0x3C
    )
    
    for ($page = 0; $page -lt 8; $page++) {
        Set-Ssd1306Cursor -i2c $i2c -col 0 -page $page -address $address
        Send-Ssd1306Data -i2c $i2c -data ([byte[]]@(0x00) * 128) -address $address
    }
}