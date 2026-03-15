# Example: ESP-NOW Wireless Telemetry via FT232H UART

Receive live wireless telemetry from one or more untethered ESP32 nodes into a
PowerShell session -- no WiFi router, no IP addresses, no MQTT broker required.

---

## Table of Contents

- [Who This Is For](#who-this-is-for)
- [What You Need](#what-you-need)
- [Hardware Background](#hardware-background)
  - [Telemetry Frame Format](#telemetry-frame-format)
- [Architecture](#architecture)
- [Step 1 -- Wire the Receiver ESP32 to the FT232H](#step-1----wire-the-receiver-esp32-to-the-ft232h)
- [Step 2 -- Flash MicroPython (if not already on the boards)](#step-2----flash-micropython-if-not-already-on-the-boards)
- [Step 3 -- Deploy the Receiver script](#step-3----deploy-the-receiver-script)
- [Step 4 -- Deploy the Transmitter script](#step-4----deploy-the-transmitter-script)
- [Step 5 -- Confirm the receiver is running](#step-5----confirm-the-receiver-is-running)
- [Step 6 -- Read live telemetry in PowerShell](#step-6----read-live-telemetry-in-powershell)
- [Step 7 -- Pull the known-devices registry](#step-7----pull-the-known-devices-registry)
- [Troubleshooting](#troubleshooting)
- [Custom Config -- Multiple Transmitters](#custom-config----multiple-transmitters)
- [Quick Reference (Pro)](#quick-reference-pro)

---

## Who This Is For

- **Beginner** - new to wireless protocols, ESP32, and PowerShell
- **Scripter** - comfortable with PowerShell, new to ESP-NOW, UART, and embedded devices
- **Engineer** - familiar with 802.11 radio, UART, and ESP32; less familiar with PSGadget and mpremote
- **Pro** - experienced with all; skip to the Quick Reference at the bottom

---

## What You Need

**Hardware**
- 1x FT232H breakout board (Adafruit #2264 or CJMCU; wired to host via USB)
- 2x ESP32 boards (ESP32-S3 Zero recommended; any ESP32 with MicroPython works)
- 4 jumper wires (UART wiring between FT232H and Receiver ESP32)
- USB cables for initial flashing

**Software**
- PSGadget module (`Import-Module ./PSGadget.psd1`)
- MicroPython firmware on both ESP32 boards
- `mpremote` on PATH: `pip install mpremote`
- PowerShell 5.1 or 7.x

> **Beginner**: "Wireless" here means the transmitter ESP32 does not need a USB
> cable or WiFi password after you flash it. It uses a protocol called ESP-NOW,
> which lets ESP32 boards talk directly to each other over radio -- like a walkie
> talkie for microcontrollers. One board (the receiver) stays plugged into your
> PC via a USB adapter. The others can be battery-powered anywhere in the room.

> **Beginner**: MicroPython is a version of Python that runs on tiny microcontroller
> boards like the ESP32. You will not need to write any Python yourself -- PSGadget
> pushes pre-written scripts to the boards for you.

---

## Hardware Background

> **Engineer**: ESP-NOW operates over 802.11 raw frames in station mode
> (`network.STA_IF`). Devices never associate to an AP; they use the Wi-Fi radio
> purely for frame transmission. Maximum payload is 250 bytes per frame. The
> receiver broadcasts its MAC address at roughly 10 Hz; transmitters scan for that
> broadcast, cache the receiver MAC, and begin sending. Range is ~200 m LOS.
>
> The UART bridge is straightforward: the Receiver ESP32 has its UART1 TX/RX
> wired to the FT232H. The FT232H presents as a virtual COM port on the host.
> PSGadget reads that COM port via `System.IO.Ports.SerialPort`. No D2XX MPSSE
> or GPIO modes are used in this setup -- the FT232H is purely a UART-to-USB
> bridge here.

### Telemetry Frame Format

Every packet the receiver forwards to the host over UART:

```
PsGadget-IO|<serial_hex>|<machine_string>|<cpu_temp_c>|<battery_pct>|<payload>\n
```

Example:
```
PsGadget-IO|a4cf1293fe84|ESP32S3|42|99|rgb(12,80,33)
```

---

## Architecture

```
[PowerShell host]
      |
   (USB)
      |
  [FT232H]  <-- purely a UART-to-USB bridge here
      |
   (UART TX/RX, 115200 baud)
      |
  [Receiver ESP32]  <---  ESP-NOW (no router, ~200 m range)  --->  [Transmitter ESP32(s)]
```

> **Scripter**: Think of the Receiver ESP32 as a wireless gateway. It sits in the
> middle: one side talks to your PC through the FT232H USB cable, the other side
> talks to wireless transmitter nodes over radio. PowerShell only talks to the
> FT232H COM port -- the radio side is handled entirely by the MicroPython script.

---

## Step 1 -- Wire the Receiver ESP32 to the FT232H

Connect four wires between the FT232H and the Receiver ESP32:

| FT232H pin | ESP32 pin (default) | Signal |
|-----------|---------------------|--------|
| TX (TXD)  | GPIO 6 (RX)         | UART data to ESP32 |
| RX (RXD)  | GPIO 5 (TX)         | UART data from ESP32 |
| GND       | GND                 | Common ground |
| 3V3 (optional) | 3V3 (optional) | Power (use board USB instead if preferred) |

> **Beginner**: TX means "transmit" and RX means "receive." When wiring two
> devices together, TX on one side connects to RX on the other -- they cross over.
> GPIO 5 and GPIO 6 are the default pins in PSGadget's bundled config. These can
> be changed in `config.json` if your board has a different pinout.

> **Engineer**: GPIO 5/6 are UART1 on ESP32-S3. UART0 is reserved for the REPL
> (connected to the USB-serial bridge). Using UART1 avoids conflicts during
> normal operation. The FT232H's RX line expects 3.3 V logic -- compatible with
> all ESP32 I/O. No level shifter required.

---

## Step 2 -- Flash MicroPython (if not already on the boards)

Skip this step if your ESP32 boards already have MicroPython installed.

```bash
# Check if mpremote can see the board
mpremote connect /dev/ttyUSB0 exec "import sys; print(sys.version)"

# If needed, flash MicroPython from https://micropython.org/download/ESP32_GENERIC_S3/
python -m esptool --chip esp32s3 erase_flash
python -m esptool --chip esp32s3 write_flash 0 ESP32_GENERIC_S3-*.bin
```

> **Beginner**: If `mpremote` prints a Python version number, MicroPython is
> already installed and you can skip the flash commands. If it says "device not
> found", check that your USB cable supports data (some are charge-only).

---

## Step 3 -- Deploy the Receiver script

Plug the Receiver ESP32 into your PC via USB (separate from the FT232H connection
-- this USB cable is only needed for flashing; once deployed it can be unplugged).

```powershell
Import-Module ./PSGadget.psd1

# Deploy receiver role to the ESP32 on this serial port
Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB0" -Role Receiver

# Windows:
Install-PsGadgetMpyScript -SerialPort "COM4" -Role Receiver
```

Expected output:
```
VERBOSE: Deploying Receiver script to /dev/ttyUSB0
VERBOSE: main.py deployed from: .../mpy/scripts/espnow_receiver.py
VERBOSE: config.json deployed from: .../mpy/scripts/config.json
VERBOSE: Resetting device on /dev/ttyUSB0
VERBOSE: PsGadget-Receiver deployed to /dev/ttyUSB0. Device reset.
```

> **Scripter**: `Install-PsGadgetMpyScript` pushes two files to the ESP32 flash:
> `main.py` (the receiver logic) and `config.json` (pin and timing settings).
> MicroPython automatically runs `main.py` on every boot, so the receiver starts
> up as a wireless gateway immediately after reset -- without a USB cable attached.

> **Engineer**: The bundled `config.json` sets UART baud to 115200, UART TX=GPIO5,
> RX=GPIO6, NeoPixel on GPIO21, and broadcast interval to 100 ms. All values are
> overridable. Pass `-ConfigPath ./my_pins.json` to deploy a custom config.

---

## Step 4 -- Deploy the Transmitter script

Plug the second ESP32 into USB.

```powershell
Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB1" -Role Transmitter

# Windows:
Install-PsGadgetMpyScript -SerialPort "COM5" -Role Transmitter
```

Unplug that USB cable. The transmitter runs on battery from this point forward.

> **Beginner**: After flashing, the transmitter does not need a USB cable anymore.
> You can power it from a USB power bank, 3 AA batteries with a 3.3 V regulator,
> or any 3.3 V supply. It will find the receiver automatically when it powers on.

---

## Step 5 -- Confirm the receiver is running

Wire the FT232H to the Receiver ESP32 (Step 1 wiring), then plug the FT232H into
the PC. Open a serial connection to confirm the receiver is alive:

```powershell
# Find the FT232H COM port
Get-PsGadgetFtdi | Format-Table

# Connect and check receiver banner
$mpy = Connect-PsGadgetMpy -SerialPort "/dev/ttyUSB0"
# Expected: connects to the UART side of the Receiver ESP32

# Query device files (should show main.py, config.json, known_devices.txt)
$mpy.Invoke("import uos; print(uos.listdir())")
```

Or test with mpremote directly:
```bash
mpremote connect /dev/ttyUSB0 run mpy/scripts/espnow_receiver.py
# Output: PsGadget-Receiver:ready
```

---

## Step 6 -- Read live telemetry in PowerShell

```powershell
# Open the FT232H COM port that the Receiver ESP32 is wired to
$port = [System.IO.Ports.SerialPort]::new("/dev/ttyUSB0", 115200)
$port.ReadTimeout = 2000
$port.Open()

Write-Host "Listening for ESP-NOW telemetry... (Ctrl-C to stop)"
try {
    while ($true) {
        try {
            $line = $port.ReadLine().Trim()
            if ($line -match '^PsGadget-') {
                $fields = $line -split '\|'
                [PSCustomObject]@{
                    Type        = $fields[0]
                    Serial      = $fields[1]
                    Machine     = $fields[2]
                    CpuTemp_C   = [int]$fields[3]
                    Battery_Pct = [int]$fields[4]
                    Payload     = $fields[5]
                    Timestamp   = (Get-Date)
                }
            }
        } catch [System.TimeoutException] {
            # no data yet, keep waiting
        }
    }
} finally {
    $port.Close()
}
```

Example output:
```
Type        : PsGadget-IO
Serial      : a4cf1293fe84
Machine     : ESP32S3 module with ESP32S3
CpuTemp_C   : 43
Battery_Pct : 99
Payload     : rgb(12,80,33)
Timestamp   : 2026-03-01 14:22:07
```

> **Scripter**: The transmitter sends a packet every 5 seconds by default
> (configurable in `config.json` via `send_interval_ms`). Each packet contains
> the transmitter's unique serial number, so if you deploy multiple transmitters
> you can tell them apart in the pipeline by `$_.Serial`.

---

## Step 7 -- Pull the known-devices registry

After running for a while the receiver builds a log of every transmitter MAC it
has seen. Pull it to disk:

```powershell
$devices = Get-PsGadgetEspNowDevices -SerialPort "/dev/ttyUSB0"
$devices | Format-Table

# Mac                  LastSeen
# ---                  --------
# a4:cf:12:93:fe:84    2026-03-01T14:22:07
# 3c:e9:0e:7e:ab:12    2026-03-01T14:18:43
```

The file is also saved to `~/.psgadget/known_devices.txt` for offline reference.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `mpremote not found` | mpremote not installed | `pip install mpremote` |
| `main.py deployed` but no UART output | UART TX/RX wired backwards | Swap GPIO5 and GPIO6 wires |
| Receiver running, transmitter never pairs | Different `ctssid` on each device | Redeploy both with matching `config.json` |
| `known_devices.txt` pull says ENOENT | Receiver has not seen any transmitter yet | Wait for transmitter to power on and send at least one packet |
| Telemetry stops after a while | Transmitter lost receiver MAC (reboot) | Transmitter auto-rediscovers on next boot; power cycle transmitter |
| `Serial port not found` | Wrong port name | Run `Get-PsGadgetMpy` to see available ports |

> **Beginner**: If the receiver is running (green NeoPixel flash on boot) but you
> see no data in PowerShell, the most common cause is the TX/RX wires being
> swapped. Swap the two data wires between the FT232H and the ESP32 and try again.

---

## Custom Config -- Multiple Transmitters

Deploy different configs to give each transmitter a distinct `gadget_type` label:

```json
{
    "gadget_type": "PsGadget-TempSensor",
    "send_interval_ms": 10000,
    "payload": "telemetry"
}
```

```powershell
Install-PsGadgetMpyScript -SerialPort "COM6" -Role Transmitter -ConfigPath "./sensor_config.json"
```

---

## Quick Reference (Pro)

```powershell
# Deploy
Install-PsGadgetMpyScript -SerialPort <port> -Role Receiver    [-ConfigPath <path>] [-Force]
Install-PsGadgetMpyScript -SerialPort <port> -Role Transmitter [-ConfigPath <path>] [-Force]

# Pull known-devices registry from receiver
Get-PsGadgetEspNowDevices -SerialPort <port> [-OutputPath <path>]

# Live UART read (manual)
$port = [System.IO.Ports.SerialPort]::new(<port>, 115200)
$port.Open(); $port.ReadLine()   # one packet

# Parse telemetry frame
$line -split '\|' | Select-Object @{n='Type';e={$_[0]}}, @{n='Serial';e={$_[1]}}, ...
```

**Default pin assignments (espnow_receiver.py):**

| Signal | GPIO | Override key |
|--------|------|-------------|
| UART TX | 5 | `uart_tx_pin` |
| UART RX | 6 | `uart_rx_pin` |
| UART baud | 115200 | `uart_baud` |
| NeoPixel | 21 | `neopixel_pin` |
| Broadcast interval | 100 ms | `broadcast_interval_ms` |

**Default pin assignments (espnow_transmitter.py, ESP32-S3 Zero):**

| Signal | GPIO | Override key |
|--------|------|-------------|
| NeoPixel power | 38 | `neopixel_power_pin` |
| NeoPixel data  | 39 | `neopixel_pin` |
| Send interval  | 5000 ms | `send_interval_ms` |

See [mpy/README.md](../mpy/README.md) for full config key reference.
