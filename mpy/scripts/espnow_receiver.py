# espnow_receiver.py
# PsGadget ESP-NOW Receiver
#
# Role: Wired to the host via FT232H UART.
#       Broadcasts its MAC address over ESP-NOW so transmitters can find it.
#       Receives ESP-NOW packets from transmitters and forwards them over UART.
#       Persists a known_devices.txt registry of seen transmitter MACs.
#
# Deploy via PSGadget:
#   Install-PsGadgetMpyScript -SerialPort "COM4" -Role Receiver
#
# Boot output (machine-readable, do not change format):
#   PsGadget-Receiver:ready
#
# UART message format forwarded to host (newline-terminated):
#   <type>|<serial>|<machine>|<cpu_temp>|<battery>|<payload>\n

import network
import espnow
import ubinascii
import time
import uos
import json
from machine import Pin, UART

# ---------------------------------------------------------------------------
# Config loader -- reads /config.json from device flash, falls back to defaults
# ---------------------------------------------------------------------------
_DEFAULTS = {
    "uart_tx_pin":    5,
    "uart_rx_pin":    6,
    "uart_baud":      115200,
    "neopixel_pin":   21,
    "neopixel_count": 1,
    "broadcast_interval_ms": 100,
    "ctssid": "PsGadget-CT",
    "macfile": "known_devices.txt"
}

def load_config():
    cfg = dict(_DEFAULTS)
    try:
        with open("config.json", "r") as f:
            overrides = json.loads(f.read())
            cfg.update(overrides)
    except OSError:
        pass  # no config file, use defaults
    except Exception as e:
        print("config.json parse error:", e)
    return cfg

CFG = load_config()

# ---------------------------------------------------------------------------
# Hardware init
# ---------------------------------------------------------------------------
uart = UART(1,
            baudrate=CFG["uart_baud"],
            tx=Pin(CFG["uart_tx_pin"]),
            rx=Pin(CFG["uart_rx_pin"]))

# NeoPixel is optional -- gracefully skip if import fails or pin is -1
np = None
if CFG["neopixel_pin"] >= 0:
    try:
        import neopixel
        np = neopixel.NeoPixel(Pin(CFG["neopixel_pin"], Pin.OUT), CFG["neopixel_count"])
        np[0] = (0, 0, 0)
        np.write()
    except Exception:
        np = None

# ---------------------------------------------------------------------------
# ESP-NOW init
# ---------------------------------------------------------------------------
BROADCAST_MAC = b'\xFF\xFF\xFF\xFF\xFF\xFF'
CTSSID        = CFG["ctssid"]
MACFILE       = CFG["macfile"]

wlan = network.WLAN(network.STA_IF)
wlan.active(True)

en = espnow.ESPNow()
en.active(True)

try:
    en.add_peer(BROADCAST_MAC)
except Exception as e:
    print("add_peer broadcast failed:", e)

# ---------------------------------------------------------------------------
# Known-devices registry
# ---------------------------------------------------------------------------
def read_known_devices():
    devices = {}
    try:
        with open(MACFILE, "r") as f:
            for line in f:
                parts = line.strip().split("|")
                if len(parts) == 2:
                    devices[parts[0]] = parts[1]
    except OSError:
        pass
    return devices

def write_known_devices(devices):
    with open(MACFILE, "w") as f:
        for mac, ts in devices.items():
            f.write("{}|{}\n".format(mac, ts))

def update_known_device(mac_str):
    dt = time.localtime()
    ts = "{:04d}-{:02d}-{:02d}T{:02d}:{:02d}:{:02d}".format(*dt[:6])
    devices = read_known_devices()
    is_new = mac_str not in devices
    devices[mac_str] = ts
    write_known_devices(devices)
    if is_new:
        print("New device registered:", mac_str)

# ---------------------------------------------------------------------------
# NeoPixel helpers
# ---------------------------------------------------------------------------
def led_set(r, g, b):
    if np is not None:
        np[0] = (r, g, b)
        np.write()

def led_off():
    led_set(0, 0, 0)

def led_blink(r, g, b, duration_ms=200):
    led_set(r, g, b)
    time.sleep_ms(duration_ms)
    led_off()

# ---------------------------------------------------------------------------
# UART forward
# ---------------------------------------------------------------------------
def forward_to_host(raw_bytes):
    try:
        if not raw_bytes.endswith(b"\n"):
            raw_bytes = raw_bytes + b"\n"
        uart.write(raw_bytes)
    except Exception as e:
        print("UART forward failed:", e)

# ---------------------------------------------------------------------------
# Broadcast (lets transmitters discover this receiver)
# ---------------------------------------------------------------------------
def broadcast_presence():
    try:
        own_mac = ubinascii.hexlify(wlan.config("mac"), ":").decode()
        msg = "{}:{}".format(own_mac, CTSSID)
        en.send(BROADCAST_MAC, msg.encode("utf-8"))
    except Exception as e:
        print("Broadcast failed:", e)

# ---------------------------------------------------------------------------
# ESP-NOW receive callback
# ---------------------------------------------------------------------------
def espnow_callback(_):
    try:
        mac, raw = en.recv()
        if mac is None:
            return
        mac_str = ubinascii.hexlify(mac, ":").decode()
        decoded = raw.decode("utf-8")

        # Parse structured message: type|serial|machine|cputemp|battery|payload
        parts = decoded.split("|")
        if len(parts) >= 6:
            payload = parts[5]
            # NeoPixel command embedded in payload
            if payload.startswith("rgb("):
                try:
                    rgb = tuple(int(x) for x in payload[4:-1].split(","))
                    led_blink(*rgb)
                except Exception:
                    pass
            elif payload.startswith("neopixel("):
                try:
                    rgb = tuple(int(x) for x in payload[9:-1].split(","))
                    led_set(*rgb)
                except Exception:
                    pass
        else:
            # Short/unknown message -- still forward
            pass

        forward_to_host(raw)
        update_known_device(mac_str)

    except Exception as e:
        print("espnow_callback error:", e)

en.irq(espnow_callback)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
print("PsGadget-Receiver:ready")
print("UART baud={} tx={} rx={}".format(CFG["uart_baud"], CFG["uart_tx_pin"], CFG["uart_rx_pin"]))
print("Broadcast interval={}ms ctssid={}".format(CFG["broadcast_interval_ms"], CTSSID))

led_blink(0, 64, 0, 300)  # green flash = ready

while True:
    broadcast_presence()
    time.sleep_ms(CFG["broadcast_interval_ms"])
