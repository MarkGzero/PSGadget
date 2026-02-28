# PSGadget Cmdlet Reference

All exported functions in PSGadget. For class method reference see
[Classes.md](Classes.md).

---

## Diagnostics and environment

### Test-PsGadgetEnvironment

Checks the current environment and reports hardware readiness.

```powershell
Test-PsGadgetEnvironment [-Verbose]
```

**Returns**: `PSCustomObject` with:

| Property | Type | Description |
|----------|------|-------------|
| Status | string | `OK` or `Fail` |
| Reason | string | Why the check passed or failed |
| NextStep | string | Command to run to fix the issue |
| Platform | string | `Windows` or `Linux/Unix` |
| PsVersion | string | PowerShell version string |
| DotNetVersion | string | .NET runtime version string |
| Backend | string | Active backend name |
| BackendReady | bool | True if a real backend loaded |
| NativeLibOk | bool | True if native library is present |
| NativeLibPath | string | Path to native library (if found) |
| Devices | array | Connected device objects |
| DeviceCount | int | Number of devices found |
| ConfigPresent | bool | True if config.json exists |
| IsReady | bool | True if backend + native + devices all OK |

`Test-PsGadgetSetup` is an alias for backward compatibility.

---

## FTDI device management

### List-PsGadgetFtdi

Lists connected FTDI devices.

```powershell
List-PsGadgetFtdi
```

**Returns**: array of device objects with `Index`, `Type`, `SerialNumber`,
`Description`, `LocationId`, `GpioMethod`, `HasMpsse`.

### New-PsGadgetFtdi

Creates and connects a `PsGadgetFtdi` object, ready to use immediately.
Preferred over `Connect-PsGadgetFtdi` for scripted workflows.

```powershell
New-PsGadgetFtdi [-Index <int>] [-SerialNumber <string>] [-LocationId <string>]
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Index | int | Zero-based device index from `List-PsGadgetFtdi` |
| SerialNumber | string | Device serial number (stable across USB ports) |
| LocationId | string | USB location ID |

**Returns**: `PsGadgetFtdi` object with `SetPin`, `SetPins`, `PulsePin`,
`Scan`, `Display`, `Close` methods.

### Connect-PsGadgetFtdi

Opens a raw connection to an FTDI device. Returns a handle for use with
lower-level cmdlets. Prefer `New-PsGadgetFtdi` for most use cases.

```powershell
Connect-PsGadgetFtdi [-Index <int>] [-SerialNumber <string>]
```

### Set-PsGadgetFtdiMode

Sets the bit-bang or MPSSE mode on an FTDI device.

```powershell
Set-PsGadgetFtdiMode -DeviceIndex <int> -Mode <string>
```

### Get-PsGadgetFtdiEeprom

Reads the EEPROM contents from an FTDI device.

```powershell
Get-PsGadgetFtdiEeprom [-Index <int>] [-SerialNumber <string>]
```

---

## GPIO

### Set-PsGadgetGpio

Sets GPIO pin state on a connected FTDI device.

```powershell
Set-PsGadgetGpio -DeviceIndex <int> -Pins <int[]> -State <string> [-DurationMs <int>]
Set-PsGadgetGpio -Connection <object> -Pins <int[]> -State <string> [-DurationMs <int>]
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| DeviceIndex | int | Zero-based device index |
| Connection | object | Open connection from `Connect-PsGadgetFtdi` |
| Pins | int[] | Pin numbers to set (e.g. `@(0, 1)`) |
| State | string | `HIGH` or `LOW` |
| DurationMs | int | If set, pin returns to opposite state after this many ms |

**Pin numbering:**
- FT232H: ACBUS0 = 0, ACBUS1 = 1, ... ACBUS7 = 7
- FT232R: CBUS0 = 0, CBUS1 = 1, CBUS2 = 2, CBUS3 = 3

### Set-PsGadgetFt232rCbusMode

Programs the FT232R EEPROM to enable CBUS bit-bang mode. Run once per device.
Requires replug after running.

```powershell
Set-PsGadgetFt232rCbusMode [-Index <int>] [-Pins <int[]>]
```

---

## SSD1306 OLED display

### Connect-PsGadgetSsd1306

Connects to an SSD1306 display over I2C via an FTDI device.

```powershell
Connect-PsGadgetSsd1306 -FtdiDevice <object> [-Address <byte>]
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| FtdiDevice | object | required | Open FTDI device from `Connect-PsGadgetFtdi` |
| Address | byte | 0x3C | I2C address of the display |

### Clear-PsGadgetSsd1306

Clears all pages of the SSD1306 display.

```powershell
Clear-PsGadgetSsd1306 -Display <object>
```

### Write-PsGadgetSsd1306

Writes text to a page of the SSD1306 display.

```powershell
Write-PsGadgetSsd1306 -Display <object> -Text <string> -Page <int>
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Display | object | Display object from `Connect-PsGadgetSsd1306` |
| Text | string | Text to render |
| Page | int | Page row 0-7 (0 = top, 7 = bottom) |

### Set-PsGadgetSsd1306Cursor

Sets the cursor position on the SSD1306 display.

```powershell
Set-PsGadgetSsd1306Cursor -Display <object> -Page <int> -Column <int>
```

---

## MicroPython

### List-PsGadgetMpy

Lists available serial ports that may have MicroPython boards connected.

```powershell
List-PsGadgetMpy
```

### Connect-PsGadgetMpy

Connects to a MicroPython board over serial REPL.

```powershell
Connect-PsGadgetMpy -SerialPort <string> [-BaudRate <int>]
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| SerialPort | string | required | Port name (`COM3`, `/dev/ttyUSB0`, etc.) |
| BaudRate | int | 115200 | Serial baud rate |

**Returns**: `PsGadgetMpy` object with `Invoke` method.

---

## Configuration

### Get-PsGadgetConfig

Returns the current user configuration as a `PSCustomObject`.

```powershell
Get-PsGadgetConfig
```

### Set-PsGadgetConfig

Sets a configuration key.

```powershell
Set-PsGadgetConfig -Key <string> -Value <string>
```

---

## Aliases

| Alias | Resolves to |
|-------|-------------|
| `Test-PsGadgetSetup` | `Test-PsGadgetEnvironment` |
