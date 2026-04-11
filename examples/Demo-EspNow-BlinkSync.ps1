<#
.SYNOPSIS
    ESP-NOW Controller/Peripheral Blink Sync -- live demo

.DESCRIPTION
    Optionally deploys main.py to each board, then opens a live terminal
    dashboard showing the controller's NeoPixel state and each peripheral's
    blink sequences as they are received and replayed.

    Hardware:
        COM28  Waveshare ESP32-S3-Zero  (controller, NeoPixel GPIO21)
        COM26  ESP32 DevKit V1          (peripheral, LED GPIO2)
        COM27  ESP32 DevKit V1          (peripheral, LED GPIO2)

.PARAMETER ControllerPort
    COM port for the Waveshare ESP32-S3-Zero controller board.

.PARAMETER PeripheralPorts
    COM port(s) for the ESP32 DevKit peripheral boards.

.PARAMETER ScriptRoot
    Path to the folder containing espnow_controller.py and espnow_peripheral.py.
    Defaults to the mpy\scripts folder relative to this script.

.PARAMETER Deploy
    Deploy main.py to every board before starting the dashboard.
    Skipped by default -- use this flag on first run or after script changes.

.PARAMETER DurationSeconds
    How long to run the live dashboard. Default: 120 seconds (2 minutes).

.EXAMPLE
    # First run -- deploy then watch
    .\Demo-EspNow-BlinkSync.ps1 -Deploy

    # Subsequent runs -- boards already flashed, just watch
    .\Demo-EspNow-BlinkSync.ps1

    # Custom ports
    .\Demo-EspNow-BlinkSync.ps1 -ControllerPort COM3 -PeripheralPorts COM4,COM5 -Deploy
#>
param(
    [string]   $ControllerPort    = 'COM28',
    [string[]] $PeripheralPorts   = @('COM26', 'COM27'),
    [string]   $ScriptRoot        = $null,
    [switch]   $Deploy,
    [int]      $DurationSeconds   = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$_here = Split-Path $MyInvocation.MyCommand.Path
if (-not $ScriptRoot) {
    $ScriptRoot = Join-Path (Split-Path $_here) 'mpy\scripts'
}
$ControllerScript  = Join-Path $ScriptRoot 'espnow_controller.py'
$PeripheralScript  = Join-Path $ScriptRoot 'espnow_peripheral.py'

# ---------------------------------------------------------------------------
# ANSI helpers
# ---------------------------------------------------------------------------
$ESC = [char]27
function ansi($code) { "$ESC[${code}m" }

$RESET  = ansi 0
$BOLD   = ansi 1
$DIM    = ansi 2
$RED    = ansi '91'
$GREEN  = ansi '92'
$YELLOW = ansi '93'
$BLUE   = ansi '94'
$CYAN   = ansi '96'
$WHITE  = ansi '97'
$GRAY   = ansi '37'

function Write-Colour([string]$Text, [string]$Colour = $WHITE) {
    Write-Host "${Colour}${Text}${RESET}" -NoNewline
}

# ---------------------------------------------------------------------------
# Step 1 -- optional deployment
# ---------------------------------------------------------------------------
if ($Deploy) {
    Write-Host ""
    Write-Colour "  Deploying scripts...`n" $BOLD

    foreach ($script in @(
        [pscustomobject]@{ Port = $ControllerPort; File = $ControllerScript; Label = 'Controller' }
        $PeripheralPorts | ForEach-Object { [pscustomobject]@{ Port = $_; File = $PeripheralScript; Label = 'Peripheral' } }
    )) {
        Write-Colour "    $($script.Label) " $CYAN
        Write-Colour "$($script.Port)  " $GRAY
        if (-not (Test-Path $script.File)) {
            Write-Colour "MISSING: $($script.File)`n" $RED
            exit 1
        }
        $result = mpremote connect $script.Port fs cp $script.File :main.py + reset 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Colour "FAILED`n" $RED
            Write-Host $result
            exit 1
        }
        Write-Colour "OK`n" $GREEN
    }
    Write-Host ""
    Write-Colour "  Waiting 4 s for boards to boot...`n`n" $DIM
    Start-Sleep -Seconds 4
}

# ---------------------------------------------------------------------------
# Step 2 -- open serial ports (read-only, no REPL interrupt)
# ---------------------------------------------------------------------------
function Open-SerialPort([string]$Port) {
    $p = [System.IO.Ports.SerialPort]::new($Port, 115200)
    $p.ReadTimeout  = 50
    $p.DtrEnable    = $true
    $p.Open()
    $p
}

Write-Colour "  Opening serial ports...`n" $BOLD

