function Start-Ssd1306Initialize {
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
    
function Send-Ssd1306Data {
    param (
        [Parameter(Mandatory = $true)][object]$i2c,
        [Parameter(Mandatory = $true)][byte[]]$data,
        [byte]$address = 0x3C
    )
    
    # Prepend control byte 0x40 for data mode
    $payload = @(0x40) + $data
    $i2c.Write($address, [byte[]]$payload)
}
    
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
