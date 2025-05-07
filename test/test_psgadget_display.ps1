
$ftdi = [FtdiSharp.FtdiDevices]::scan() | Select-Object -First 1
$psgadget_ds = [FtdiSharp.Protocols.I2C]::new($ftdi)
$psgadget_ds.scan() | ForEach-Object {"0x{0:X2}" -f $_}

Start-Ssd1306Initialize -i2c $psgadget_ds
Set-Ssd1306Cursor -i2c $psgadget_ds -col 0 -page 0
Clear-Ssd1306 -i2c $psgadget_ds

$str = "Ps Gadget!" 
$arrChar = $str.ToCharArray()
[System.Collections.Generic.List[byte]]$buffer = @()

foreach ($char in $arrChar) {
    $glyph = $glyphs["$char"]
    if ($glyph) {
        foreach ($b in $glyph) {
            $buffer.Add([byte]$b)
        }
    }
}
if ($buffer.Count -gt 0) {
    Clear-ssd1306 $psgadget_ds
    $fullPayload = $buffer.ToArray()
    Send-Ssd1306Data -i2c $psgadget_ds -data $fullPayload -align 'center' -fontsize 3
}

