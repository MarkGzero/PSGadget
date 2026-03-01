# PsGadget MicroPython Scripts

MicroPython scripts deployed to ESP32 devices by PSGadget cmdlets.

## Scripts

| File | Role | Device | Wiring |
|------|------|--------|--------|
| `espnow_receiver.py` | Wireless gateway -- receives ESP-NOW, forwards over UART to FT232H | ESP32 wired to host | UART wired to FT232H |
| `espnow_transmitter.py` | Wireless node -- sends telemetry to receiver over ESP-NOW | ESP32, battery-powered | None required |
| `config.json` | Pin/baud overrides for both roles | Deployed alongside main.py | -- |

---

## Architecture

```
[PowerShell host]
      |
   (USB)
      |
  [FT232H]
      |
   (UART TX/RX)
      |
  [Receiver ESP32]  <--- ESP-NOW (no router, ~200m range) --->  [Transmitter ESP32(s)]
```

No WiFi access point or IP network required. ESP-NOW uses raw 802.11 frames.
Multiple transmitters can pair to one receiver.

---

## Deploy with PSGadget

```powershell
# Flash receiver role to an ESP32 connected via USB
Install-PsGadgetMpyScript -SerialPort "COM4"         -Role Receiver

# Flash transmitter role to another ESP32
Install-PsGadgetMpyScript -SerialPort "COM5"         -Role Transmitter

# Linux / macOS
Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB0" -Role Receiver
Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB1" -Role Transmitter

# After the receiver has been running, pull its known-devices registry
Get-PsGadgetEspNowDevices -SerialPort "COM4"
# Saved to: ~/.psgadget/known_devices.txt
# Returns:  [PSCustomObject]@{ Mac; LastSeen }[]
```

---

## Pin Maps

### Receiver default pins

| Function | GPIO | Notes |
|----------|------|-------|
| UART TX   | 5  | To FT232H RX (ACBUS or dedicated UART pin) |
| UART RX   | 6  | From FT232H TX |
| NeoPixel  | 21 | ESP32-S3 Zero onboard LED |

Compatible with: **ESP32-S3 Zero** (Waveshare), **generic ESP32-WROOM** (change pins in `config.json`).

### Transmitter default pins (ESP32-S3 Zero)

| Function | GPIO | Notes |
|----------|------|-------|
| NeoPixel power | 38 | Enable pin for onboard NeoPixel |
| NeoPixel data  | 39 | Onboard NeoPixel data |

No UART wiring required on the transmitter.

---

## Telemetry Message Format

Every packet the receiver forwards to the host over UART:

```
PsGadget-IO|<serial_hex>|<machine_string>|<cpu_temp_c>|<battery_pct>|<payload>\n
```

Example:
```
PsGadget-IO|a4cf1293fe84|ESP32S3|42|99|rgb(12,80,33)
```

---

## config.json Overrides

Deploy a custom `config.json` alongside `main.py` to change any pin or timing.
PSGadget pushes the bundled `config.json` automatically; pass `-ConfigPath` to override.

```powershell
Install-PsGadgetMpyScript -SerialPort "COM4" -Role Receiver -ConfigPath "./my_board.json"
```

Key fields (all optional -- missing keys use built-in defaults):

| Key | Default | Role | Description |
|-----|---------|------|-------------|
| `uart_tx_pin` | 5 | Receiver | UART TX GPIO |
| `uart_rx_pin` | 6 | Receiver | UART RX GPIO |
| `uart_baud` | 115200 | Receiver | UART baud rate |
| `neopixel_pin` | 21 | Receiver | NeoPixel GPIO (-1 to disable) |
| `broadcast_interval_ms` | 100 | Receiver | How often the receiver broadcasts its MAC |
| `neopixel_pin` | 39 | Transmitter | NeoPixel data GPIO (-1 to disable) |
| `neopixel_power_pin` | 38 | Transmitter | NeoPixel enable GPIO (-1 to skip) |
| `send_interval_ms` | 5000 | Transmitter | Telemetry send interval |
| `ctssid` | PsGadget-CT | Both | Rendezvous identifier; must match on both sides |
| `gadget_type` | PsGadget-IO | Transmitter | Device type string in telemetry |
| `payload` | telemetry | Transmitter | `telemetry` = auto RGB color; or a custom string |

---

## Boot Banners (machine-readable)

After flash and reset, confirm role with:

```powershell
$mpy = Connect-PsGadgetMpy -SerialPort "COM4"
$mpy.Invoke("import uos; print(uos.listdir())")
```

Or via mpremote directly:
```bash
mpremote connect COM4 run espnow_receiver.py
# Should print: PsGadget-Receiver:ready
```
