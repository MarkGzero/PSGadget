function Send-Ssd1306Data {
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
    Set-Ssd1306Cursor -i2c $i2c -col $col -page $page -address $address

    # Send data with control byte 0x40
    $payload = @(0x40) + $data
    $i2c.Write($address, $payload)
}