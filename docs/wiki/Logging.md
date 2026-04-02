# Logging and Protocol Trace

PSGadget writes everything — session events, errors, and wire-level protocol
entries — to a single unified log file. No configuration required.

---

## Quick reference

| | Detail |
|---|---|
| **Log file** | `~/.psgadget/logs/psgadget.log` (fixed name, appended each session) |
| **Backup** | `~/.psgadget/logs/psgadget.1.log` (created when size limit is reached) |
| **Default max size** | 50 MB (configurable via `Set-PsGadgetConfig`) |
| **Protocol tracing** | Off by default; call `Start-PsGadgetTrace` to enable |
| **Live viewer** | `Start-PsGadgetTrace` or `Get-PsGadgetLog -Follow` |

---

## Log levels

| Level | When written |
|-------|-------------|
| `[HEADER]` | Session start block (one per module import) |
| `[INFO]` | Normal operations: connect, mode switch, GPIO set |
| `[DEBUG]` | Step-level detail: buffer sizes, resolved parameters |
| `[TRACE]` | Low-level internals: individual I2C phase bytes |
| `[ERROR]` | Hardware errors and recoverable faults |
| `[PROTO]` | Wire-level protocol entries (only when `Start-PsGadgetTrace` has been called) |

---

## Log format

```
[2026-03-29 10:22:01.234] [HEADER] === PsGadget Session a1b2c3d4 2026-03-29 10:22:01 ===
[2026-03-29 10:22:01.234] [INFO]   Connecting to FTDI device (index=0)
[2026-03-29 10:22:01.489] [INFO]   Connected: FT232H FTAXBFCQ GPIO=IoT
[2026-03-29 10:22:01.501] [PROTO]  CONNECT      FT232H serial=FTAXBFCQ backend=IoT
[2026-03-29 10:22:01.512] [PROTO]  I2C.INIT     clock=400000Hz divisor=29 3phase=on
[2026-03-29 10:22:01.512] [PROTO]               RAW  8A 97 8C 86 C7 00 85
[2026-03-29 10:22:01.521] [PROTO]  SSD1306      INIT height=64px rotation=0deg 18B
[2026-03-29 10:22:01.600] [PROTO]  I2C.WRITE    addr=0x3C 19B wire=0x78
[2026-03-29 10:22:01.600] [PROTO]               RAW  00 AE D5 80 A8 3F D3 00 40 8D 14 ...
```

Each `[PROTO]` entry spans one or two lines. The first line has the subsystem
name left-aligned in 12 characters; when a RAW hex line follows, the subsystem
column is blank.

---

## Viewing the log

```powershell
# Show all lines in the current log
Get-PsGadgetLog

# Show last 100 lines
Get-PsGadgetLog -Tail 100

# Stream live updates (equivalent to tail -f)
Get-PsGadgetLog -Follow

# List log files with sizes and timestamps
Get-PsGadgetLog -List
```

The cmdlet always reads `~/.psgadget/logs/psgadget.log`. Use `-List` to see
both the active log and the rolled backup (`psgadget.1.log`).

---

## Protocol tracing

**Protocol tracing is off by default.** Wire-level `[PROTO]` entries are
written only after `Start-PsGadgetTrace` is called.

> **Call `Start-PsGadgetTrace` before connecting or running protocol commands.**
> Enabling tracing mid-session does not retroactively capture past operations.
> Commands run before `Start-PsGadgetTrace` produce no `[PROTO]` entries.

```powershell
Start-PsGadgetTrace              # enable tracing + open live viewer
$dev = New-PsGadgetFtdi         # CONNECT appears in viewer
$dev.GetDisplay().ShowSplash()  # SSD1306 + I2C entries appear
```

On **Windows**, `Start-PsGadgetTrace` opens a new PowerShell window with
colorized, auto-refreshing output on `psgadget.log`.

On **Linux/macOS**, it prints a `Get-Content -Wait` command to run in a
second terminal.

To get the log path without opening a viewer:

```powershell
$logPath = Start-PsGadgetTrace -PassThru
```

### Subsystems and color coding

| Subsystem | Color | Description |
|-----------|-------|-------------|
| `I2C.INIT` | Cyan | MPSSE I2C clock and framing configuration |
| `I2C.WRITE` | Cyan | I2C write transaction (address, byte count, wire byte) |
| `GPIO.WRITE` | Green | ACBUS or IoT GPIO pin state change |
| `CBUS.WRITE` | Dark green | FT232R CBUS pin state change |
| `MPSSE.INIT` | Dark cyan | MPSSE sync and ADBUS initialization |
| `SSD1306` | Magenta | SSD1306 init sequence, page write, full display write |
| `SPI.INIT` | Blue | MPSSE SPI clock frequency and CS pin configuration |
| `SPI.WRITE` | Blue | SPI write transaction (byte count, CS pin, hex payload) |
| `SPI.READ` | Blue | SPI read transaction (byte count, MOSI=0x00) |
| `SPI.XFER` | Blue | SPI full-duplex transfer (TX and RX byte counts) |
| `UART.TX` | DarkYellow | UART transmit bytes (byte count, ASCII if printable) |
| `UART.RX` | DarkYellow | UART receive bytes or ReadLine result |
| `UART.FLUSH` | DarkYellow | TX+RX buffer purge |
| `STEPPER` | Yellow | Stepper move start, completion |
| `CONNECT` | Dark gray | Device opened |
| `DISCONNECT` | Dark gray | Device closed |
| `RAW` | Dark cyan | Raw hex bytes (indented, second line) |
| `[ERROR]` | Red | Errors |
| `[HEADER]` | White | Session start block |
| `[DEBUG]` | Dark gray | Debug entries |

### Raw hex truncation

Raw lines show up to 64 bytes. Larger payloads append a `[...+N]` suffix:

```
RAW  40 00 00 FF 80 00 18 18 18 18 00 00 3C 7E FF FF [...+112]
```

---

## Log file management

`psgadget.log` grows by appending new session headers and entries on each
module import. When the file reaches the configured size limit, it is renamed
to `psgadget.1.log` (overwriting any previous backup) and a fresh
`psgadget.log` is started.

### Configuring the size limit

```powershell
# Default is 50 MB; increase to 200 MB
Set-PsGadgetConfig -Key logging.maxSizeMb -Value 200

# Alias form
Set-PsGadgetOption -Key logging.maxSizeMb -Value 200

# Read current setting
Get-PsGadgetConfig
```

Changes take effect the next time the module is imported (i.e., the next
session's roll check uses the new limit).

### Adjusting log verbosity

```powershell
Set-PsGadgetConfig -Key logging.level -Value DEBUG   # more detail
Set-PsGadgetConfig -Key logging.level -Value ERROR   # errors only
```

Valid levels (ascending verbosity): `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE`.

### Manual cleanup

```powershell
# List current log files with sizes
Get-PsGadgetLog -List

# Remove both files if you want a clean slate (module will recreate them)
Remove-Item ~/.psgadget/logs/psgadget*.log
```

---

## Accessing the logger from code

All device instances share the module-level singleton logger. You can read
the current log path from any device:

```powershell
$dev = New-PsGadgetFtdi
$dev.Logger.LogFilePath     # ~\.psgadget\logs\psgadget.log
$dev.Logger.SessionId       # 8-character hex session ID
$dev.Logger.TraceEnabled    # $true after Start-PsGadgetTrace is called
```
