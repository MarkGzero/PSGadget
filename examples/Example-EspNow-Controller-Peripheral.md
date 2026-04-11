# Example: ESP-NOW Controller / Peripheral Blink Sync

Three ESP32 boards communicate wirelessly over ESP-NOW with zero infrastructure —
no WiFi router, no IP addresses, no broker. A Waveshare ESP32-S3-Zero acts as the
**controller**: it changes its NeoPixel colour as peers join and broadcasts a random
blink sequence every 3 seconds. Two ESP32 DevKit V1 boards act as **peripherals**:
they discover the controller, pair, then replay the identical blink pattern on their
on-board LED — proving the wireless link is live.

---

## Table of Contents

- [Hardware Used](#hardware-used)
- [Architecture](#architecture)
- [Protocol Design](#protocol-design)
- [What We Learned](#what-we-learned)
  - [Lesson 1 — Native USB CDC boards may need reflashing](#lesson-1--native-usb-cdc-boards-may-need-reflashing)
  - [Lesson 2 — MicroPython ESPNow: broadcast peers vs unicast peers](#lesson-2--micropython-espnow-broadcast-peers-vs-unicast-peers)
  - [Lesson 3 — IRQ single-slot receive buffer gets overwritten by high-frequency broadcasts](#lesson-3--irq-single-slot-receive-buffer-gets-overwritten-by-high-frequency-broadcasts)
  - [Lesson 4 — mpremote exec interrupts main.py; use serial monitoring for live inspection](#lesson-4--mpremote-exec-interrupts-mainpy-use-serial-monitoring-for-live-inspection)
  - [Lesson 5 — esptool can reach the ESP32-S3 ROM even when MicroPython is unreachable](#lesson-5--esptool-can-reach-the-esp32-s3-rom-even-when-micropython-is-unreachable)
- [Quick Start](#quick-start)
- [Script: espnow_controller.py](#script-espnow_controllerpy)
- [Script: espnow_peripheral.py](#script-espnow_peripheralpy)
- [Demo Script](#demo-script)
- [LED Reference](#led-reference)
- [Troubleshooting](#troubleshooting)

---

## Hardware Used

| Board | Role | LED | Tested Port |
|-------|------|-----|-------------|
| Waveshare ESP32-S3-Zero | Controller / hub | WS2812 NeoPixel on GPIO21 | COM28 |
| ESP32 DevKit V1 (×2) | Peripheral | Blue LED on GPIO2 (active HIGH) | COM26, COM27 |

**MicroPython versions:**
- Waveshare (ESP32-S3): `1.28.0` — `Espressif • ESP32-S3` from [micropython.org](https://micropython.org/download/ESP32_GENERIC_S3/)
- DevKit V1 (ESP32): any recent MicroPython with `espnow` module (tested with 1.23+)

---

## Architecture

```
  [Waveshare ESP32-S3-Zero]  ←── USB (mpremote / monitoring)
         CONTROLLER
         NeoPixel GPIO21
              |
              |  ESP-NOW  (802.11 raw frames, no AP, ~200 m LOS)
              |
    ┌─────────┴──────────┐
    ▼                    ▼
[ESP32 DevKit V1]   [ESP32 DevKit V1]
  PERIPHERAL           PERIPHERAL
  LED GPIO2            LED GPIO2
  COM26                COM27
```

No wires between boards after initial USB deployment. All communication is wireless.

---

## Protocol Design

### Discovery (one-time at boot)

1. **Controller** broadcasts `PSGADGET-CTRL:<own_mac>` to `FF:FF:FF:FF:FF:FF` every 100 ms
2. **Peripheral** listens for any packet containing the `PSGADGET-CTRL` string
3. **Peripheral** extracts the sender MAC from `en.recv()` (this IS the controller's MAC)
4. **Peripheral** calls `en.add_peer(ctrl_mac)` then sends unicast `HELLO:<own_mac>` to controller
5. **Controller** IRQ receives `HELLO:`, calls `en.add_peer(peer_mac)`, appends to peers list
6. NeoPixel updates: amber → green (1 peer) → teal (2+ peers)

### Blink Sync (recurring, every 3 s while peers exist)

1. Controller generates a random comma-separated sequence of 3–6 durations (50–561 ms each)
2. Sends `BLINK:<seq>` **unicast** to each registered peer MAC
3. Controller flashes NeoPixel purple briefly, then returns to peer-count colour
4. Each peripheral receives `BLINK:`, parses durations, replays on GPIO2 LED
5. Both peripherals execute the **same** sequence → visually proves the link

---

## What We Learned

### Lesson 1 — Native USB CDC boards may need reflashing

The Waveshare ESP32-S3-Zero uses the ESP32-S3's native USB peripheral (VID `303a`,
PID varies). Before this session, the board had third-party firmware installed
that printed `[WiFi] Failed to connect to WiFi!` on every boot. `mpremote` reported
"could not enter raw repl" with no error detail.

**Diagnosis:** open the serial port with Python `pyserial` directly and look for any
output without sending anything. If you see non-REPL text, the board is not running
MicroPython.

**Fix:** reflash MicroPython via Thonny (`Interpreter → Install MicroPython`). After
reflash, the board may appear on a **different COM port** because the new firmware
uses a different USB PID. Run `mpremote connect list` again to find it.

```
# Before reflash
COM25  303a:1001  (old firmware, no REPL)

# After reflash with MicroPython 1.28.0
COM28  303a:4001  (new MicroPython, fully usable)
```

### Lesson 2 — MicroPython ESPNow: broadcast peers vs unicast peers

`en.add_peer(BROADCAST_MAC)` (where `BROADCAST_MAC = b'\xFF\xFF\xFF\xFF\xFF\xFF'`)
must be called on **both sides** before either side can send or receive broadcast
packets. Calling `en.add_peer()` for the broadcast address enables both sending
broadcasts and receiving them.

For unicast after discovery:
- Peripheral adds controller MAC → can receive unicast from controller
- Controller adds peripheral MAC → can send unicast to peripheral

### Lesson 3 — IRQ single-slot receive buffer gets overwritten by high-frequency broadcasts

**This was the main functional bug.** The controller broadcasts its presence every
100 ms. After pairing, the peripheral's IRQ handler stored the most recent received
packet in a single variable (`_pending_data[0]`). The main loop checks that variable
every 20 ms.

Because the controller's presence broadcasts arrive every 100 ms, a `BLINK:` packet
was almost always overwritten by a presence broadcast before the 20 ms main loop
could read it.

**The fix:** filter in the IRQ handler. Only store the packet if it starts with `b"BLINK:"`.
Presence broadcasts are discarded at IRQ time and never reach the main loop.

```python
# WRONG — presence broadcasts silently overwrite BLINK packets
def _main_irq(_):
    mac, data = en.recv()
    if mac and data:
        _pending_data[0] = data          # any packet overwrites!

# CORRECT — only keep messages we care about
def _main_irq(_):
    mac, data = en.recv()
    if mac and data and data.startswith(b"BLINK:"):
        _pending_data[0] = data          # presence broadcasts discarded
```

**General rule:** when a high-frequency background signal and a low-frequency action
signal share the same channel, filter as early as possible — ideally in the ISR.

### Lesson 4 — mpremote exec interrupts main.py; use serial monitoring for live inspection

Running `mpremote connect <port> exec "..."` sends Ctrl-C to the board, which
**stops main.py**. Using exec to inspect a running script's state is not possible
this way.

**Instead:** open the serial port with `pyserial` (DTR=True) and just read lines.
`main.py` output goes to the USB CDC UART and is visible without interrupting
execution. This is how the bug in Lesson 3 was confirmed — the controller printed
`Blink seq -> 2 peer(s): ...` every 3 seconds, but the peripherals printed nothing
after `ESPNow-Peripheral:connected`.

```python
import serial, time
p = serial.Serial('COM28', 115200, timeout=0.1)
p.dtr = True
end = time.time() + 15
while time.time() < end:
    line = p.readline()
    if line: print(repr(line))
p.close()
```

### Lesson 5 — esptool can reach the ESP32-S3 ROM even when MicroPython is unreachable

When `mpremote` cannot enter raw REPL, `esptool` may still work via the ESP32-S3's
built-in USB-Serial/JTAG peripheral (the ROM bootloader). This is useful for:
- Confirming the chip is alive and reading its MAC
- Erasing the filesystem or flashing new firmware
- Hard-resetting the board (`esptool run`)

```bash
python -m esptool --port COM25 chip-id     # confirm chip is present
python -m esptool --port COM25 run         # hard reset, triggers MicroPython boot
```

---

## Quick Start

```bash
# 1. Reflash MicroPython on the Waveshare if needed (use Thonny or esptool)
# 2. Find the new COM port
mpremote connect list

# 3. Deploy — adjust port names to match your system
mpremote connect COM28 fs cp mpy/scripts/espnow_controller.py :main.py + reset
mpremote connect COM26 fs cp mpy/scripts/espnow_peripheral.py :main.py + reset
mpremote connect COM27 fs cp mpy/scripts/espnow_peripheral.py :main.py + reset

# 4. Watch the controller output live
python -c "
import serial, time
p = serial.Serial('COM28', 115200, timeout=0.1); p.dtr = True
end = time.time() + 30
while time.time() < end:
    l = p.readline()
    if l: print(l.decode().strip())
p.close()
"
```

Expected controller output:
```
ESPNow-Controller:ready mac=34:b7:da:5b:83:38
Peer joined: ac:15:18:d8:af:98 total=1
Peer joined: 88:13:bf:62:ad:ac total=2
Blink seq -> 2 peer(s): 412,273,467,376,290
Blink seq -> 2 peer(s): 539,171,525,450,428,421
```

Expected peripheral output:
```
ESPNow-Peripheral:searching mac=ac:15:18:d8:af:98
Paired: 34:b7:da:5b:83:38
ESPNow-Peripheral:connected
Blink: 412,273,467,376,290
Blink: 539,171,525,450,428,421
```

---

## Script: espnow_controller.py

Deploy to the Waveshare ESP32-S3-Zero (NeoPixel on GPIO21).

```python
# espnow_controller.py
# ESPNow Controller/Hub -- Waveshare ESP32-S3-Zero
# WS2812 NeoPixel on GPIO21
#
# LED:
#   Amber  = waiting for peers     (20, 10,  0)
#   Green  = 1 peer connected      ( 0, 30,  0)
#   Teal   = 2+ peers connected    ( 0, 20, 20)
#   Purple = flashes on blink send (30,  0, 30)
#
# Deploy:
#   mpremote connect COM28 fs cp espnow_controller.py :main.py + reset

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
peers     = []
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
    count = (urandom.getrandbits(2) & 0x03) + 3      # 3-6 blinks
    durations = []
    for _ in range(count):
        durations.append(str((urandom.getrandbits(9) & 0x1FF) + 50))  # 50-561 ms
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
```

---

## Script: espnow_peripheral.py

Deploy to each ESP32 DevKit V1 (built-in LED on GPIO2).

```python
# espnow_peripheral.py
# ESPNow Peripheral -- ESP32 DevKit V1
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
# Discovery -- blocks until the controller is found and HELLO sent
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
#
# KEY LESSON: filter in the IRQ -- only store BLINK messages.
# The controller broadcasts presence every 100 ms; without this filter
# those broadcasts silently overwrite BLINK payloads in the single-slot
# buffer before the 20 ms main loop can read them.
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
```

---

## Demo Script

See [`Demo-EspNow-BlinkSync.ps1`](Demo-EspNow-BlinkSync.ps1) in this folder.

---

## LED Reference

### Controller (Waveshare NeoPixel)

| Colour | Meaning |
|--------|---------|
| Amber `(20,10,0)` | Waiting — no peers connected |
| Green `(0,30,0)` | 1 peripheral connected |
| Teal `(0,20,20)` | 2+ peripherals connected |
| Purple flash `(30,0,30)` | Blink sequence being sent |

### Peripheral (ESP32 DevKit GPIO2 blue LED)

| Pattern | Meaning |
|---------|---------|
| Slow blink (100 ms / 400 ms) | Searching for controller |
| 3 rapid blinks | Just paired |
| Solid ON | Connected and idle |
| Random on/off sequence | Replaying blink sequence from controller |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `mpremote` says "could not enter raw repl" | Board has non-MicroPython firmware | Reflash MicroPython via Thonny; board may get a new COM port after reflash |
| Board shows up on a different COM port after reflash | New firmware uses a different USB PID | Run `mpremote connect list` to find the new port |
| Controller stays amber, peripherals slow-blink forever | CTSSID mismatch or boards not in range | Verify all scripts use `PSGADGET-CTRL`; boards should be within a few metres |
| Peripherals pair (solid LED) but never show blink replay | IRQ overwrite bug — presence broadcasts overwrote BLINK | Ensure `_main_irq` filters on `data.startswith(b"BLINK:")` |
| `en.add_peer()` raises an exception | Peer already registered | Wrap in `try/except` — duplicate add is safe to ignore |
| `mpremote exec` stops the running script | By design — exec sends Ctrl-C first | Use `pyserial` to read serial output without interrupting |