$ports = @{}
$allPorts = @($ControllerPort) + $PeripheralPorts
foreach ($port in $allPorts) {
    try {
        $ports[$port] = Open-SerialPort $port
        Write-Colour "    $port  " $GRAY
        Write-Colour "open`n" $GREEN
    } catch {
        Write-Colour "    $port  " $GRAY
        Write-Colour "FAILED: $_`n" $RED
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 3 -- state tracking
# ---------------------------------------------------------------------------
$state = @{
    ControllerPort  = $ControllerPort
    PeerCount       = 0
    LastSeq         = ''
    LastSendTime    = $null
    Peripherals     = @{}
}
foreach ($port in $PeripheralPorts) {
    $state.Peripherals[$port] = @{
        Status   = 'booting'
        LastBlink= ''
        BlinkTime= $null
    }
}

# ---------------------------------------------------------------------------
# Step 4 -- dashboard renderer
# ---------------------------------------------------------------------------
function Render-Dashboard {
    $now = Get-Date

    # Move cursor to top of dashboard (interactive console only)
    if ($isInteractive) { [Console]::SetCursorPosition(0, $dashRow) }

    # -- Controller row
    $peerStr = switch ($state.PeerCount) {
        0 { "${YELLOW}waiting${RESET}" }
        1 { "${GREEN}1 peer${RESET}" }
        default { "${CYAN}$($state.PeerCount) peers${RESET}" }
    }

    $seqStr = if ($state.LastSeq) {
        $age = if ($state.LastSendTime) { [int]($now - $state.LastSendTime).TotalSeconds } else { 0 }
        "${DIM}last seq ${RESET}${WHITE}[$($state.LastSeq)]${RESET} ${DIM}${age}s ago${RESET}"
    } else {
        "${DIM}no sequence sent yet${RESET}"
    }

    $ledStr = switch ($state.PeerCount) {
        0 { "${YELLOW}●${RESET} amber" }
        1 { "${GREEN}●${RESET} green" }
        default { "${CYAN}●${RESET} teal " }
    }

    Write-Host ("  {0,-22} {1}  LED {2}  {3}" -f
        "${BOLD}${CYAN}CONTROLLER${RESET} ${GRAY}[$($state.ControllerPort)]${RESET}",
        $peerStr, $ledStr, $seqStr)

    Write-Host ""

    # -- Peripheral rows
    foreach ($port in $PeripheralPorts) {
        $p = $state.Peripherals[$port]
        $statusStr = switch ($p.Status) {
            'booting'    { "${DIM}booting...${RESET}" }
            'searching'  { "${YELLOW}● searching${RESET}" }
            'connected'  { "${GREEN}● connected${RESET}" }
            default      { "${GRAY}$($p.Status)${RESET}" }
        }

        $blinkStr = if ($p.LastBlink) {
            $durations = $p.LastBlink -split ','
            $bar = ($durations | ForEach-Object {
                $d = [int]$_
                if     ($d -lt 150) { "${DIM}▏${RESET}" }
                elseif ($d -lt 300) { "▍" }
                elseif ($d -lt 450) { "${BOLD}▊${RESET}" }
                else                { "${BOLD}█${RESET}" }
            }) -join ''
            $age = if ($p.BlinkTime) { [int]($now - $p.BlinkTime).TotalSeconds } else { 0 }
            "${WHITE}${bar}${RESET}  ${DIM}[$($p.LastBlink)] ${age}s ago${RESET}"
        } else {
            "${DIM}waiting for first blink sequence...${RESET}"
        }

        Write-Host ("  {0,-28} {1}  {2}" -f
            "${BOLD}PERIPHERAL${RESET} ${GRAY}[$port]${RESET}",
            $statusStr,
            $blinkStr)
    }

    Write-Host ""
    $elapsed = [int]($now - $startTime).TotalSeconds
    $remaining = $DurationSeconds - $elapsed
    Write-Host "  ${DIM}Running ${elapsed}s / ${DurationSeconds}s  (Ctrl-C to stop)${RESET}   " -NoNewline
}

# ---------------------------------------------------------------------------
# Step 5 -- run
# ---------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Colour "  ESP-NOW Controller / Peripheral Blink Sync`n" $BOLD
Write-Colour "  ==========================================`n`n" $DIM
Write-Host "  ${CYAN}●${RESET} Waveshare ESP32-S3-Zero  NeoPixel GPIO21  ${GRAY}$ControllerPort${RESET}"
foreach ($port in $PeripheralPorts) {
    Write-Host "  ${BLUE}●${RESET} ESP32 DevKit V1          LED GPIO2        ${GRAY}$port${RESET}"
}
Write-Host ""
Write-Host "  ${DIM}Tip: Run with ${RESET}-Deploy${DIM} to flash scripts; omit if already deployed.${RESET}"
Write-Host ""
Write-Host "  $('-' * 72)"
Write-Host ""

$isInteractive = $Host.Name -eq 'ConsoleHost' -and [Console]::IsOutputRedirected -eq $false
$dashRow   = if ($isInteractive) { [Console]::CursorTop } else { 0 }
$startTime = Get-Date

# Render blank dashboard to reserve space (interactive only)
if ($isInteractive) {
    foreach ($i in 1..(3 + $PeripheralPorts.Count)) { Write-Host "" }
}

try {
    while ([int](((Get-Date) - $startTime).TotalSeconds) -lt $DurationSeconds) {

        # Read one line from each port (non-blocking via short timeout)
        foreach ($port in $allPorts) {
            try {
                $line = $ports[$port].ReadLine().Trim()
                if (-not $line) { continue }

                # Controller lines
                if ($port -eq $ControllerPort) {
                    if ($line -match '^Peer joined:.*total=(\d+)') {
                        $state.PeerCount = [int]$Matches[1]
                    }
                    if ($line -match '^Blink seq -> \d+ peer\(s\): (.+)$') {
                        $state.LastSeq      = $Matches[1]
                        $state.LastSendTime = Get-Date
                    }
                }

                # Peripheral lines
                if ($state.Peripherals.ContainsKey($port)) {
                    $p = $state.Peripherals[$port]
                    if ($line -match 'searching')  { $p.Status = 'searching' }
                    if ($line -match 'connected')  { $p.Status = 'connected' }
                    if ($line -match '^Blink: (.+)$') {
                        $p.LastBlink = $Matches[1]
                        $p.BlinkTime = Get-Date
                    }
                }
            } catch [System.TimeoutException] {
                # no data on this port this cycle -- normal
            } catch {
                # port error -- skip silently
            }
        }

        Render-Dashboard
        Start-Sleep -Milliseconds 200
    }
} finally {
    foreach ($p in $ports.Values) {
        try { $p.Close() } catch {}
    }
    Write-Host ""
    Write-Host ""
    Write-Colour "  Demo complete.`n`n" $BOLD
}
