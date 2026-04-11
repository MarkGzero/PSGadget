# espnow_controller.py
# ESPNow Controller/Hub -- Waveshare ESP32-S3-Zero (COM25)
# WS2812 NeoPixel on GPIO21
#
# LED:
#   Amber  = waiting for peers     (20, 10,  0)
#   Green  = 1 peer connected      ( 0, 30,  0)
#   Teal   = 2+ peers connected    ( 0, 20, 20)
#   Purple = flashes on blink send (30,  0, 30)
#
# Deploy:
#   mpremote connect COM25 fs cp espnow_controller.py :main.py + reset

import network
import espnow
import ubinascii
import time
import urandom
from machine import Pin
import neopixel

CTSSID        = "PSGADGET-CTRL"
BROADCAST_MAC = b'\xFF\xFF\xFF\xFF\xFF\xFF'

COL_WAITING = (20, 10,  0)
COL_1PEER   = ( 0, 30,  0)
COL_2PEERS  = ( 0, 20, 20)
COL_SEND    = (30,  0, 30)

# ---------------------------------------------------------------------------
# Hardware
# ---------------------------------------------------------------------------
np = neopixel.NeoPixel(Pin(21, Pin.OUT), 1)

def led(r, g, b):
    np[0] = (r, g, b)
    np.write()

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
# Peer tracking + receive queue
# peers: list of (mac_bytes, mac_str)
# _rx_queue: messages collected by IRQ, processed in main loop
# ---------------------------------------------------------------------------
peers    = []
_rx_queue = []

def _irq(_):
    try:
        mac, data = en.recv()
        if mac is None or data is None:
            return
        msg = data.decode("utf-8")
        if len(_rx_queue) < 8:
            _rx_queue.append((mac, msg))
    except Exception:
        pass

en.irq(_irq)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def peer_color():
    n = len(peers)
    if n >= 2:
        return COL_2PEERS
    if n == 1:
        return COL_1PEER
    return COL_WAITING

def random_blink_seq():
    count = (urandom.getrandbits(2) & 0x03) + 3      # 3–6 blinks
    durations = []
    for _ in range(count):
        durations.append(str((urandom.getrandbits(9) & 0x1FF) + 50))  # 50–561 ms
    return ",".join(durations)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
print("ESPNow-Controller:ready mac={}".format(MY_MAC))
led(*COL_WAITING)

last_broadcast  = time.ticks_ms()
last_blink_send = time.ticks_ms()

while True:
    now = time.ticks_ms()

    # Process messages queued by IRQ
    while _rx_queue:
        mac, msg = _rx_queue.pop(0)
        if msg.startswith("HELLO:"):
            mac_str = ubinascii.hexlify(mac, ":").decode()
            if not any(s == mac_str for _, s in peers):
                try:
                    en.add_peer(mac)
                except Exception:
                    pass
                peers.append((mac, mac_str))
                print("Peer joined: {} total={}".format(mac_str, len(peers)))
                led(*peer_color())

    # Broadcast presence every 100 ms so peripherals can find us
    if time.ticks_diff(now, last_broadcast) >= 100:
        try:
            en.send(BROADCAST_MAC, "{}:{}".format(CTSSID, MY_MAC).encode())
        except Exception:
            pass
        last_broadcast = now

    # Send a random blink sequence to every peer every 3 s
    if peers and time.ticks_diff(now, last_blink_send) >= 3000:
        seq = random_blink_seq()
        payload = "BLINK:{}".format(seq).encode()
        for mac_bytes, mac_str in peers:
            try:
                en.send(mac_bytes, payload)
            except Exception as e:
                print("Send error {}: {}".format(mac_str, e))
        led(*COL_SEND)
        time.sleep_ms(150)
        led(*peer_color())
        print("Blink seq -> {} peer(s): {}".format(len(peers), seq))
        last_blink_send = now

    time.sleep_ms(10)
