# Engineer Example: I2C Bus Scan and Device Detection

**Purpose**: Enumerate the I2C bus from PowerShell, verify ACK-based device
detection, and understand the MPSSE layer underneath.

> **Engineer (Izzy)**: This example assumes you understand I2C protocol basics
> (start/stop conditions, 7-bit addressing, ACK/NACK). The focus is on how
> PSGadget maps these to MPSSE commands and what happens at the byte level.

---

## Hardware setup

| FT232H pin | I2C signal | Note |
|-----------|-----------|------|
| ACBUS0 | SCL | 4.7 kohm pull-up to 3.3 V required |
| ACBUS1 | SDA | 4.7 kohm pull-up to 3.3 V required |
| 3V3 | VCC | Supplies 3.3 V to I2C devices |
| GND | GND | Common ground |

Without pull-up resistors the bus will not function. SDA and SCL must both be
pulled to VCC when idle. 4.7 kohm is standard for 100 kHz; 2.2 kohm for 400 kHz.

---

## MPSSE I2C internals

PSGadget initializes MPSSE for I2C in `Private/Ftdi.Mpsse.ps1`:

1. Set clock divide-by-5 off -- base clock is 60 MHz.
2. Disable three-phase clocking, disable loopback.
3. Set clock divisor: standard mode (100 kHz) uses divisor `0x14B` which
   gives `60 MHz / (1 + 0x14B) / 2 = 99.7 kHz`.
4. Set ADBUS0 (SCL) and ADBUS1 (SDA) as outputs, idle HIGH.

Each I2C write from `Send-MpsseI2CWrite` sends:
- START condition (SDA LOW while SCL HIGH)
- Address byte (7-bit address left-shifted by 1, or'd with 0 for write)
- ACK bit read-back after the address byte -- NACK throws a terminating error
- Data bytes with ACK read-back after each one
- STOP condition (SDA HIGH while SCL HIGH)

---

## I2C bus scan

```powershell
#Requires -Version 5.1
Import-Module PSGadget

$dev = New-PsGadgetFtdi -Index 0

try {
    Write-Host 'Scanning I2C bus (addresses 0x08 to 0x77)...'
    $found = $dev.Scan()

    if ($found.Count -eq 0) {
        Write-Host 'No devices found. Check wiring and pull-up resistors.'
    } else {
        Write-Host ("Found {0} device(s):" -f $found.Count)
        foreach ($addr in $found) {
            $hex = '0x{0:X2}' -f $addr
            Write-Host ("  $hex")
        }
    }
} finally {
    $dev.Close()
}
```

Expected output with an SSD1306 connected at the default address:

```
Scanning I2C bus (addresses 0x08 to 0x77)...
Found 1 device(s):
  0x3C
```

---

## Interpreting the scan results

Common I2C addresses:

| Address | Device |
|---------|--------|
| 0x3C or 0x3D | SSD1306 OLED display |
| 0x68 or 0x69 | MPU-6050 IMU |
| 0x29 | VL53L0X ToF rangefinder |
| 0x23 or 0x5C | BH1750 light sensor |
| 0x48-0x4B | ADS1115 ADC |
| 0x76 or 0x77 | BME280 / BMP280 pressure/temperature |

---

## Verifying ACK validation in write path

`Send-MpsseI2CWrite` reads back the ACK bit after each byte. If a device NACKs
the address phase (device not present or not ready), PSGadget throws:

```
ERROR: I2C NACK received at address 0x3C byte 0 (address phase)
```

If a device NACKs mid-data (write overflow, invalid register), PSGadget throws:

```
ERROR: I2C NACK received at address 0x3C byte 3 (data phase)
```

This means you do not need to check return values from I2C writes -- any fault
terminates as a PowerShell error you can catch:

```powershell
try {
    # Connect-PsGadgetSsd1306 will throw if 0x3C does not ACK
    $display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi -Address 0x3C
} catch {
    Write-Error "I2C init failed: $_"
}
```

---

## GPIO read-modify-write behavior

`Set-FtdiGpioPins` internally calls `Get-FtdiGpioPins` first to read the
current direction and value bytes, then ORs/ANDs the target pins into them.

This means if ACBUS0 is HIGH and you call `SetPin(1, 'HIGH')`, ACBUS0 stays
HIGH. The driver does not reset all pins to LOW on each operation.

To explicitly clear all pins:

```powershell
# Force all ACBUS0-7 to LOW and output direction
# This bypasses the read-modify-write by writing a full mask
$dev.SetPins(@(0,1,2,3,4,5,6,7), 'LOW')
```

---

## Clock frequency selection

```powershell
# Standard mode: 100 kHz (default)
$ftdi = Connect-PsGadgetFtdi -Index 0
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi   # uses 100 kHz
```

To change the I2C clock (for fast mode or slower devices), call
`Initialize-MpsseI2C` directly from a private function invocation:

```powershell
# Fast mode: 400 kHz
Initialize-MpsseI2C -DeviceHandle $ftdi.Handle -ClockFrequency 400000
```

Note: `Initialize-MpsseI2C` is a private function. Call it before
`Connect-PsGadgetSsd1306` if you need a non-default frequency.

---

## Quick reference

| MPSSE detail | Value |
|-------------|-------|
| Base clock | 60 MHz (divide-by-5 disabled) |
| 100 kHz divisor | 0x14B |
| 400 kHz divisor | 0x4A |
| SCL pin | ADBUS0 (mapped to ACBUS0 in PSGadget) |
| SDA pin | ADBUS1 (mapped to ACBUS1 in PSGadget) |
| GPIO command (ACBUS) | 0x82 (set direction + value) |
| GPIO read (ACBUS) | 0x83 |
| I2C address byte | (7-bit addr << 1) OR 0 for write, OR 1 for read |
