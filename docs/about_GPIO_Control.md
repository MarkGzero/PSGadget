
## Modes

| `ucMode` | Hex | Mode Name                             | Notes                                                                           |
| :------: | :-- | :------------------------------------ | :------------------------------------------------------------------------------ |
|   0x00   | 0   | **Reset**                             | Returns the chip to its default (UART or FIFO) mode as defined in EEPROM.       |
|   0x01   | 1   | **Asynchronous Bit‑Bang**             | Classic bit‑bang on ADBUS or CBUS (baud‑rate clocked)                           |
|   0x02   | 2   | **MPSSE**                             | Multi‑Protocol Sync Serial Engine for JTAG/SPI/I²C/GPIO .                       |
|   0x04   | 4   | **Synchronous Bit‑Bang**              | Bit‑bang that updates outputs only on USB transfers; strobes WRSTB/RDSTB lines. |
|   0x08   | 8   | **MCU Host Bus Emulation (CBUS)**     | “Microcontroller” parallel bus emulation over CBUS lines.                       |
|   0x10   | 16  | **Fast Opto‑Isolated Serial Mode**    | High‑speed, opto‑isolator‑friendly UART/FIFO variant.                           |
|   0x20   | 32  | **CBUS Bit‑Bang Mode**                | Bit‑bang on the CBUSn pins—requires EEPROM configuration of CBUS pins.          |
|   0x40   | 64  | **Single‑Channel Sync 245 FIFO Mode** | FIFO‑style parallel data on ADBUS, 245‑style—but synchronous (FT2232H/FT232H).  |


## GPIO & Control Commands (Section 3.6–3.7) AN_108_Command_Processo…

### GPIO Addresses

| ACBUSn | FT232H pin No. | Default EEPROM config | MPSSE mask (1 ≪ n) |
|--------|----------------|----------------------|---------------------|
| ACBUS0 | 21             | TriSt‑PU             | 0x01                |
| ACBUS1 | 25             | TriSt‑PU             | 0x02                |
| ACBUS2 | 26             | TriSt‑PU             | 0x04                |
| ACBUS3 | 27             | TriSt‑PU             | 0x08                |
| ACBUS4 | 28             | TriSt‑PU             | 0x10                |
| ACBUS5 | 29             | TriSt‑PU             | 0x20                |
| ACBUS6 | 30             | TriSt‑PU             | 0x40                |
| ACBUS7 | 31             | TriSt‑PD             | 0x80                |

### GPIO Commands

| Opcode | Set O/P | Read I/P | Byte-Group | Purpose |
|--------|---------|----------|------------|---------|
| 0x80   | Yes     | No       | Low byte   | Set ADBUS 7–0 output & value |
| 0x82   | Yes     | No       | High byte  | Set ACBUS 7–0 output & value |
| 0x81   | No      | Yes      | Low byte   | Read ADBUS 7–0 inputs |
| 0x83   | No      | Yes      | High byte  | Read ACBUS 7–0 inputs |
| 0x84   | –       | –        | –          | Enable loopback (TDI→TDO) |
| 0x85   | –       | –        | –          | Disable loopback |
| 0x87   | –       | –        | –          | Send Immediate: flush buffer |
| 0x88   | –       | –        | –          | Wait On I/O High: block until I/O1↑ |
| 0x89   | –       | –        | –          | Wait On I/O Low: block until I/O1↓ |


## Examples

- `$psgadget` is initialized in MPSSE mode
- red LED is connected to ACBUS2
- green LED is connected to ACBUS4


### blink RED LED

```powershell
$cmd = 0x82
$zero = 0x00
$acbus2 = 0x04
$blinks = 10
$delay = 20
[uint32]$_ref = 0

$acbus2_setHigh = [byte[]]($cmd, $acbus2, $acbus2)
$acbus2_setLow = [byte[]]($cmd, $zero, $acbus2)


for ($i = 0; $i -lt $blinks; $i++) {
    $psgadget.Write($acbus2_setHigh,3, [ref]$_ref)
    Start-Sleep -Milliseconds $delay
    $psgadget.Write($acbus2_setLow,3, [ref]$_ref)
    Start-Sleep -Milliseconds $delay
}

```

### alternate blink RED and GREEN LEDs

```powershell
$cmd = 0x82
$zero = 0x00
$acbus2 = 0x04
$acbus4 = 0x10
$blinks = 10
$delay = 250
$_ref = $null

$acbus2_setHigh = [byte[]]($cmd, $acbus2, $acbus2)
$acbus2_setLow = [byte[]]($cmd, $zero, $acbus2)

$acbus4_setHigh = [byte[]]($cmd, $acbus4, $acbus4)
$acbus4_setLow = [byte[]]($cmd, $zero, $acbus4)

for ($i = 0; $i -lt $blinks; $i++) {

    # toggle the red LED to ON
    $psgadget.Write($acbus2_setHigh,3, [ref]$_ref)
    
    # wait for a bit to keep the LED ON
    Start-Sleep -Milliseconds $delay
    
    # toggle the red LED to OFF
    $psgadget.Write($acbus2_setLow,3, [ref]$_ref)

    # wait for a bit for consistency
    Start-Sleep -Milliseconds $delay

    # toggle the green LED to ON
    $psgadget.Write($acbus4_setHigh,3, [ref]$_ref)

    # wait for a bit to keep the LED ON
    Start-Sleep -Milliseconds $delay

    # toggle the green LED to OFF
    $psgadget.Write($acbus4_setLow,3, [ref]$_ref)
    Start-Sleep -Milliseconds $delay
}

$psgadget.Write($acbus2_setLow,3, [ref]$_ref)

```