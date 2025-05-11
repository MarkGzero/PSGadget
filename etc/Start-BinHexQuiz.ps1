function Start-HexBinQuiz {
    [CmdletBinding()]
    param(
        [int]$Rounds = 10
    )

    $score = 0
    for ($i = 1; $i -le $Rounds; $i++) {
        # pick random 4‑bit value (0–15)
        $n = Get-Random -Minimum 0 -Maximum 16

        # choose whether to show hex or binary
        if ((Get-Random -Maximum 2) -eq 0) {
            # show hex, ask for binary
            $promptVal     = '0x' + $n.ToString('X')
            $expected      = '0b' + [Convert]::ToString($n,2).PadLeft(4,'0')
            $resp          = Read-Host "[$i/$Rounds] Convert $promptVal to binary nibble (prefix with 0b)"
        }
        else {
            # show binary, ask for hex
            $promptVal     = '0b' + [Convert]::ToString($n,2).PadLeft(4,'0')
            $expected      = '0x' + $n.ToString('X')
            $resp          = Read-Host "[$i/$Rounds] Convert $promptVal to hex nibble (prefix with 0x)"
        }

        # normalize response
        $respNorm = $resp.Trim().ToLower()
        $expNorm  = $expected.ToLower()

        if ($respNorm -eq $expNorm) {
            Write-Host 'Correct!' -ForegroundColor Green
            $score++
        }
        else {
            Write-Host "Nope - expected $expected" -ForegroundColor Red
        }
    }

    Write-Host "`nYou scored $score out of $Rounds." -ForegroundColor Cyan
}
