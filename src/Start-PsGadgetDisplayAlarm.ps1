function Start-PsGadgetDisplayAlarm {
    param (
        [Parameter(Mandatory = $false)]
        [int]$DurationSeconds = 3,
        [Parameter(Mandatory = $false)]
        [object]$I2CDevice = $psgadget_ds
    )

    # Constants
    $SCREEN_WIDTH = 128
    $SCREEN_HEIGHT = 64
    $BUFFER_SIZE = 1024
    $PAGES = 8

    # Create two buffers - one for yellow flash (pages 0-1) and one for warning symbol (pages 2-7)
    $yellowBuf = [byte[]]::new($BUFFER_SIZE)
    $warningBuf = [byte[]]::new($BUFFER_SIZE)

    # Define "ALARM" text pattern (8x5 pixels per character, 5 characters)
    $alarmPattern = @(
        # A     L     A     R     M
        0xE0, 0xF8, 0xE0, 0xF8, 0xFC, # Row 1
        0xB8, 0x80, 0xB8, 0x84, 0xA4, # Row 2
        0xF8, 0x80, 0xF8, 0x88, 0xA4, # Row 3
        0xB8, 0x80, 0xB8, 0x90, 0xA4, # Row 4
        0xB8, 0xF8, 0xB8, 0x88, 0xA4, # Row 5
        0x00, 0x00, 0x00, 0x00, 0x00  # Spacing
    )

    function Draw-InsetText {
        param (
            [byte[]]$buffer,
            [int]$x,
            [int]$y
        )
        
        $textWidth = 5 * 6  # 5 characters * 6 pixels width
        $startX = $x - ($textWidth / 2)
        
        for ($charIndex = 0; $charIndex -lt 5; $charIndex++) {
            for ($row = 0; $row -lt 5; $row++) {
                $pattern = $alarmPattern[$row]
                for ($bit = 0; $bit -lt 5; $bit++) {
                    if ($pattern -band (0x80 -shr $bit)) {
                        $px = $startX + ($charIndex * 6) + $bit
                        $py = $y + $row
                        if ($px -ge 0 -and $px -lt $SCREEN_WIDTH) {
                            $page = [math]::Floor($py / 8)
                            $index = ($page * $SCREEN_WIDTH) + $px
                            $bitPos = $py % 8
                            $buffer[$index] = $buffer[$index] -band (-bnot (1 -shl $bitPos))
                        }
                    }
                }
            }
        }
    }

    function Draw-WarningTriangle {
        param (
            [byte[]]$buffer,
            [int]$cx,  # center x
            [int]$cy,  # center y
            [int]$size = 16
        )
    
        $half = [math]::Floor($size / 2)
    
        for ($y = 0; $y -lt $size; $y++) {
            # Width of the triangle at this height
            $span = [math]::Floor(($size - $y) / $size * $half)
            for ($x = -$span; $x -le $span; $x++) {
                $px = $cx + $x
                $py = $cy + $y - $half  # center vertically
    
                if ($px -ge 0 -and $px -lt 128 -and $py -ge 0 -and $py -lt 64) {
                    $page = [math]::Floor($py / 8)
                    $index = ($page * 128) + $px
                    $bitPos = $py % 8
                    $buffer[$index] = $buffer[$index] -bor (1 -shl $bitPos)
                }
            }
        }
    
        # Optional: draw a '!' near the middle (small vertical bar)
        $ex = $cx
        for ($dy = -3; $dy -le 1; $dy++) {
            $py = $cy + $dy
            if ($py -ge 0 -and $py -lt 64) {
                $page = [math]::Floor($py / 8)
                $index = ($page * 128) + $ex
                $bitPos = $py % 8
                $buffer[$index] = $buffer[$index] -bxor (1 -shl $bitPos)
            }
        }
    
        # Optional: draw dot at the bottom
        $dotY = $cy + 3
        if ($dotY -lt 64) {
            $page = [math]::Floor($dotY / 8)
            $index = ($page * 128) + $cx
            $bitPos = $dotY % 8
            $buffer[$index] = $buffer[$index] -bxor (1 -shl $bitPos)
        }
    }
     

    function Render-SplitBuffer {
        param (
            [object]$i2c,
            [byte[]]$topBuffer,
            [byte[]]$bottomBuffer,
            [byte]$address = 0x3C
        )
        
        # Render yellow section (pages 0-1)
        for ($page = 0; $page -lt 2; $page++) {
            $startIndex = $page * $SCREEN_WIDTH
            $endIndex = $startIndex + $SCREEN_WIDTH - 1
            Set-PsGadgetDisplayCursor -i2c $i2c -col 0 -page $page -address $address
            Send-PsGadgetDisplayData -i2c $i2c -data $topBuffer[$startIndex..$endIndex] -address $address
        }

        # Render white section (pages 2-7)
        for ($page = 2; $page -lt 8; $page++) {
            $startIndex = $page * $SCREEN_WIDTH
            $endIndex = $startIndex + $SCREEN_WIDTH - 1
            Set-PsGadgetDisplayCursor -i2c $i2c -col 0 -page $page -address $address
            Send-PsGadgetDisplayData -i2c $i2c -data $bottomBuffer[$startIndex..$endIndex] -address $address
        }
    }

    # Main animation loop
    $centerX = $SCREEN_WIDTH / 2
    $centerY = $SCREEN_HEIGHT / 2
    $framesPerSecond = 20
    $totalFrames = $DurationSeconds * $framesPerSecond

    for ($i = 0; $i -lt $totalFrames; $i++) {
        # Clear both buffers
        [Array]::Clear($yellowBuf, 0, $BUFFER_SIZE)
        [Array]::Clear($warningBuf, 0, $BUFFER_SIZE)
        
        # Fill yellow section (pages 0-1)
        if ($i % 6 -lt 3) {
            # Fill pages 0-1 completely
            for ($j = 0; $j -lt (2 * $SCREEN_WIDTH); $j++) {
                $yellowBuf[$j] = 0xFF
            }
            
            # Draw inset "ALARM" text
            Draw-InsetText -buffer $yellowBuf -x $centerX -y 5
        }

        # Draw warning triangle in white section (pages 2-7)
        $triangleSize = 30 + [Math]::Sin($i / 4) * 10
        Draw-WarningTriangle -buffer $warningBuf -cx $centerX -cy ($centerY + 8) -size $triangleSize
        
        # Render both sections
        Render-SplitBuffer -i2c $I2CDevice -topBuffer $yellowBuf -bottomBuffer $warningBuf
        Start-Sleep -Milliseconds (1000 / $framesPerSecond)
    }
}

#Start-PsGadgetDisplayAlarm -I2CDevice $psgadget_ds -DurationSeconds 3