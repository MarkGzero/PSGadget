# Logging and Protocol Trace

PSGadget writes two separate log streams to `~/.psgadget/logs/` automatically,
with no configuration required.

---

## Quick reference

| Stream | File pattern | What it records | How to view |
|--------|-------------|-----------------|-------------|
| Session log | `psgadget-yyyyMMdd-HHmmss.log` | Module events, device lifecycle, errors | Any text editor or `Get-Content` |
| Protocol trace | `trace-yyyyMMdd-HHmmss.log` | Every I2C transaction, GPIO state change, MPSSE command, SSD1306 write, stepper move | `Open-PsGadgetTrace` (live viewer) |

Both files are created in `~/.psgadget/logs/` on first use and are appended
to throughout the session. Neither requires opt-in.

---

## Session log (PsGadgetLogger)

A new session log is created for each device instance (`New-PsGadgetFtdi`,
`Connect-PsGadgetFtdi`). It records high-level operations at four levels:

| Level | When written | Console output |
|-------|-------------|----------------|
| `INFO` | Normal operations: connect, mode switch, GPIO set | Visible with `-Verbose` |
| `DEBUG` | Step-level detail: buffer sizes, resolved parameters | Visible with `-Debug` |
| `TRACE` | Low-level internals: individual I2C phase bytes, stub calls | File only |
| `ERROR` | Recoverable hardware errors | Shown as `Write-Warning` |

### Log format

```
[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] Message
```

Session header at the top of each file:

```
=== PsGadget Session Started ===
Timestamp: 2026-03-29 10:22:01
Session ID: a1b2c3d4
OS: Microsoft Windows NT 10.0.26200.0
PowerShell: 7.4.6
Module Version: 0.1.0
User: mark
Computer: WORKSTATION01
=================================
[2026-03-29 10:22:01.234] [INFO] Connecting to FT232H (index=0, serial=BG01X3GX)
[2026-03-29 10:22:01.489] [INFO] MPSSE GPIO initialized
[2026-03-29 10:22:01.501] [INFO] I2C initialized at 400000 Hz
[2026-03-29 10:22:03.012] [INFO] Set ACBUS[0] HIGH
[2026-03-29 10:22:03.112] [INFO] Set ACBUS[0] LOW
```

### Viewing the session log

```powershell
# Find the most recent session log
Get-ChildItem ~/.psgadget/logs/psgadget-*.log | Sort-Object LastWriteTime | Select-Object -Last 1

# Tail it (waits for new lines)
Get-Content ~/.psgadget/logs/psgadget-20260329-102201.log -Wait
```

### Enabling verbose output at the console

Session log INFO lines also call `Write-Verbose`. To see them in the terminal:

```powershell
$VerbosePreference = 'Continue'
$dev = New-PsGadgetFtdi
# or pass -Verbose to individual commands:
Set-PsGadgetGpio -PsGadget $dev -Pins 0 -State HIGH -Verbose
```

### Accessing the log path from code

Every `PsGadgetFtdi` instance exposes its logger:

```powershell
$dev = New-PsGadgetFtdi
$dev.Logger.LogFilePath     # full path to this session's log file
$dev.Logger.SessionId       # 8-character hex session ID
```

---

## Protocol trace (PsGadgetTrace)

The protocol trace captures the raw wire activity across every subsystem --
I2C, GPIO, MPSSE, SSD1306, stepper -- in a single file shared by all devices.

**Tracing is off by default.** Call `Open-PsGadgetTrace` to activate it.
All hardware operations after that call are recorded.

### Activating the trace

```powershell
Open-PsGadgetTrace         # start trace + open viewer
$dev = New-PsGadgetFtdi    # CONNECT appears in viewer
$dev.Display('hello', 0)   # I2C + SSD1306 writes appear in viewer
```

On **Windows**, `Open-PsGadgetTrace` opens a new PowerShell window with
colorized, auto-refreshing output.

On **Linux/macOS**, it prints a `Get-Content -Wait` command to run in a
second terminal.

Each call to `Open-PsGadgetTrace` truncates the previous trace and starts
fresh. There is always exactly one trace file:

```
~/.psgadget/logs/trace.log
```

Pass `-PassThru` to get the path without opening a window:

```powershell
$tracePath = Open-PsGadgetTrace -PassThru
```

### Trace format

