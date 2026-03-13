# Adafruit FT232H Breakout — LLM Hardware Description (PsGadget Context)

## 1. Device Overview

The **Adafruit FT232H breakout** is a USB-to-multifunction interface board built around the **FTDI FT232H** chip.

Primary purpose: allow a **host computer to directly control hardware buses** such as:

* UART
* GPIO
* SPI
* I2C
* JTAG
* Parallel FIFO

Communication occurs over **USB 2.0 High-Speed (480 Mbps)** using the **FTDI D2XX driver** or VCP driver.

For **PsGadget**, the board is used in **D2XX mode with MPSSE enabled** to allow PowerShell to control digital pins and serial buses.

---

# 2. FT232H Core Architecture

The FT232H chip exposes **two digital I/O buses**:

| Bus       | Width  | Typical Use                     |
| --------- | ------ | ------------------------------- |
| **ADBUS** | 8 bits | MPSSE interfaces (SPI/I2C/JTAG) |
| **ACBUS** | 8 bits | GPIO or auxiliary signals       |

Each pin can be configured as:

* Input
* Output
* Alternate peripheral function

The chip includes an internal **MPSSE (Multi-Protocol Synchronous Serial Engine)** which can generate protocol signals without CPU timing.

---

# 3. Board Power System

### USB Input

The board is powered from USB.

```
USB-C → FT232H → onboard regulators
```

### Power rails available on header

| Pin | Voltage               | Notes           |
| --- | --------------------- | --------------- |
| 5V  | USB voltage           | direct from USB |
| 3V  | 3.3V regulator output | up to ~500 mA   |
| GND | ground                | reference       |

The **FT232H I/O voltage is 3.3V**, but pins are **5V tolerant**.

---

# 4. Physical Board Connectors

## USB

```
USB-C → FT232H USB controller
```

Used for:

* device enumeration
* D2XX driver communication
* power

---

## STEMMA QT / Qwiic connector

Provides **plug-and-play I2C** connection.

Pins internally wired to:

```
SDA → D1
SCL → D0
3V
GND
```

Used primarily for sensors and small displays.

---

## I2C Mode Switch

Newer board revision includes a switch that **connects D1 and D2** to simplify I2C wiring.

Purpose:

```
Enable simple I2C wiring without external pullups
```

---

# 5. Digital Pin Header

The breakout exposes FT232H pins as a **header row**.

## ADBUS pins (primary bus)

| FT232H Pin | Header Label | Typical Function |
| ---------- | ------------ | ---------------- |
| ADBUS0     | D0           | SCL / SPI CLK    |
| ADBUS1     | D1           | SDA / MOSI       |
| ADBUS2     | D2           | MISO             |
| ADBUS3     | D3           | CS               |
| ADBUS4     | D4           | GPIO             |
| ADBUS5     | D5           | GPIO             |
| ADBUS6     | D6           | GPIO             |
| ADBUS7     | D7           | GPIO             |

These are the **most important pins for PsGadget**.

### Typical MPSSE mapping

| Protocol | Pins                            |
| -------- | ------------------------------- |
| I2C      | D0 (SCL), D1 (SDA)              |
| SPI      | D0 CLK, D1 MOSI, D2 MISO, D3 CS |
| GPIO     | D4–D7                           |

---

## ACBUS pins (secondary bus)

| FT232H Pin | Header Label | Use                |
| ---------- | ------------ | ------------------ |
| ACBUS0     | C0           | GPIO               |
| ACBUS1     | C1           | GPIO               |
| ACBUS2     | C2           | GPIO               |
| ACBUS3     | C3           | GPIO               |
| ACBUS4     | C4           | optional functions |
| ACBUS5     | C5           | optional functions |
| ACBUS6     | C6           | optional functions |
| ACBUS7     | C7           | optional functions |

Common use:

```
status LEDs
GPIO outputs
control lines
```

In **PsGadget design**, these are often used for:

```
ACBUS → GPIO outputs
ADBUS → protocol bus
```

---

# 6. UART Interface

The FT232H also supports standard UART.

Pins:

| Signal | Pin |
| ------ | --- |
| TX     | D1  |
| RX     | D2  |

However, **when MPSSE is active these pins are used for SPI/I2C**.

PsGadget typically uses **separate FT232 devices or dynamic configuration**.

---

# 7. MPSSE (Multi-Protocol Serial Engine)

The **MPSSE hardware engine** is the key feature for PsGadget.

Capabilities:

```
hardware clock generation
serial protocol shifting
bit-level GPIO control
```

Protocols supported:

```
SPI
I2C
JTAG
custom synchronous protocols
```

The host communicates with MPSSE using **command bytes over USB**.

Example commands:

```
0x80 → set GPIO state
0x86 → set clock divisor
0x11 → clock data out
```

These commands are sent via **FT_Write()** in the D2XX API.

---

# 8. GPIO Behavior

GPIO is controlled using the **MPSSE command processor**.

Typical GPIO command:

```
0x80
<value byte>
<direction byte>
```

Example:

```
Value:      0b00010000
Direction:  0b11110000
```

Meaning:

```
D4 = HIGH
D5-D7 = outputs
D0-D3 = inputs
```

---

# 9. EEPROM Configuration

FT232H includes internal EEPROM.

Used to configure:

* device name
* serial number
* CBUS functions
* driver mode

Configured using **FT_PROG**.

Typical PsGadget configuration:

```
UART enabled
CBUS LEDs for RX/TX
unique serial number
```

---

# 10. PsGadget Recommended Pin Strategy

For PowerShell hardware control:

### ADBUS

```
D0 → I2C SCL
D1 → I2C SDA
D2 → optional GPIO
D3 → optional CS
D4-D7 → general GPIO
```

### ACBUS

```
C0-C3 → output GPIO
C4-C7 → status signals
```

### UART

Optional connection to:

```
ESP32-S3
microcontrollers
debug ports
```

---

# 11. Electrical Characteristics

| Property       | Value       |
| -------------- | ----------- |
| USB Speed      | 480 Mbps    |
| IO voltage     | 3.3V        |
| IO tolerance   | 5V tolerant |
| Max GPIO drive | ~16 mA      |
| 3.3V regulator | ~500 mA     |

---

# 12. Example Hardware Use Cases

Typical PsGadget demonstrations:

### I2C sensor interface

```
FT232H → SSD1306 OLED
FT232H → INA219 power sensor
```

---

### Servo control

```
FT232H → PCA9685 → servo motors
```

---

### UART bridge

```
FT232H → ESP32-S3
```

Used for:

```
NeoPixel control
WiFi
sensor aggregation
```

---

# 13. Internal Data Flow

```
PowerShell
  ↓
FTD2XX_NET.dll
  ↓
D2XX driver
  ↓
USB packets
  ↓
FT232H
  ↓
MPSSE command processor
  ↓
ADBUS / ACBUS pins
  ↓
external hardware
```

---

# 14. Important Constraints

### Only one mode active

The chip cannot simultaneously run:

```
UART
MPSSE
FIFO
```

You must select the mode with:

```
FT_SetBitMode()
```

Common modes:

```
0x00 → reset
0x01 → async bitbang
0x02 → MPSSE
```

---

# 15. PsGadget Design Philosophy

Typical architecture:

```
FT232H
   │
   ├─ I2C → sensors / OLED
   ├─ GPIO → LEDs / buttons
   ├─ UART → ESP32 helper MCU
   └─ SPI → displays / DAC
```

PowerShell becomes the **host-side firmware** controlling hardware dynamically.

