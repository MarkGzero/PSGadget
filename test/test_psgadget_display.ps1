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