```
=== PsGadget Trace  session=a1b2c3d4  2026-03-29 10:22:01 ===
HH:mm:ss.fff  SUBSYSTEM     Semantic summary
              (blank)       RAW  hex bytes
```

Example trace output:

```
=== PsGadget Trace  session=a1b2c3d4  2026-03-29 10:22:01 ===
10:22:01.489  CONNECT       FT232H  serial=BG01X3GX  backend=IoT
10:22:01.492  MPSSE.INIT    GPIO initialized  sync=OK  ADBUS all-low
              RAW           8A 97 8C 86 C7 00 85  +  80 00 00 (x5)
10:22:01.501  I2C.INIT      clock=400000Hz  divisor=29  3phase=on  drive-zero=on
              RAW           8A 97 8C 86 C7 00 85 00 8D 29 00 9E 07 00 80 03 03
10:22:01.521  SSD1306       INIT  height=64px  rotation=0deg  18B
              RAW           AE D5 80 A8 3F D3 00 40 8D 14 20 00 A1 C8 DA 12 81 CF AF
10:22:01.534  I2C.WRITE     addr=0x3C  19B  wire=0x78
              RAW           00 AE D5 80 A8 3F D3 00 40 8D 14 20 00 A1 C8 DA 12 81 CF
10:22:01.600  SSD1306       PAGE 0  128B
              RAW           00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 [...+112]
10:22:01.612  GPIO.WRITE    ACBUS val=0x01 dir=0xFF  (MPSSE x5)
              RAW           0x82 0x01 0xFF
10:22:05.034  STEPPER       MOVE  508 steps  Half  Forward  2ms/step  bank=ADBUS
10:22:06.051  STEPPER       DONE  508 steps  MPSSE/ADBUS
10:22:06.055  DISCONNECT    FT232H  serial=BG01X3GX  backend=IoT
```

### Subsystems and color coding

| Subsystem | Color | Description |
|-----------|-------|-------------|
| `I2C.INIT` | Cyan | MPSSE I2C clock and framing configuration |
| `I2C.WRITE` | Cyan | I2C write transaction (address, byte count, wire byte) |
| `I2C.SCAN` | Cyan | I2C address scan results |
| `GPIO.WRITE` | Green | ACBUS or IoT GPIO pin state change |
| `CBUS.WRITE` | Dark green | FT232R CBUS pin state change |
| `MPSSE.INIT` | Dark cyan | MPSSE sync and ADBUS initialization |
| `SSD1306` | Magenta | SSD1306 init sequence, page write, full display write |
| `STEPPER` | Yellow | Stepper move start, completion |
| `CONNECT` | Dark gray | Device opened |
| `DISCONNECT` | Dark gray | Device closed |
| `RAW` | Dark cyan | Raw hex bytes (indented, second line) |

### Raw hex truncation

Raw lines show up to 64 bytes. If the payload is larger, the remainder is
indicated by a `[...+N]` suffix:

```
RAW  40 00 00 FF 80 00 18 18 18 18 00 00 3C 7E FF FF [...+112]
```

### Accessing the trace file path

```powershell
Open-PsGadgetTrace -PassThru    # returns path without opening a viewer window
```

The file is always `~/.psgadget/logs/trace.log`.

---

## Log file management

Both log types accumulate in `~/.psgadget/logs/`. PSGadget does not rotate
or delete old files automatically.

```powershell
# List all logs by age
Get-ChildItem ~/.psgadget/logs/ | Sort-Object LastWriteTime

# Remove logs older than 30 days
Get-ChildItem ~/.psgadget/logs/ |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item

# Check total size
(Get-ChildItem ~/.psgadget/logs/ | Measure-Object -Property Length -Sum).Sum / 1MB
```

---

## Relationship between the two streams

| | Session log | Protocol trace |
|---|---|---|
| Scope | One file per device instance | Single `trace.log` (shared by all devices) |
| Active | Always (created at device connect) | Only after `Open-PsGadgetTrace` is called |
| Granularity | Operation-level (connect, set pin, I2C write) | Wire-level (MPSSE bytes, hex payloads) |
| Best for | Diagnosing errors, understanding device lifecycle | Verifying protocol compliance, debugging hardware |
| Format | `[timestamp] [LEVEL] message` | `HH:mm:ss.fff  SUBSYSTEM  summary` + RAW line |
| Real-time viewer | `Get-Content -Wait` | `Open-PsGadgetTrace` |
