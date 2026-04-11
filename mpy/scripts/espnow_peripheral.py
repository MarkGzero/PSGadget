# espnow_peripheral.py
# ESPNow Peripheral -- ESP32 DevKit V1 (COM26 / COM27)
# Built-in LED on GPIO2 (active HIGH)
#
# LED states:
#   Slow blink (100 ms on / 400 ms off) = searching for controller
#   3 rapid blinks                      = just paired
#   Solid ON                            = connected and idle
#   Blink sequence replay               = replaying pattern sent by controller
#
# Deploy:
#   mpremote connect COM26 fs cp espnow_peripheral.py :main.py + reset
#   mpremote connect COM27 fs cp espnow_peripheral.py :main.py + reset

import network
import espnow
import ubinascii
import time
from machine import Pin

CTSSID        = "PSGADGET-CTRL"
BROADCAST_MAC = b'\xFF\xFF\xFF\xFF\xFF\xFF'

# ---------------------------------------------------------------------------
# Hardware
# ---------------------------------------------------------------------------
_led = Pin(2, Pin.OUT)
_led.value(0)

def led_on():  _led.value(1)
def led_off(): _led.value(0)

def blink(count=1, on_ms=100, off_ms=100):
    for _ in range(count):
        led_on();  time.sleep_ms(on_ms)
        led_off(); time.sleep_ms(off_ms)

# ---------------------------------------------------------------------------
# ESPNow
# ---------------------------------------------------------------------------
wlan = network.WLAN(network.STA_IF)
wlan.active(True)

en = espnow.ESPNow()
en.active(True)
en.add_peer(BROADCAST_MAC)

MY_MAC = ubinascii.hexlify(wlan.config("mac"), ":").decode()

# ---------------------------------------------------------------------------
# Discovery -- blocks until the controller is found and HELLO acknowledged
# Uses a flag-only IRQ (no allocation) then reads in main thread
# ---------------------------------------------------------------------------
print("ESPNow-Peripheral:searching mac={}".format(MY_MAC))

_msg_ready = [False]

def _disco_irq(_):
    _msg_ready[0] = True

en.irq(_disco_irq)

ctrl_mac = None
while ctrl_mac is None:
    blink(1, 100, 400)               # slow blink while searching
    if _msg_ready[0]:
        _msg_ready[0] = False
        try:
            mac, data = en.recv()
            if mac and data:
                msg = data.decode("utf-8")
                if CTSSID in msg:
                    try:
                        en.add_peer(mac)
                    except Exception:
                        pass
                    en.send(mac, "HELLO:{}".format(MY_MAC).encode())
                    ctrl_mac = mac
                    print("Paired:", ubinascii.hexlify(mac, ":").decode())
        except Exception as e:
            print("Discovery error:", e)

blink(3, 80, 80)     # 3 rapid blinks = paired
led_on()             # solid ON = connected
print("ESPNow-Peripheral:connected")

# ---------------------------------------------------------------------------
# Main loop -- receive BLINK sequences from controller and replay them
# IRQ stores the raw payload; parsing + replay happens in main thread
# ---------------------------------------------------------------------------
_pending_data = [None]

def _main_irq(_):
    try:
        mac, data = en.recv()
        if mac and data and data.startswith(b"BLINK:"):
            _pending_data[0] = data      # only store BLINK messages
    except Exception:
        pass

en.irq(_main_irq)

while True:
    if _pending_data[0] is not None:
        data = _pending_data[0]
        _pending_data[0] = None
        try:
            msg = data.decode("utf-8")
            if msg.startswith("BLINK:"):
                seq = [int(x) for x in msg[6:].split(",")]
                print("Blink:", msg[6:])
                led_off()
                time.sleep_ms(100)
                for dur in seq:
                    led_on();  time.sleep_ms(dur)
                    led_off(); time.sleep_ms(100)
                led_on()        # return to solid
        except Exception:
            pass
    time.sleep_ms(20)
