#Requires -Version 5.1
# Open-PsGadgetTrace.ps1
# Enables protocol-level logging in the unified session log and opens a live colorized viewer.
# Protocol entries ([PROTO] level) are written to ~/.psgadget/logs/psgadget.log alongside
# the regular session log entries.  Calling this is the on/off switch for protocol tracing.

function Open-PsGadgetTrace {
    <#
    .SYNOPSIS
    Enables protocol-level tracing and opens a live colorized viewer on the session log.

    .DESCRIPTION
    Open-PsGadgetTrace activates [PROTO] entries in the unified session log
    (~/.psgadget/logs/psgadget.log).  Protocol tracing is off by default; this function
    turns it on for the current session.

    All hardware operations after this call -- I2C transactions, GPIO state changes, MPSSE
    commands, SSD1306 framebuffer writes, stepper moves -- are recorded at [PROTO] level
    in the same file as regular INFO/DEBUG/ERROR entries.

    On Windows, a new pwsh (or powershell.exe) window opens with colorized, auto-refreshing
    output.  On Linux/macOS, a Get-Content -Wait command is printed for a second terminal.

    Typical usage:
        Open-PsGadgetTrace              # enable tracing + open viewer
        $dev = New-PsGadgetFtdi         # CONNECT appears in viewer
        $dev.GetDisplay().ShowSplash()  # SSD1306 + I2C entries appear

    .PARAMETER PassThru
    Return the log file path instead of opening a viewer window.

    .EXAMPLE
    Open-PsGadgetTrace
    $dev = New-PsGadgetFtdi -Index 0
    $dev.GetDisplay().ShowSplash()

    .PARAMETER Clear
    Truncate the session log before enabling tracing and opening the viewer.

    .EXAMPLE
    Open-PsGadgetTrace -Clear
    $dev = New-PsGadgetFtdi -Index 0

    .EXAMPLE
    $path = Open-PsGadgetTrace -PassThru
    # Linux: Get-Content -LiteralPath $path -Wait
    #>

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [switch]$PassThru,
        [switch]$Clear
    )

    $logger = Get-PsGadgetModuleLogger
    if (-not $logger) {
        Write-Warning 'Open-PsGadgetTrace: logger not available'
        return
    }

    if ($Clear) {
        $logger.Clear()   # closes writer, truncates file, reopens -- avoids null-byte gap
        Write-Host 'Log cleared. Close any old viewer windows -- they cannot rewind after truncation.' -ForegroundColor DarkYellow
        Write-Verbose "Cleared session log: $($logger.LogFilePath)"
    }

    $logger.TraceEnabled = $true
    $logPath = $logger.LogFilePath

    if ($PassThru) {
        return $logPath
    }

    # Inline viewer script -- runs in a new process, no module dependency
    $viewerScript = @"
`$path = '$($logPath -replace "'", "''")'
`$Host.UI.RawUI.WindowTitle = 'PSGadget Log'
Write-Host 'PSGadget Session Log  --  ' -NoNewline -ForegroundColor White
Write-Host `$path -ForegroundColor DarkGray
Write-Host ('-' * 70) -ForegroundColor DarkGray
Get-Content -LiteralPath `$path -Wait | ForEach-Object {
    `$line = `$_
    if     (`$line -match '\[HEADER\]')                     { Write-Host `$line -ForegroundColor White     }
    elseif (`$line -match '\[ERROR\]')                      { Write-Host `$line -ForegroundColor Red       }
    elseif (`$line -match '\[PROTO\].*I2C')                 { Write-Host `$line -ForegroundColor Cyan      }
    elseif (`$line -match '\[PROTO\].*SPI')                 { Write-Host `$line -ForegroundColor Blue      }
    elseif (`$line -match '\[PROTO\].*UART')                { Write-Host `$line -ForegroundColor DarkYellow }
    elseif (`$line -match '\[PROTO\].*GPIO')                { Write-Host `$line -ForegroundColor Green     }
    elseif (`$line -match '\[PROTO\].*STEPPER')             { Write-Host `$line -ForegroundColor Yellow    }
    elseif (`$line -match '\[PROTO\].*SSD1306')             { Write-Host `$line -ForegroundColor Magenta   }
    elseif (`$line -match '\[PROTO\].*CBUS')                { Write-Host `$line -ForegroundColor DarkGreen }
    elseif (`$line -match '\[PROTO\].*MPSSE')               { Write-Host `$line -ForegroundColor DarkCyan  }
    elseif (`$line -match '\[PROTO\].*(CONNECT|DISCONNECT)'){ Write-Host `$line -ForegroundColor DarkGray  }
    elseif (`$line -match '\[PROTO\].*RAW')                 { Write-Host `$line -ForegroundColor DarkCyan  }
    elseif (`$line -match '\[PROTO\]')                      { Write-Host `$line -ForegroundColor Gray      }
    elseif (`$line -match '\[INFO\].*(Connected:|Closing FTDI|PsGadgetFtdi created)') { Write-Host `$line -ForegroundColor Cyan }
    elseif (`$line -match '\[INFO\].*CBUS GPIO')            { Write-Host `$line -ForegroundColor DarkGreen }
    elseif (`$line -match '\[INFO\].*(GPIO|MPSSE GPIO)')    { Write-Host `$line -ForegroundColor Green     }
    elseif (`$line -match '\[DEBUG\]')                      { Write-Host `$line -ForegroundColor DarkGray  }
    else                                                    { Write-Host `$line                            }
}
"@

    $runningOnWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

    if ($runningOnWindows) {
        $bytes   = [System.Text.Encoding]::Unicode.GetBytes($viewerScript)
        $encoded = [Convert]::ToBase64String($bytes)

        Start-Process powershell -ArgumentList '-NoExit', '-EncodedCommand', $encoded
        Write-Verbose "Trace viewer opened in new powershell window: $logPath"
    } else {
        Write-Host ''
        Write-Host 'Run this in a second terminal to follow the session log:' -ForegroundColor White
        Write-Host ''
        Write-Host "  Get-Content -LiteralPath '$logPath' -Wait" -ForegroundColor Cyan
        Write-Host ''
    }
}
