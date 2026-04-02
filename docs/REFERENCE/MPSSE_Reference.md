# MPSSE Command Reference

> Source: FTDI AN_108 (Command Processor for MPSSE and MCU Host Bus Emulation Modes)  
> DS_FT232H (FT232H Single Channel Hi-Speed USB to Multipurpose UART/FIFO IC Datasheet)  
> Cross-reference: [docs/wiki/Architecture.md](../wiki/Architecture.md) — Performance Tiers section

## Table of Contents

- [1. Pin Reference](#1-pin-reference)
- [2. Command Byte Decoder](#2-command-byte-decoder)
- [3. Clock Configuration](#3-clock-configuration)
- [4. GPIO Commands](#4-gpio-commands)
- [5. Setup and Control Commands](#5-setup-and-control-commands)
- [6. Data Shifting — Output Only](#6-data-shifting--output-only)
- [7. Data Shifting — Input Only](#7-data-shifting--input-only)
- [8. Data Shifting — Bidirectional](#8-data-shifting--bidirectional)
- [9. TMS Commands (JTAG)](#9-tms-commands-jtag)
- [10. Wait and Clock-Without-Data Commands](#10-wait-and-clock-without-data-commands)
- [11. CPU Bus Emulation Commands](#11-cpu-bus-emulation-commands)
- [12. I2C Byte Sequences (Annotated)](#12-i2c-byte-sequences-annotated)
- [13. SPI Byte Sequences (Annotated)](#13-spi-byte-sequences-annotated)
- [14. Error Response](#14-error-response)
- [15. PsGadget Module Usage Cross-Reference](#15-psgadget-module-usage-cross-reference)

---

## Overview

The MPSSE (Multi-Protocol Synchronous Serial Engine) is a hardware command processor
built into FT232H, FT2232H, and FT4232H chips. The host writes raw byte sequences over
USB using FT_Write() (D2XX API). The chip executes each command synchronously in silicon
— no CPU timing loop required on the host side.

All commands are sent as a flat byte array. Multi-byte commands consume their argument
bytes immediately. Unrecognized commands return the bad command response (section 14).

Commands are sent via:

```powershell
$dev._connection.Device.Write([ref]$buf, $buf.Length, [ref]$written)
```

[return to ToC](#table-of-contents)

## 1. Pin Reference

### 1.1 ADBUS — Low Byte (primary protocol bus)

| Signal  | FT232H Pin | Adafruit Label | MPSSE Function               | Default Direction |
|-|-|-|-|-|
| ADBUS0  | 13        | D0             | TCK / SCK / SCL              | Output            |
| ADBUS1  | 14        | D1             | TDI / MOSI / SDA             | Output            |
| ADBUS2  | 15        | D2             | TDO / MISO                   | Input             |
| ADBUS3  | 16        | D3             | TMS / CS                     | Output            |
| ADBUS4  | 17        | D4             | GPIOL0 (general purpose I/O) | Input (tristate)  |
| ADBUS5  | 18        | D5             | GPIOL1 (general purpose I/O) | Input (tristate)  |
| ADBUS6  | 19        | D6             | GPIOL2 (general purpose I/O) | Input (tristate)  |
| ADBUS7  | 20        | D7             | GPIOL3 (general purpose I/O) | Input (tristate)  |

ADBUS is controlled by commands 0x80 (write low byte) and 0x81 (read low byte).

### 1.2 ACBUS — High Byte (secondary GPIO bus)

| Signal  | FT232H Pin | Adafruit Label | MPSSE Function               | Default            |
|-|-|-|-|-|
| ACBUS0  | 21        | C0             | GPIOH0                       | Tristate + pull-up |
| ACBUS1  | 25        | C1             | GPIOH1                       | Tristate + pull-up |
| ACBUS2  | 26        | C2             | GPIOH2                       | Tristate + pull-up |
| ACBUS3  | 27        | C3             | GPIOH3                       | Tristate + pull-up |
| ACBUS4  | 28        | C4             | GPIOH4 / SIWU#               | Tristate + pull-up |
| ACBUS5  | 29        | C5             | GPIOH5 / CLKOUT              | Tristate + pull-up |
| ACBUS6  | 30        | C6             | GPIOH6 / OE#                 | Tristate + pull-up |
| ACBUS7  | 31        | C7             | GPIOH7 / PWRSAV#             | Tristate + pull-DOWN |
| ACBUS8  | 32        | (not broken out on Adafruit) | GPIOH8      | Tristate + pull-up |
| ACBUS9  | 33        | (not broken out on Adafruit) | GPIOH9      | Tristate + pull-up |

ACBUS is controlled by commands 0x82 (write high byte) and 0x83 (read high byte).

> **Note:** ACBUS7 defaults to pull-DOWN (not pull-up like the rest). It is also
> configurable as PWRSAV# via EEPROM. Do not assume high-impedance high state on C7.

### 1.3 I2C Pin Assignment (PsGadget default)

```text
D0 (ADBUS0) = SCL    (clock, open-drain output)
D1 (ADBUS1) = SDA    (data, open-drain bidirectional)
D2 (ADBUS2) = SDA    (connected to D1 via I2C mode switch on Adafruit board)
```

The direction byte for I2C idle: `0x03` (D0 and D1 are outputs; D2-D7 are inputs).

[return to ToC](#table-of-contents)

## 2. Command Byte Decoder

For data shifting commands (opcodes 0x10–0x3F), the single command byte encodes
all options. Each bit selects a behavioral flag:

```text
Bit 7  Bit 6  Bit 5  Bit 4  Bit 3  Bit 2  Bit 1  Bit 0
  0      0      1      ?      ?      ?      ?      ?
  |      |      |      |      |      |      |      |
  |      |      |      |      |      |      |      +-- Write TDI
  |      |      |      |      |      |      +--------- Read TDO
  |      |      |      |      |      +---------------- Write TMS
  |      |      |      |      +----------------------- 0=MSB first / 1=LSB first
  |      |      |      +------------------------------ 0=+ve clock edge / 1=-ve clock edge (write)
  |      |      +------------------------------------ 0=+ve clock edge / 1=-ve clock edge (read)
  |      +------------------------------------------- 0=byte length / 1=bit length
  +-------------------------------------------------- must be 0 for MPSSE data commands
```

**Bit 0 (Write TDI):** Set to 1 to shift data OUT on TDI/DO during this command.  
**Bit 1 (Read TDO):** Set to 1 to capture data IN from TDO/DI during this command.  
**Bit 2 (Write TMS):** Set to 1 to use TMS clocking mode instead of data shifting.  
**Bit 3 (LSB first):** Set to 1 to shift LSB first (default is MSB first).  
**Bit 4 (Write clock edge):** 0 = data changes on rising edge; 1 = data changes on falling edge.  
**Bit 5 (Read clock edge):** 0 = data sampled on rising edge; 1 = data sampled on falling edge.  
**Bit 6 (Bit mode):** 0 = byte mode (1–65536 bytes); 1 = bit mode (1–8 bits).  

Common combinations used in I2C:

- `0x1B` = 0b00011011 = LSB first, -ve write edge, bit mode, write only — used for clocking I2C bytes

[return to ToC](#table-of-contents)

---

## 3. Clock Configuration

### 3.1 Frequency Formula

**FT232H / FT2232H / FT4232H with clock-divide-by-5 DISABLED (0x8A):**

```text
TCK = 60 MHz / ((1 + divisor) * 2)
Maximum = 30 MHz  (divisor = 0)
```

**FT232H / FT2232H / FT4232H with clock-divide-by-5 ENABLED (0x8B) or FT2232D:**

```text
TCK = 12 MHz / ((1 + divisor) * 2)
Maximum = 6 MHz  (divisor = 0)
```

### 3.2 Common Divisor Values (divide-by-5 OFF, 60 MHz base)

| Target Freq | Divisor (hex) | Divisor Low | Divisor High | Actual Freq |
|-|-|-|-|-|
| 30 MHz      | 0x0000       | 0x00        | 0x00         | 30 MHz      |
| 10 MHz      | 0x0002       | 0x02        | 0x00         | 10 MHz      |
| 5 MHz       | 0x0005       | 0x05        | 0x00         | 5 MHz       |
| 1 MHz       | 0x001D       | 0x1D        | 0x00         | 1 MHz       |
| 400 kHz     | 0x004A       | 0x4A        | 0x00         | ~400 kHz    |
| 100 kHz     | 0x012B       | 0x2B        | 0x01         | ~100 kHz    |

> **PsGadget I2C default:** 100 kHz — divisor `0x012B`, sent as `@(0x86, 0x2B, 0x01)`.

### 3.3 Clock Commands

| Opcode | Arguments      | Function                                         | Module |
|-|-|-|-|
| 0x86   | divL, divH    | Set TCK/SK clock divisor (16-bit little-endian)  | YES    |
| 0x8A   | (none)        | Disable clock divide-by-5 (use 60 MHz base)      | YES    |
| 0x8B   | (none)        | Enable clock divide-by-5 (12 MHz base, FT2232D compat) | No |
| 0x8C   | (none)        | Enable 3-phase data clocking (I2C timing)        | No     |
| 0x8D   | (none)        | Disable 3-phase data clocking                    | YES    |
| 0x8E   | len (0–7)     | Clock n bits with no data transfer               | No     |
| 0x8F   | lenL, lenH    | Clock n*8 bits with no data transfer             | No     |

[return to ToC](#table-of-contents)

---

## 4. GPIO Commands

These commands control the state and direction of ADBUS and ACBUS pins directly.
They are the lowest-latency way to toggle outputs from the host.

| Opcode | Arguments          | Function                                                   | Module |
|-|-|-|-|
| 0x80   | value, direction   | Set ADBUS low byte value and direction                      | YES    |
| 0x81   | (none)             | Read ADBUS low byte — returns 1 byte in response buffer     | YES    |
| 0x82   | value, direction   | Set ACBUS high byte value and direction                     | YES    |
| 0x83   | (none)             | Read ACBUS high byte — returns 1 byte in response buffer    | YES    |

### Byte encoding for 0x80 / 0x82

Both commands take two argument bytes immediately after the opcode:

```text
0x80  <value>  <direction>
       |         |
       |         +-- 1 bit per pin: 1=output, 0=input
       +------------ 1 bit per pin: for outputs, 1=high, 0=low; for inputs, ignored
```

**Example — set ACBUS0 high, all ACBUS outputs:**

```powershell
$buf = [byte[]]@(0x82, 0x01, 0xFF)
# value=0x01: bit0=1 (ACBUS0=high), all others low
# direction=0xFF: all 8 pins as outputs
```

**Example — read ACBUS:**

```powershell
$buf = [byte[]]@(0x83)
$dev._connection.Device.Write([ref]$buf, 1, [ref]$written)
$read = [byte[]]::new(1)
$dev._connection.Device.Read([ref]$read, 1, [ref]$bytesRead)
```

[return to ToC](#table-of-contents)

---

## 5. Setup and Control Commands

These are sent once during initialization to configure the MPSSE engine.

| Opcode | Arguments         | Function                                              | Module |
|-|-|-|-|
| 0x84   | (none)            | Enable loopback — connect TDI to TDO internally       | No     |
| 0x85   | (none)            | Disable loopback — disconnect TDI from TDO            | YES    |
| 0x87   | (none)            | Send Immediate — flush output buffer to host PC       | YES    |
| 0x88   | (none)            | Wait until GPIOL1 (ADBUS5) is HIGH                    | No     |
| 0x89   | (none)            | Wait until GPIOL1 (ADBUS5) is LOW                     | No     |
| 0x96   | (none)            | Enable adaptive clocking (ARM JTAG RTCK sync)         | No     |
| 0x97   | (none)            | Disable adaptive clocking                             | YES    |
| 0x9E   | lowEnable, highEnable | FT232H only: per-pin open-drain drive-low / tristate on 1 (I2C open-drain) | No |

> **0x87 (Send Immediate)** is critical. Without it, the chip may buffer commands
> internally. Always append 0x87 at the end of a command sequence that expects a
> response, or whenever you want guaranteed delivery before reading.

### PsGadget init sequence (Initialize-MpsseI2C)

```powershell
# Step 1: engine reset and baseline
@(0x8A,   # disable clock divide-by-5 (use 60 MHz base)
  0x85,   # disable loopback
  0x97)   # disable adaptive clocking

# Step 2: set clock frequency (100 kHz I2C)
@(0x86, 0x2B, 0x01)   # divisor = 0x012B -> 100 kHz

# Step 3: set ADBUS pins to I2C idle (SCL=1, SDA=1, both output)
@(0x80, 0x03, 0x03)
```

[return to ToC](#table-of-contents)

---

## 6. Data Shifting — Output Only

These commands clock data out on TDI/DO. No data is captured from TDO/DI.
Arguments `lenL` and `lenH` encode length as `(n - 1)` little-endian: to send 8 bytes,
pass `0x07, 0x00`. For bit mode, `len` is `(bits - 1)`: to clock 8 bits, pass `0x07`.

| Opcode | Mode      | Edge    | Bit Order | Arguments              |
|-|-|-|-|-|
| 0x10   | Byte      | +ve     | MSB first | lenL, lenH, data bytes |
| 0x11   | Byte      | -ve     | MSB first | lenL, lenH, data bytes |
| 0x12   | Bit       | +ve     | MSB first | len (0-7), byte        |
| 0x13   | Bit       | -ve     | MSB first | len (0-7), byte        |
| 0x18   | Byte      | +ve     | LSB first | lenL, lenH, data bytes |
| 0x19   | Byte      | -ve     | LSB first | lenL, lenH, data bytes |
| 0x1A   | Bit       | +ve     | LSB first | len (0-7), byte        |
| 0x1B   | Bit       | -ve     | LSB first | len (0-7), byte        |

> **0x1B is used by PsGadget I2C** to clock out each byte (8 bits, LSB first, -ve edge).
>
> Example — clock out byte 0x50 (I2C address write):
>
> ```powershell
> @(0x1B, 0x07, 0x50)
> # 0x07 = 8-1 = clock 8 bits
> # 0x50 = data byte (MSB is ignored for LSB-first, chip reads from bit 0 up)
> ```

[return to ToC](#table-of-contents)

## 7. Data Shifting — Input Only

These commands clock TDO/DI and capture data into the receive buffer.
No data is driven onto TDI/DO. Length encoding is same as output commands.

| Opcode | Mode  | Edge    | Bit Order  | Arguments       | Returns        |
|-|-|-|-|-|-|
| 0x20   | Byte  | +ve     | MSB first  | lenL, lenH      | (len+1) bytes  |
| 0x24   | Byte  | -ve     | MSB first  | lenL, lenH      | (len+1) bytes  |
| 0x22   | Bit   | +ve     | MSB first  | len (0-7)       | 1 byte         |
| 0x26   | Bit   | -ve     | MSB first  | len (0-7)       | 1 byte         |
| 0x28   | Byte  | +ve     | LSB first  | lenL, lenH      | (len+1) bytes  |
| 0x2C   | Byte  | -ve     | LSB first  | lenL, lenH      | (len+1) bytes  |
| 0x2A   | Bit   | +ve     | LSB first  | len (0-7)       | 1 byte         |
| 0x2E   | Bit   | -ve     | LSB first  | len (0-7)       | 1 byte         |

For bit mode reads, the captured bits are right-aligned in the returned byte.
Reading 3 bits returns a byte where bits [2:0] hold the captured data; bits [7:3] are undefined.

[return to ToC](#table-of-contents)

---

## 8. Data Shifting — Bidirectional

These commands simultaneously clock data out on TDI/DO while capturing data
from TDO/DI. SPI full-duplex uses these opcodes.

| Opcode | Mode  | Write Edge | Read Edge | Bit Order  | Arguments              | Returns        |
|-|-|-|-|-|-|-|
| 0x31   | Byte  | -ve        | +ve       | MSB first  | lenL, lenH, data bytes | (len+1) bytes  |
| 0x34   | Byte  | +ve        | -ve       | MSB first  | lenL, lenH, data bytes | (len+1) bytes  |
| 0x33   | Bit   | -ve        | +ve       | MSB first  | len, byte              | 1 byte         |
| 0x36   | Bit   | +ve        | -ve       | MSB first  | len, byte              | 1 byte         |
| 0x39   | Byte  | -ve        | +ve       | LSB first  | lenL, lenH, data bytes | (len+1) bytes  |
| 0x3C   | Byte  | +ve        | -ve       | LSB first  | lenL, lenH, data bytes | (len+1) bytes  |
| 0x3B   | Bit   | -ve        | +ve       | LSB first  | len, byte              | 1 byte         |
| 0x3E   | Bit   | +ve        | -ve       | LSB first  | len, byte              | 1 byte         |

> **SPI Mode 0** (CPOL=0, CPHA=0): use 0x31 (write -ve, read +ve, MSB first).  
> **SPI Mode 1** (CPOL=0, CPHA=1): use 0x34 (write +ve, read -ve, MSB first).

## 9. TMS Commands (JTAG)

Used for JTAG TAP state machine navigation. Not used in PsGadget I2C/SPI/GPIO paths.

| Opcode | Arguments     | Function                                       |
|-|-|-|
| 0x4A   | len, byte     | Clock TMS, no read, data changes on +ve edge   |
| 0x4B   | len, byte     | Clock TMS, no read, data changes on -ve edge   |
| 0x6A   | len, byte     | Clock TMS + read TDO on +ve edge, MSB          |
| 0x6B   | len, byte     | Clock TMS + read TDO on -ve edge, MSB          |
| 0x6E   | len, byte     | Clock TMS + read TDO on +ve edge, LSB          |
| 0x6F   | len, byte     | Clock TMS + read TDO on -ve edge, LSB          |

For TMS bit commands: `len` = (bits - 1); `byte` provides the TMS bit pattern.
The MSB of the `byte` argument is driven onto TDI for all TMS clocks in the sequence.

[return to ToC](#table-of-contents)

---

## 10. Wait and Clock-Without-Data Commands

| Opcode | Arguments     | Function                                                      | Module |
|-|-|-|-|
| 0x88   | (none)        | Wait until GPIOL1 (ADBUS5) goes HIGH — CPU stall              | No     |
| 0x89   | (none)        | Wait until GPIOL1 (ADBUS5) goes LOW — CPU stall               | No     |
| 0x94   | (none)        | Clock continuously (no data) until GPIOL1 HIGH                | No     |
| 0x95   | (none)        | Clock continuously (no data) until GPIOL1 LOW                 | No     |
| 0x8E   | len (0-7)     | Clock n bits with no data on TDI or TDO                       | No     |
| 0x8F   | lenL, lenH    | Clock n*8 bits with no data on TDI or TDO                     | No     |
| 0x9C   | lenL, lenH    | Clock n*8 bits or until GPIOL1 HIGH (whichever first)         | No     |
| 0x9D   | lenL, lenH    | Clock n*8 bits or until GPIOL1 LOW (whichever first)          | No     |

[return to ToC](#table-of-contents)

---

## 11. CPU Bus Emulation Commands

Used in MCU host bus emulation mode. Not applicable to MPSSE I2C/SPI/GPIO.

| Opcode | Arguments          | Function                                         |
|-|-|-|
| 0x90   | addr              | Read short address (1-byte addr)                 |
| 0x91   | addrH, addrL      | Read extended address (2-byte addr)              |
| 0x92   | addr, data        | Write short address                              |
| 0x93   | addrH, addrL, data | Write extended address                          |  

[return to ToC](#table-of-contents)

---

## 12. I2C Byte Sequences (Annotated)

All sequences shown as PowerShell byte arrays. These are the exact byte patterns
sent by `Send-MpsseI2CWrite` and `Invoke-FtdiI2CScan` in `Private/Ftdi.Mpsse.ps1`.

### 12.1 I2C START Condition

SDA falls while SCL is HIGH. Both pins initially idle HIGH.

```powershell
@(0x80, 0x03, 0x03)   # ADBUS idle:  SCL=1, SDA=1, both output  (bits 0,1 = outputs)
@(0x80, 0x01, 0x03)   # START step1: SCL=1, SDA=0  (SDA falls while SCL high)
@(0x80, 0x00, 0x03)   # START step2: SCL=0, SDA=0  (begin clocking)
```

### 12.2 Clock Out One Byte + Read ACK

The device drives SDA low for ACK (bit=0), or high for NACK (bit=1).

```powershell
# --- clock out the byte (e.g. address 0x3C write = 0x78) ---
@(0x1B, 0x07, $byte)         # 0x1B: bit mode, LSB first, -ve edge, write only
                              # 0x07: clock 8 bits (8-1)
                              # $byte: the data byte

# --- release SDA to input so device can drive ACK ---
@(0x80, 0x00, 0x01)          # SCL=0, SDA released (direction: only D0=output)
@(0x80, 0x01, 0x01)          # SCL=1 (device drives ACK/NACK on SDA now)

# --- read ADBUS to capture ACK bit ---
0x81                          # read low byte -> returns 1 byte; bit1 = SDA state

# --- release clock ---
@(0x80, 0x00, 0x01)          # SCL=0

# --- reclaim SDA as output ---
@(0x80, 0x02, 0x03)          # SCL=0, SDA=1 (output high), both output

0x87                          # SEND IMMEDIATE: flush to chip
```

Interpreting the ACK byte read back:

```powershell
$ackByte = $readBuf[0]
$ackBit  = ($ackByte -band 0x02) -shr 1   # bit 1 = SDA = D1
# ackBit -eq 0 -> ACK  (device acknowledged)
# ackBit -eq 1 -> NACK (device not responding or address wrong)
```

### 12.3 I2C STOP Condition

SCL goes HIGH first, then SDA goes HIGH while SCL is HIGH.

```powershell
@(0x80, 0x00, 0x03)   # SCL=0, SDA=0, both output
@(0x80, 0x01, 0x03)   # SCL=1, SDA=0  (SCL rises first)
@(0x80, 0x03, 0x03)   # SCL=1, SDA=1  (SDA rises: STOP condition)
0x87                   # SEND IMMEDIATE
```

### 12.4 Full I2C Write (Address + Data Bytes)

```powershell
function Send-I2C {
    param([FTD2XX_NET.FTDI]$ftdi, [byte]$addr7bit, [byte[]]$data)

    $addrByte = ($addr7bit -shl 1) -bor 0x00   # write = 0, read = 1

    $buf = [System.Collections.Generic.List[byte]]::new()

    # START
    $buf.AddRange([byte[]]@(0x80, 0x03, 0x03))
    $buf.AddRange([byte[]]@(0x80, 0x01, 0x03))
    $buf.AddRange([byte[]]@(0x80, 0x00, 0x03))

    # Address byte + ACK
    $buf.AddRange([byte[]]@(0x1B, 0x07, $addrByte))
    $buf.AddRange([byte[]]@(0x80, 0x00, 0x01))
    $buf.AddRange([byte[]]@(0x80, 0x01, 0x01))
    $buf.Add(0x81)
    $buf.AddRange([byte[]]@(0x80, 0x00, 0x01))
    $buf.AddRange([byte[]]@(0x80, 0x02, 0x03))

    # Data bytes + ACK each
    foreach ($b in $data) {
        $buf.AddRange([byte[]]@(0x1B, 0x07, $b))
        $buf.AddRange([byte[]]@(0x80, 0x00, 0x01))
        $buf.AddRange([byte[]]@(0x80, 0x01, 0x01))
        $buf.Add(0x81)
        $buf.AddRange([byte[]]@(0x80, 0x00, 0x01))
        $buf.AddRange([byte[]]@(0x80, 0x02, 0x03))
    }

    # STOP
    $buf.AddRange([byte[]]@(0x80, 0x00, 0x03))
    $buf.AddRange([byte[]]@(0x80, 0x01, 0x03))
    $buf.AddRange([byte[]]@(0x80, 0x03, 0x03))
    $buf.Add(0x87)

    $arr = $buf.ToArray()
    $written = 0
    $ftdi.Write([ref]$arr, $arr.Length, [ref]$written) | Out-Null
}
```

[return to ToC](#table-of-contents)

---

## 13. SPI Byte Sequences (Annotated)

SPI uses ADBUS for the clock bus. CS (chip select) is typically ADBUS3 (D3) or
an ACBUS pin controlled manually with 0x80/0x82.

### 13.1 SPI Mode 0 Write (CPOL=0, CPHA=0)

```text
CLK idle LOW. Data captured on rising edge. Data changes on falling edge.
Host uses: 0x11 (byte out, MSB first, -ve edge) or 0x31 (full-duplex)
```

```powershell
# Assert CS (D3 low, others as needed)
# direction: D0(CLK)=out, D1(MOSI)=out, D2(MISO)=in, D3(CS)=out = 0b00001011 = 0x0B
@(0x80, 0x08, 0x0B)   # CS=high initially, CLK=0, MOSI=0

# CS low to begin transaction
@(0x80, 0x00, 0x0B)   # D3(CS)=0

# Write 3 bytes (0xAA, 0xBB, 0xCC), MSB first, -ve edge out
@(0x11, 0x02, 0x00, 0xAA, 0xBB, 0xCC)
# 0x11: byte out, MSB, -ve edge
# 0x02, 0x00: length = 3-1 = 2 (little-endian)

0x87   # SEND IMMEDIATE

# CS high to end transaction
@(0x80, 0x08, 0x0B)
```

### 13.2 SPI Mode 0 Full-Duplex Read/Write

```powershell
# Write 2 bytes and simultaneously read 2 bytes
@(0x31, 0x01, 0x00, 0xAA, 0xBB)
# 0x31: full-duplex, MSB first, -ve write, +ve read
# 0x01, 0x00: length = 2-1 = 1
# returned bytes appear in receive buffer

0x87
```

[return to ToC](#table-of-contents)

---

## 14. Error Response

When the MPSSE receives an unrecognized command byte, it returns a 2-byte error response
into the host's receive buffer:

```text
0xFA  <offending-byte>
```

Example — sending opcode 0xFF (undefined) returns `[0xFA, 0xFF]` in the read buffer.

Always check for `0xFA` in response data when debugging new command sequences.
If you see `0xFA` followed by an unexpected byte, you have a command framing error —
usually a missing argument byte that was consumed as the next opcode.

[return to ToC](#table-of-contents)

---

## 15. PsGadget Module Usage Cross-Reference

This table maps every opcode used in the PsGadget module to its source file and function.

| Opcode | Hex  | Purpose in Module                     | Source File          | Function              |
|-|-|-|-|-|
| 0x80   | ADBUS write | Set SCL/SDA for I2C signaling  | Ftdi.Mpsse.ps1 | Send-MpsseI2CWrite, Initialize-MpsseI2C |
| 0x81   | ADBUS read  | Read SDA for ACK/NACK bit      | Ftdi.Mpsse.ps1 | Send-MpsseI2CWrite    |
| 0x82   | ACBUS write | Set ACBUS GPIO output state    | Ftdi.Mpsse.ps1 | Send-MpsseAcbusCommand |
| 0x83   | ACBUS read  | Read ACBUS GPIO input state    | Ftdi.Mpsse.ps1 | Get-FtdiGpioPins      |
| 0x85   | Loopback off | Disable TDI-TDO loopback      | Ftdi.Mpsse.ps1 | Initialize-MpsseI2C   |
| 0x86   | Clock div   | Set I2C clock frequency        | Ftdi.Mpsse.ps1 | Initialize-MpsseI2C   |
| 0x87   | Flush       | Send Immediate — flush buffer  | Ftdi.Mpsse.ps1 | Send-MpsseI2CWrite, Send-MpsseAcbusCommand |
| 0x8A   | Clk/5 off   | Use 60 MHz base clock          | Ftdi.Mpsse.ps1 | Initialize-MpsseI2C   |
| 0x8D   | 3-phase off | Disable 3-phase data clocking  | Ftdi.Mpsse.ps1 | Initialize-MpsseI2C   |
| 0x97   | Adaptive off | Disable adaptive clocking     | Ftdi.Mpsse.ps1 | Initialize-MpsseI2C   |
| 0x1B   | Bit out LSB | Clock I2C byte out, LSB first  | Ftdi.Mpsse.ps1 | Send-MpsseI2CWrite    |

### Architecture Tier Mapping

| MPSSE Commands    | Architecture Tier | Accessible From        | Approx. Latency |
|-|-|-|-|
| 0x10-0x3F (shift) | Tier 0            | User scripts           | 1-3 ms          |
| 0x80/0x82 (GPIO)  | Tier 1/2          | User scripts           | 2-5 ms          |
| I2C write sequence | Tier 0 (via public) | Send-PsGadgetI2CWrite | 3-8 ms/byte    |
| ACBUS GPIO        | Tier 1/2 (via public) | Set-PsGadgetGpio     | 2-4 ms          |

See docs/wiki/Architecture.md for the full tier explanation and timing data.

[return to ToC](#table-of-contents)
