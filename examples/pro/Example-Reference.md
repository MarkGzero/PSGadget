# Pro Example: PSGadget Reference Patterns

**Purpose**: Concise patterns for FT232H GPIO, I2C, SSD1306, FT232R CBUS,
and MicroPython REPL. No step-by-step prose.

> **Pro (Scott)**: Read the tables. Run the blocks. Skip the rest.

---

## Environment

```powershell
Import-Module PSGadget
$e = Test-PsGadgetEnvironment
# $e.Status / $e.Reason / $e.NextStep / $e.Backend / $e.Devices
```

---

## Device enumeration and connect

```powershell
Get-FTDevice | Format-Table Index, Type, SerialNumber, GpioMethod

# By serial number (recommended -- stable across USB port changes)
$dev = New-PsGadgetFtdi -SerialNumber 'BG01X3GX'

# By index (fragile if multiple devices)
$dev = New-PsGadgetFtdi -Index 0

# By type
$sn  = (Get-FTDevice | Where-Object { $_.Type -eq 'FT232H' })[0].SerialNumber
$dev = New-PsGadgetFtdi -SerialNumber $sn
```

---

## FT232H GPIO (MPSSE, ACBUS0-7)

```powershell
$dev.SetPin(0, 'HIGH')               # ACBUS0 HIGH
$dev.SetPin(0, 'LOW')                # ACBUS0 LOW
$dev.SetPins(@(0,1,2), 'HIGH')       # ACBUS0,1,2 HIGH
$dev.SetPins(@(0,1,2), 'LOW')        # ACBUS0,1,2 LOW
$dev.PulsePin(0, 'HIGH', 500)        # HIGH for 500 ms then LOW
$dev.Close()
```

Pin map: pin N = ACBUSN. All 3.3 V.

---

## I2C scan

```powershell
$dev     = New-PsGadgetFtdi -Index 0
$addrs   = $dev.Scan()               # returns [int[]] of responding addresses
$addrs | ForEach-Object { '0x{0:X2}' -f $_ }
$dev.Close()
```

---

## SSD1306 OLED

```powershell
$dev = New-PsGadgetFtdi -Index 0
$d   = $dev.GetDisplay([byte]0x3C)
$d.Clear() | Out-Null
$d.WriteText('Line 1', 0) | Out-Null
$d.WriteText('Line 2', 1) | Out-Null
$d.SetCursor(0, 4) | Out-Null
$d.WriteText('Bottom half', 4) | Out-Null
$dev.Close()
```

Pages 0-7 top to bottom. Col 0-127. Text wraps at right edge.

---

## FT232R CBUS GPIO

```powershell
# One-time EEPROM setup (replug after)
Set-PsGadgetFt232rCbusMode -Index 0

# Runtime GPIO (after replug)
$dev = New-PsGadgetFtdi -Index 0
$dev.SetPin(0, 'HIGH')    # CBUS0
$dev.SetPins(@(0,1), 'LOW')
$dev.Close()
```

Runtime pins: CBUS0-3 only. CBUS4 is EEPROM-config only, not driveable at runtime.
Bit mask is 8 bits: upper nibble = direction, lower nibble = value.

---

## MicroPython

```powershell
Get-PsGadgetMpy | Format-Table

$mpy = Connect-PsGadgetMpy -SerialPort '/dev/ttyUSB0'
$mpy.Invoke("import sys; print(sys.version)")
$mpy.Invoke(@"
import machine
led = machine.Pin(25, machine.Pin.OUT)
led.toggle()
"@)
```

---

## Config

```powershell
Get-PsGadgetConfig
Set-PsGadgetConfig -Key LogLevel -Value Debug
```

Config at `~/.psgadget/config.json`. Logs at `~/.psgadget/logs/psgadget.log`.

---

## Backends and flags

| Script flag | Meaning |
|------------|---------|
| `$script:IotBackendAvailable` | Iot.Device.Bindings loaded (PS 7.4+ / .NET 8+) |
| `$script:D2xxLoaded` | FTD2XX_NET.dll loaded |

DLL selection: `Private/Initialize-FtdiAssembly.ps1`.
Enumeration dispatch: `Private/Ftdi.Backend.ps1` -> `Get-FtdiDeviceList`.
MPSSE byte sequences: `Private/Ftdi.Mpsse.ps1`.
GPIO capabilities by chip: `Get-FtdiChipCapabilities -TypeName 'FT232H'`.

---

## Alias

`Test-PsGadgetSetup` -> `Test-PsGadgetEnvironment`
