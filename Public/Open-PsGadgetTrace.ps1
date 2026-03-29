#Requires -Version 5.1
# Open-PsGadgetTrace.ps1
# Opens a colorized protocol trace viewer in a new terminal window (Windows),
# or prints the tail command to run in a second terminal (Linux/macOS).

function Open-PsGadgetTrace {
    <#
    .SYNOPSIS
    Opens the PSGadget protocol trace viewer in a new terminal window.

    .DESCRIPTION
    Launches a second PowerShell window that tails the current session's protocol
    trace log with color-coded output per subsystem:
      Cyan    = I2C operations
      Green   = GPIO operations
      Yellow  = Stepper motor steps
      Magenta = SSD1306 OLED writes
      DarkCyan= MPSSE commands / RAW bytes
      DarkGray= CONNECT / DISCONNECT events

    On Windows, a new pwsh (or powershell.exe) window opens automatically.
    On Linux/macOS, the tail command is printed to the console — run it in a
    second terminal.

    .PARAMETER PassThru
    Return the trace file path instead of opening a viewer.

    .EXAMPLE
    # Open the trace viewer, then run your hardware script
    Open-PsGadgetTrace
    $dev = New-PsGadgetFtdi -Index 0
    $dev.SetPin(0, 'HIGH')

    .EXAMPLE
    # Get the path and tail with your own tool
    $path = Open-PsGadgetTrace -PassThru
    # Linux: tail -f $path
    #>

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [switch]$PassThru
    )

    if (-not $script:PsGadgetTrace -or -not $script:PsGadgetTrace.TraceFilePath) {
        Write-Warning 'Protocol trace is not active. Import-Module PSGadget to start it.'
        return
    }

    $tracePath = $script:PsGadgetTrace.TraceFilePath

    if ($PassThru) {
        return $tracePath
    }

    # Inline viewer script — embedded as a string so it runs cleanly in a new process
    # with no module dependency (just Get-Content + Write-Host coloring)
    $viewerScript = @"
`$path = '$($tracePath -replace "'", "''")'
`$Host.UI.RawUI.WindowTitle = 'PSGadget Trace'
Write-Host 'PSGadget Protocol Trace  --  ' -NoNewline -ForegroundColor White
Write-Host `$path -ForegroundColor DarkGray
Write-Host ('-' * 70) -ForegroundColor DarkGray
Get-Content -LiteralPath `$path -Wait | ForEach-Object {
    `$line = `$_
    if     (`$line -match '  RAW  ')             { Write-Host `$line -ForegroundColor DarkCyan  }
    elseif (`$line -match '  I2C')               { Write-Host `$line -ForegroundColor Cyan      }
    elseif (`$line -match '  GPIO')              { Write-Host `$line -ForegroundColor Green     }
    elseif (`$line -match '  STEPPER')           { Write-Host `$line -ForegroundColor Yellow    }
    elseif (`$line -match '  SSD1306')           { Write-Host `$line -ForegroundColor Magenta   }
    elseif (`$line -match '  CBUS')              { Write-Host `$line -ForegroundColor DarkGreen }
    elseif (`$line -match '  MPSSE')             { Write-Host `$line -ForegroundColor DarkCyan  }
    elseif (`$line -match 'CONNECT|DISCONNECT')  { Write-Host `$line -ForegroundColor DarkGray  }
    elseif (`$line -match '^===')                { Write-Host `$line -ForegroundColor White     }
    else                                         { Write-Host `$line                            }
}
"@

    $runningOnWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

    if ($runningOnWindows) {
        # Encode as UTF-16LE Base64 so quoting in the path is irrelevant
        $bytes   = [System.Text.Encoding]::Unicode.GetBytes($viewerScript)
        $encoded = [Convert]::ToBase64String($bytes)

        # Prefer pwsh (PS 7+) for colour support; fall back to powershell.exe (PS 5.1)
        $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
        Start-Process $exe -ArgumentList '-NoExit', '-EncodedCommand', $encoded
        Write-Verbose "Trace viewer opened in new $exe window: $tracePath"
    } else {
        # Linux/macOS: no portable way to spawn a new terminal window
        Write-Host ''
        Write-Host 'Run this in a second terminal to follow the protocol trace:' -ForegroundColor White
        Write-Host ''
        Write-Host "  Get-Content -LiteralPath '$tracePath' -Wait" -ForegroundColor Cyan
        Write-Host ''
        Write-Host "Or with color (copy Open-PsGadgetTrace viewer script above)." -ForegroundColor DarkGray
    }
}
