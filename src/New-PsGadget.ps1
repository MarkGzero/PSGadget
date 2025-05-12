function Open-PsGadgetDisplay {
    [cmdletbinding()]
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

function Set-PsGadgetDisplayCursor {
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
    
function Send-PsGadgetDisplayData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][object]$i2c,
        [Parameter(Mandatory = $true)][byte[]]$data,
        [byte]$address = 0x3C,
        [int]$page = 0,

        [ValidateSet(1, 2)][int]$FontSize = 1,
        [switch]$Invert,

        [ValidateSet('left', 'right', 'center')]
        [string]$Align = 'left'
    )

    # Apply inversion if requested
    if ($Invert) {
        $data = $data | ForEach-Object { $_ -bxor 0xFF }
    }

    # Optional: Scale font horizontally (basic 2x font)
    if ($FontSize -eq 2) {
        $scaled = @()
        foreach ($byte in $data) {
            $scaled += $byte, $byte  # duplicate each column horizontally
        }
        $data = [byte[]]$scaled
    }
    # Determine starting column based on alignment
    $col = switch ($Align) {
        'center' { [math]::Floor((128 - $data.Length) / 2) }
        'right'  { [math]::Max(0, 128 - $data.Length) }
        default  { 0 }
    }

    # Move cursor
    Set-PsGadgetDisplayCursor -i2c $i2c -col $col -page $page -address $address

    # Send data with control byte 0x40
    $payload = @(0x40) + $data
    $i2c.Write($address, $payload)
}


    
function Clear-PsGadgetDisplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$i2c,
        [byte]$address = 0x3C
    )

    # 1) Build a “data” buffer: first byte 0x40 (data control), then 128 zeros
    $zeroData = New-Object byte[] 129
    $zeroData[0] = 0x40
    for ($i = 1; $i -lt 129; $i++) {
        $zeroData[$i] = 0x00
    }

    # 2) For each of the 8 pages:
    for ($page = 0; $page -lt 8; $page++) {
        # a) Build a single command packet:
        #    0x00 = control byte for “these are commands”,
        #    0xB0+page = select page,
        #    0x00     = set lower column address to 0,
        #    0x10     = set higher column address to 0
        $cmds = [byte[]]@(0x00, (0xB0 + $page), 0x00, 0x10)

        # b) Send the 4‑byte command
        $i2c.Write($address, $cmds)

        # c) Now dump 128 zeros to that page
        $i2c.Write($address, $zeroData)
    }
}
