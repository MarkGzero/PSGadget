# espnow_transmitter.py
# PsGadget ESP-NOW Transmitter
#
# Role: Untethered/battery-powered wireless node.
#       Listens for a PsGadget-Receiver broadcast to discover its MAC.
#       Sends periodic telemetry to the receiver over ESP-NOW.
#       No WiFi AP or router required.
#
# Deploy via PSGadget:
#   Install-PsGadgetMpyScript -SerialPort "COM5" -Role Transmitter
#
# Boot output (machine-readable, do not change format):
#   PsGadget-Transmitter:ready
#
# Telemetry message format sent to receiver:
#   PsGadget-IO|<serial>|<machine>|<cpu_temp_c>|<battery_pct>|<payload>

import network
import espnow
import ubinascii
import time
import esp32
import uos
import machine
import json
import urandom

# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------
_DEFAULTS = {
    "neopixel_pin":         39,
    "neopixel_power_pin":   38,
    "neopixel_count":       1,
    "send_interval_ms":     5000,
    "receiver_poll_ms":     500,
    "ctssid":               "PsGadget-CT",
    "gadget_type":          "PsGadget-IO",
    "payload":              "telemetry"
}

def load_config():
    cfg = dict(_DEFAULTS)
    try:
        with open("config.json", "r") as f:
            overrides = json.loads(f.read())
            cfg.update(overrides)
    except OSError:
        pass
    except Exception as e:
        print("config.json parse error:", e)
    return cfg

CFG = load_config()

# ---------------------------------------------------------------------------
# Hardware init
# ---------------------------------------------------------------------------
SERIAL_NUMBER = ubinascii.hexlify(machine.unique_id()).decode()
MACHINE_TYPE  = uos.uname().machine

# NeoPixel (optional)
np = None
if CFG["neopixel_pin"] >= 0:
    try:
        import neopixel
        if CFG["neopixel_power_pin"] >= 0:
            pwr = machine.Pin(CFG["neopixel_power_pin"], machine.Pin.OUT)
            pwr.value(1)
        np = neopixel.NeoPixel(machine.Pin(CFG["neopixel_pin"]), CFG["neopixel_count"])
        np[0] = (0, 0, 0)
        np.write()
    except Exception:
        np = None

# ---------------------------------------------------------------------------
# ESP-NOW init
# ---------------------------------------------------------------------------
BROADCAST_MAC = b'\xFF\xFF\xFF\xFF\xFF\xFF'
CTSSID        = CFG["ctssid"]

wlan = network.WLAN(network.STA_IF)
wlan.active(True)

en = espnow.ESPNow()
en.active(True)
en.add_peer(BROADCAST_MAC)

# ---------------------------------------------------------------------------
# NeoPixel helpers
# ---------------------------------------------------------------------------
def led_set(r, g, b):
    if np is not None:
        np[0] = (r, g, b)
        np.write()

def led_off():
    led_set(0, 0, 0)

def led_blink(r, g, b, duration_ms=150):
    led_set(r, g, b)
    time.sleep_ms(duration_ms)
    led_off()

# ---------------------------------------------------------------------------
# Battery placeholder (override with actual ADC read for your board)
# ---------------------------------------------------------------------------
def battery_percent():
    return 99

# ---------------------------------------------------------------------------
# Receiver discovery -- listens for PsGadget-CT broadcast, extracts MAC
# ---------------------------------------------------------------------------
def discover_receiver():
    print("Scanning for PsGadget-Receiver broadcast...")
    msg_flag = [False]

    def _irq(_):
        msg_flag[0] = True

    en.irq(_irq)

    while True:
        if msg_flag[0]:
            msg_flag[0] = False
            try:
                mac, data = en.recv()
                if mac is None:
                    continue
                decoded = data.decode("utf-8")
                if CTSSID in decoded:
                    mac_str = ubinascii.hexlify(mac, ":").decode()
                    print("Receiver found:", mac_str, "msg:", decoded)
                    try:
                        en.add_peer(mac)
                    except Exception:
                        pass  # already added
                    en.irq(None)
                    return mac
            except Exception as e:
                print("Discovery recv error:", e)
        time.sleep_ms(CFG["receiver_poll_ms"])

# ---------------------------------------------------------------------------
# Build and send telemetry
# ---------------------------------------------------------------------------
def send_telemetry(receiver_mac):
    try:
        cpu_temp = esp32.mcu_temperature()
        battery  = battery_percent()

        # Payload: configurable; include random neopixel color for visual demo
        r = urandom.getrandbits(7)  # keep brightness sane
        g = urandom.getrandbits(7)
        b = urandom.getrandbits(7)
        payload = CFG.get("payload", "rgb({},{},{})".format(r, g, b))
        if payload == "telemetry":
            payload = "rgb({},{},{})".format(r, g, b)

        msg = "{}|{}|{}|{}|{}|{}".format(
            CFG["gadget_type"],
            SERIAL_NUMBER,
            MACHINE_TYPE,
            cpu_temp,
            battery,
            payload
        )
        en.send(receiver_mac, msg.encode("utf-8"))
        led_blink(r, g, b)
        print("Sent:", msg)
    except Exception as e:
        print("send_telemetry error:", e)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
print("PsGadget-Transmitter:ready")
print("Serial:", SERIAL_NUMBER, "Machine:", MACHINE_TYPE)
print("Send interval={}ms ctssid={}".format(CFG["send_interval_ms"], CTSSID))

led_blink(0, 0, 64, 300)  # blue flash = ready

receiver_mac = discover_receiver()
print("Paired. Starting telemetry loop.")
led_blink(0, 64, 64, 300)  # cyan flash = paired

while True:
    send_telemetry(receiver_mac)
    time.sleep_ms(CFG["send_interval_ms"])
