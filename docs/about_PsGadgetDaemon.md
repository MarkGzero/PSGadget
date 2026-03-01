# PSGadget Daemon Reference

## about_PsGadgetDaemon

### TOPIC
Background device daemons -- running PsGadget hardware without an interactive PowerShell terminal

---

## Table of Contents

- [Short Description](#short-description)
- [Motivation](#motivation)
- [Architecture Overview](#architecture-overview)
- [IPC Mechanisms](#ipc-mechanisms)
  - [Named Pipe (preferred)](#named-pipe-preferred)
  - [File Drop Directory (alternative)](#file-drop-directory-alternative)
- [Daemon Lifecycle](#daemon-lifecycle)
  - [Starting a Daemon](#starting-a-daemon)
  - [Stopping a Daemon](#stopping-a-daemon)
  - [Checking Status](#checking-status)
- [Command Schema](#command-schema)
  - [General Envelope](#general-envelope)
  - [Response Envelope](#response-envelope)
- [Action Reference](#action-reference)
  - [SSD1306 Display Actions](#ssd1306-display-actions)
  - [GPIO / FTDI Actions](#gpio--ftdi-actions)
  - [Control Actions (any daemon type)](#control-actions-any-daemon-type)
- [Send-PsGadgetCommand Usage](#send-psgadgetcommand-usage)
- [Example Workflows](#example-workflows)
  - [Scenario 1: CPU Temperature Monitor on SSD1306](#scenario-1-cpu-temperature-monitor-on-ssd1306)
  - [Scenario 2: Alert Triggers RGB LED + Servo](#scenario-2-alert-triggers-rgb-led--servo)
  - [Scenario 3: Bash / Non-PowerShell Caller via File Drop](#scenario-3-bash--non-powershell-caller-via-file-drop)
  - [Scenario 4: Python Caller via Named Pipe](#scenario-4-python-caller-via-named-pipe)
- [Systemd Integration (Linux)](#systemd-integration-linux)
- [Security Considerations](#security-considerations)
- [Implementation Status](#implementation-status)
- [See Also](#see-also)

---

## SHORT DESCRIPTION

A **PsGadget Daemon** is a long-running background runspace that holds an open device
handle (FTDI, MicroPython serial, or .NET IoT) and accepts commands from external
callers via a named pipe or a file drop directory.

This pattern solves the core limitation of interactive PsGadget sessions: the FTDI or
serial connection lives inside a single PowerShell runspace. Once that terminal closes,
the handle is lost and the device must be reconnected. A daemon keeps the handle alive
indefinitely and exposes it to other processes.

---

## MOTIVATION

The following scenarios require a background-capable PsGadget:

- A cron job or scheduled task needs to update an SSD1306 display every 60 seconds
  without opening a new FTDI connection on every run.
- An alerting system (Grafana, Prometheus alertmanager, Ansible) needs to trigger a
  GPIO-wired RGB LED or servo motor in response to events.
- A non-PowerShell process (Python, bash, curl) needs to send display or GPIO commands
  without knowing anything about FTDI drivers or .NET assemblies.
- Multiple independent scripts need to share one physical device without handle conflicts.

---

## ARCHITECTURE OVERVIEW

```
+-----------------------------+
| Start-PsGadgetDaemon        |   <-- sysadmin runs this once; terminal can be closed
|  - opens device handle      |
|  - creates NamedPipe server |
|  - starts FileSystemWatcher |
|  - loops waiting for input  |
+-----------------------------+
           |
           |  named pipe:  \\.\pipe\psgadget-<name>  (Windows)
           |               /tmp/psgadget-<name>       (Linux)
           |
           |  file drop:   ~/.psgadget/commands/<name>/*.json
           |
+-----------------------------+    +-----------------------------+
| Send-PsGadgetCommand        |    | bash / Python / cron / curl |
|  (PS client, any session)   |    |  (writes .json drop file)   |
+-----------------------------+    +-----------------------------+
```

The daemon serializes all incoming requests to the device connection sequentially,
preventing concurrent access errors. The caller either receives a JSON ACK response
(named pipe) or reads a paired `.response` file (file drop).

---

## IPC MECHANISMS

### Named Pipe (preferred)

The named pipe provides bidirectional, synchronous request/response between any
process and the daemon. The client sends a JSON command object and receives a JSON
result object.

| Property | Value |
|----------|-------|
| Windows path | `\\.\pipe\psgadget-<name>` |
| Linux path | `/tmp/psgadget-<name>.sock` |
| Direction | Bidirectional |
| Response | Synchronous JSON |
| PS client | `Send-PsGadgetCommand` |
| Non-PS client | `System.IO.Pipes.NamedPipeClientStream` or `socat` |

### File Drop Directory (alternative)

Any process with filesystem access can drop a `.json` file into the daemon's watch
directory. The FileSystemWatcher fires on `Created`, processes the command, then
deletes or moves the file.

| Property | Value |
|----------|-------|
| Drop path | `~/.psgadget/commands/<name>/` |
| Response path | `~/.psgadget/commands/<name>/<filename>.response` |
| Direction | Unidirectional (fire-and-forget) or poll `.response` file |
| PS client | `Send-PsGadgetCommand -Method FileDrop` |
| Non-PS client | any process that can write a file |

---

## DAEMON LIFECYCLE

### Starting a Daemon

```powershell
# SSD1306 display on FTDI device index 0
Start-PsGadgetDaemon -Name "display" -DeviceIndex 0 -Type Ssd1306

# Servo + RGB LED on FTDI device index 1
Start-PsGadgetDaemon -Name "panel" -DeviceIndex 1 -Type Ftdi

# With file drop directory enabled
Start-PsGadgetDaemon -Name "display" -DeviceIndex 0 -Type Ssd1306 -EnableFileDrop
```

The daemon starts in a new PowerShell background runspace. The calling terminal is
free to exit. The daemon persists until stopped explicitly or until the host process
(pwsh.exe / pwsh) exits.

For permanent persistence across reboots, register the daemon as a systemd unit
(Linux) or Windows Service (see SYSTEMD INTEGRATION below).

### Stopping a Daemon

```powershell
Stop-PsGadgetDaemon -Name "display"
Stop-PsGadgetDaemon -Name "panel"
Stop-PsGadgetDaemon -All
```

Stop gracefully closes the device handle before terminating the runspace. This
prevents FTDI handle leaks that would require a physical USB reconnect to clear.

### Checking Status

```powershell
Get-PsGadgetDaemon              # list all running daemons
Get-PsGadgetDaemon -Name "display"

# Example output:
# Name     Type     Device  Pipe                    Started              Commands
# ----     ----     ------  ----                    -------              --------
# display  Ssd1306  0       /tmp/psgadget-display   2026-02-27 09:14:00  142
# panel    Ftdi     1       /tmp/psgadget-panel      2026-02-27 09:14:03  38
```

---

## COMMAND SCHEMA

Commands are JSON objects with a required `Action` field and action-specific
parameters. All field names are case-insensitive.

### General Envelope

```json
{
  "Action": "<action name>",
  "<param1>": "<value1>",
  "<param2>": "<value2>"
}
```

### Response Envelope

```json
{
  "Success": true,
  "Action": "<action name>",
  "Result": <any>,
  "Error": null
}
```

On failure, `Success` is `false` and `Error` contains the exception message.

---

## ACTION REFERENCE

### SSD1306 Display Actions

| Action | Parameters | Description |
|--------|-----------|-------------|
| `Write` | `Line` (0-7), `Text` (string) | Write text to a display line |
| `Clear` | *(none)* | Clear the entire display |
| `SetCursor` | `Page` (0-7), `Column` (0-127) | Move cursor to position |
| `WriteRaw` | `Data` (byte array) | Send raw page data |

```json
{ "Action": "Write",     "Line": 0, "Text": "CPU: 72 C"  }
{ "Action": "Write",     "Line": 1, "Text": "MEM: 4.2 GB" }
{ "Action": "Clear"                                        }
{ "Action": "SetCursor", "Page": 3, "Column": 0           }
```

### GPIO / FTDI Actions

| Action | Parameters | Description |
|--------|-----------|-------------|
| `SetGpio` | `Pin` (int), `State` (High/Low/0/1) | Set a GPIO pin state |
| `SetLed` | `R`, `G`, `B` (0-255) | Set RGB LED via three GPIO pins |
| `SetServo` | `Angle` (0-180) | Set servo position via PWM pin |
| `PulseGpio` | `Pin` (int), `DurationMs` (int) | Pulse a pin high for N ms |
| `ReadGpio` | `Pin` (int) | Read current pin state; returned in Result |

```json
{ "Action": "SetGpio",   "Pin": 3, "State": "High"   }
{ "Action": "SetLed",    "R": 255, "G": 0,   "B": 0  }
{ "Action": "SetServo",  "Angle": 90                  }
{ "Action": "PulseGpio", "Pin": 5, "DurationMs": 500  }
{ "Action": "ReadGpio",  "Pin": 2                     }
```

### Control Actions (any daemon type)

| Action | Parameters | Description |
|--------|-----------|-------------|
| `Ping` | *(none)* | Returns `"Pong"` - confirms daemon is alive |
| `Status` | *(none)* | Returns daemon status object |
| `Reconnect` | *(none)* | Close and reopen the device handle |
| `Shutdown` | *(none)* | Gracefully shut down the daemon |

---

## SEND-PSGADGETCOMMAND USAGE

```powershell
# Basic usage - result returned as a PS object
Send-PsGadgetCommand -Daemon "display" -Command @{
    Action = "Write"
    Line   = 0
    Text   = "Hello World"
}

# Fire-and-forget (no wait for response)
Send-PsGadgetCommand -Daemon "panel" -Command @{ Action="SetLed"; R=255; G=0; B=0 } -NoWait

# Via file drop
Send-PsGadgetCommand -Daemon "display" -Method FileDrop -Command @{
    Action = "Write"; Line = 2; Text = "File drop test"
}

# Confirm daemon is alive
Send-PsGadgetCommand -Daemon "display" -Command @{ Action = "Ping" }
# Result: Pong
```

---

## EXAMPLE WORKFLOWS

### Scenario 1: CPU Temperature Monitor on SSD1306

A cron job runs every 60 seconds and writes live system stats to the display.
The daemon started once at boot; cron just sends commands.

```powershell
# /etc/cron.d/psgadget-display  (runs as botmanager)
# * * * * * pwsh -NonInteractive -c ". /opt/psgadget/cron-display.ps1"

# cron-display.ps1
Import-Module PSGadget

$cpuTemp = (Get-Content /sys/class/thermal/thermal_zone0/temp) / 1000
$memFree = [math]::Round((Get-Content /proc/meminfo | Select-String MemAvailable)[0] -replace '\D','') / 1024

Send-PsGadgetCommand -Daemon "display" -Command @{ Action="Write"; Line=0; Text="CPU:  $cpuTemp C"  }
Send-PsGadgetCommand -Daemon "display" -Command @{ Action="Write"; Line=1; Text="MEM:  $memFree MB" }
```

### Scenario 2: Alert Triggers RGB LED + Servo

Grafana Alertmanager webhook or Prometheus rule calls a PS webhook receiver.
On ALERT state, the LED goes red and the servo swings to 90 degrees.

```powershell
# webhook-receiver.ps1 (runs as a simple HTTP listener)
Import-Module PSGadget

# ALERT fired
Send-PsGadgetCommand -Daemon "panel" -Command @{ Action="SetLed";   R=255; G=0; B=0 }
Send-PsGadgetCommand -Daemon "panel" -Command @{ Action="SetServo"; Angle=90         }

# RESOLVED
Send-PsGadgetCommand -Daemon "panel" -Command @{ Action="SetLed";   R=0; G=255; B=0 }
Send-PsGadgetCommand -Daemon "panel" -Command @{ Action="SetServo"; Angle=0          }
```

### Scenario 3: Bash / Non-PowerShell Caller via File Drop

No PowerShell knowledge required. Any process that can write a file can control
the device.

```bash
# Bash script, Python, Ansible shell module, etc.
echo '{"Action":"Write","Line":0,"Text":"DISK: 95% FULL"}' \
  > ~/.psgadget/commands/display/alert_disk.json

# Check response (optional)
sleep 0.2
cat ~/.psgadget/commands/display/alert_disk.json.response
# {"Success":true,"Action":"Write","Result":null,"Error":null}
```

### Scenario 4: Python Caller via Named Pipe

```python
import socket, json, os

def send_psgadget(daemon_name, command):
    pipe_path = f"/tmp/psgadget-{daemon_name}.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(pipe_path)
        s.sendall((json.dumps(command) + "\n").encode())
        response = s.recv(4096)
    return json.loads(response)

send_psgadget("display", {"Action": "Write", "Line": 3, "Text": "Python says hi"})
send_psgadget("panel",   {"Action": "SetLed", "R": 0, "G": 0, "B": 255})
```

---

## SYSTEMD INTEGRATION (Linux)

Register a daemon to start at boot and restart on failure.

```ini
# /etc/systemd/system/psgadget-display.service

[Unit]
Description=PSGadget Display Daemon (SSD1306 on /dev/bus/usb)
After=network.target

[Service]
Type=simple
User=botmanager
ExecStart=/usr/bin/pwsh -NonInteractive -c "Import-Module PSGadget; Start-PsGadgetDaemon -Name display -DeviceIndex 0 -Type Ssd1306 -Foreground"
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable psgadget-display
sudo systemctl start  psgadget-display
sudo systemctl status psgadget-display
```

Note the `-Foreground` flag on `Start-PsGadgetDaemon` - this prevents the function
from spawning a background runspace and instead blocks, which is what systemd expects
for `Type=simple`.

---

## SECURITY CONSIDERATIONS

| Concern | Recommendation |
|---------|---------------|
| Named pipe access | Pipe permissions are set to owner-only by default. On Linux, the socket file inherits standard file permissions. Restrict with `chmod 600`. |
| File drop directory | Set `~/.psgadget/commands/` to `chmod 700`. Only the daemon owner and trusted callers should write here. |
| Network exposure | The daemon only listens on local pipes/sockets by default. Do NOT expose the pipe or drop directory across a network share without additional authentication. |
| Command injection | The daemon validates `Action` against a whitelist before dispatching. Unknown actions return an error response and are not executed. |
| Shutdown via command | The `Shutdown` action is disabled by default. Enable with `-AllowRemoteShutdown` on `Start-PsGadgetDaemon`. |

---

## IMPLEMENTATION STATUS

> **Note:** As of v0.1.0, the daemon subsystem (`Start-PsGadgetDaemon`,
> `Stop-PsGadgetDaemon`, `Get-PsGadgetDaemon`, `Send-PsGadgetCommand`) is
> **planned but not yet implemented**. This document describes the intended design.
> The underlying device functions (`Write-PsGadgetSsd1306`, `Set-PsGadgetGpio`, etc.)
> are implemented and form the backend that the daemon will delegate to.

---

## SEE ALSO

- [Function Reference](wiki/Function-Reference.md)
- [Configuration Reference](about_PsGadgetConfig.md)
- [Example: SSD1306 Display](../examples/Example-Ssd1306.md)
- [Workflow Reference](../examples/psgadget_workflow.md)
- [PowerShell Runspaces (Microsoft Docs)](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.runspaces.runspace)
- [System.IO.Pipes.NamedPipeServerStream](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeserverstream)
- [System.IO.FileSystemWatcher](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher)
