$header = @{
    1 = ">> HOT TAKE <<"
    2 = ">> INCOMING <<"
}

$body = @{
    3 = "Python"
    5 = "is better than "
    6 = "PowerShell"
}

$sw = [System.Diagnostics.Stopwatch]::new()
$sw.start()
while ($sw.Elapsed.Seconds -lt 5) {
    $header.GetEnumerator() | sort Name | % {
        [System.Collections.Generic.List[byte]]$buffer = @()
        $line = $_.Name
        $str = $_.Value
        $arrChar = $str.ToCharArray()

        foreach ($char in $arrChar) {
            $glyph = $script:glyphs["$char"]
            if ($glyph) {
                foreach ($b in $glyph) {
                    $buffer.Add([byte]$b)
                }
            }
        }

        Send-PsGadgetDisplayData -i2c $psgadget_ds -data $buffer -page $line -align 'center'
        Start-Sleep -Milliseconds 250
        Clear-PsGadgetDisplay $psgadget_ds
    }
}
<<<<<<< HEAD
if ($buffer.Count -gt 0) {
    Clear-ssd1306 $psgadget_ds
    $fullPayload = $buffer.ToArray()
    @(0..7) | ForEach-Object {
     Send-psgadgetdisplaydata -i2c $psgadget_ds -data $fullPayload -page $_ -address 0x3C
    }
}
=======
>>>>>>> 535c95b64cc02f0fcc0076bb410188351dae9767

$sw.stop()

$body.GetEnumerator() | sort Name | % {
    [System.Collections.Generic.List[byte]]$buffer = @()
    $line = $_.Name
    $str = $_.Value
    $arrChar = $str.ToCharArray()

    foreach ($char in $arrChar) {
        $glyph = $script:glyphs["$char"]
        if ($glyph) {
            foreach ($b in $glyph) {
                $buffer.Add([byte]$b)
            }
        }
    }

    Send-PsGadgetDisplayData -i2c $psgadget_ds -data $buffer -page $line -align 'center'
}
