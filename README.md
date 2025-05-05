# PsGadget

PsGadget is a .NETFramework PowerShell-based modular gadget framework built around the FT232H chip, bridging the gap between administration and electronic hardware.

This module enables users to interface with common electronic components through PowerShell - to create practical hardware tools that extend their capabilities beyond the standard workstation setup.

With PsGadget, admins can build custom monitoring displays, environmental sensors, physical notification systems, or automation controls using readily available hobbyist components, all programmed through familiar PowerShell commandlet -- turning ideas into tangible hardware solutions that make daily sysadmin work more interesting and fun.

![PsGadget_intro](img/psgadget_intro.png)

## Potential Hardware Configurations:

### PsGadget_Display (see: intro image)
Configuration for an I2C LED display (e.g. SSD1306 128×64)

### PsGadget_LED
Flash, blink, or define LED patterns using the FT232H ACBUS GPIO pins C0-C7

### PsGadget_DCMotor
Control a motor

### PsGadget_Sensor
Receive data from an I2C/SPI sensor module, or send commands if applicable

### PsGadget_Button
Configure one or more digital inputs (momentary, toggle, pull‑up/down, debounce) for push‑buttons and switches.

### PsGadget_Buzzer
Generate tones or simple melodies on a piezo buzzer or speaker

### PsGadget_UART
Raw UART bridge configuration on the FT232H’s UART engine—port name, baud, parity, stop bits, flow control, and buffer sizes.

### PsGadget_I2C
Generic I²C‑bus master configuration: clock/data pins, bus speed (e.g. 100 kHz, 400 kHz), acknowledgment handling, pull‑up requirements, and support for multiple device addresses.

### PsGadget_SPI
Generic SPI‑bus master setup for arbitrary devices: clock polarity/phase, bit order, clock speed, and multiple chip‑select lines.

### PsGadget_CAN
CAN‑bus interface through an external transceiver (e.g. MCP2551): bit rate, sample point, and TX/RX pin assignments.

### PsGadget_RTC
Real‑time clock module (e.g. DS3231) over I²C: device address, alarm thresholds, and time‑sync interval.

### PsGadget_RFID
Combine with RFID hardware to read RFID tags directly into PowerShell console for further processing and automation.

## PsGadget_ESP32  
Paired with an ESP32 board running your pre‑flashed MicroPython firmware, this configuration lets PsGadget issue high‐level commands over serial to tap into the ESP32’s rich feature set:

- **PortName** – e.g. `COM3` on Windows or `/dev/ttyUSB0` on Linux  
- **BaudRate** – e.g. `115200`  
- **ResetPin**, **BootPin** – FT232H ACBUS pins used to drive the ESP32’s EN and IO0 lines for hardware reset or entering the bootloader  
- **CommandTimeout**, **RetryCount** – serial‐transaction settings  

#### Networking  
- **WiFiMode** – `"Station"`, `"AP"`, or `"Station+AP"`  
- **SSID**, **Password** – credentials for STA or AP  
- **IPConfig** – static IP or DHCP  

#### ESP‑Now  
- **ESPNowPeers** – array of peer MAC addresses to which you’ll send/receive data  
- **Channel** – RF channel for ESP‑Now communication  

#### Bluetooth  
- **BluetoothMode** – `"BLE"` or `"Classic"`  
- **GATTServices** – list of service/characteristic UUIDs for BLE interactions  

#### PWM & GPIO  
- **PWMChannels** – hashtable of pin numbers mapped to `{ Frequency, DutyCycle }`  
- **DigitalPins** – list of GPIO pins you can drive or read, with pull‑up/down settings  

#### ADC & DAC  
- **ADCChannels** – list of ADC pin numbers and their attenuation (e.g. `11dB`)  
- **DACChannels** – list of DAC pin numbers for analog outputs  

#### Bus Bridging  
- **I2CBus** – map SDA/SCL pins if you want to proxy an I²C bus through the ESP32  
- **SPIBus** – map SCLK/MOSI/MISO/CS pins for SPI pass‑through  

#### Command Mapping  
- **FirmwareFunctionMap** – maps PsGadget commands to MicroPython RPC calls, e.g.:  
    ```powershell
  @{
    "SetLED"     = "led.on({pin},{r},{g},{b})"
    "ReadTemp"   = "sensor.read_temp()"
    "StartScan"  = "wifi.scan()"
    "SendESPNOW" = "espnow.send({mac},{data})"
  }
    ```

