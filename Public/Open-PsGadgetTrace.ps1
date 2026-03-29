#Requires -Version 5.1
# Open-PsGadgetTrace.ps1
# Activates the PSGadget protocol trace and opens a colorized viewer in a new terminal.
# Calling this is the switch: tracing is off until Open-PsGadgetTrace runs.

function Open-PsGadgetTrace {
    <#
    .SYNOPSIS
    Activates the PSGadget protocol trace and opens a live viewer in a new terminal window.

    .DESCRIPTION
    Open-PsGadgetTrace is the on/off switch for the protocol trace.  Tracing is disabled
    until this function is called.  Each call truncates the previous trace and starts fresh.

    All hardware operations after this call — I2C transactions, GPIO state changes, MPSSE
    commands, SSD1306 framebuffer writes, stepper moves — are recorded to:
        ~/.psgadget/logs/trace.log

    On Windows, a new pwsh (or powershell.exe) window opens automatically with colorized
    output.  On Linux/macOS, the tail command is printed to run in a second terminal.

    Typical usage:
        Open-PsGadgetTrace         # start trace + open viewer
        $dev = New-PsGadgetFtdi    # hardware ops now appear in the viewer
        $dev.SetPin(0, 'HIGH')

    .PARAMETER PassThru
    Return the trace file path instead of opening a viewer window.

    .EXAMPLE
    Open-PsGadgetTrace
    $dev = New-PsGadgetFtdi -Index 0
    $dev.Display('hello', 0)

    .EXAMPLE
    $path = Open-PsGadgetTrace -PassThru
    # Linux: tail -f $path
    #>

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [switch]$PassThru
    )

    # Dispose any existing trace writer before creating a new one
    if ($script:PsGadgetTrace) {
        $script:PsGadgetTrace.Dispose()
        $script:PsGadgetTrace = $null
    }

    # Create the trace writer — truncates trace.log and writes the session header
    try {
        $script:PsGadgetTrace = [PsGadgetTrace]::new()
    } catch {
        Write-Warning "Open-PsGadgetTrace: could not create trace writer: $_"
        return
    }

    $tracePath = $script:PsGadgetTrace.TraceFilePath

    if ($PassThru) {
        return $tracePath
    }

    # Inline viewer script — runs in a new process with no module dependency
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

        $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
        Start-Process $exe -ArgumentList '-NoExit', '-EncodedCommand', $encoded
        Write-Verbose "Trace viewer opened in new $exe window: $tracePath"
    } else {
        Write-Host ''
        Write-Host 'Run this in a second terminal to follow the protocol trace:' -ForegroundColor White
        Write-Host ''
        Write-Host "  Get-Content -LiteralPath '$tracePath' -Wait" -ForegroundColor Cyan
        Write-Host ''
    }
}
