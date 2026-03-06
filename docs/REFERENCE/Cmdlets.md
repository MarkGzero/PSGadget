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
List-PsGadgetFtdi [-ShowVCP]
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| ShowVCP | switch | Also show VCP (COM port / ttyUSB) entries hidden by default |

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
`Scan`, `GetDisplay`, `Close` methods. Device is connected on construction.

### Connect-PsGadgetFtdi

Opens a raw connection to an FTDI device. Returns a handle for use with
lower-level cmdlets. Prefer `New-PsGadgetFtdi` for most use cases.

```powershell
Connect-PsGadgetFtdi -Index <int>
Connect-PsGadgetFtdi -SerialNumber <string>
Connect-PsGadgetFtdi -LocationId <string>
```

**Parameters** (one required, mutually exclusive):

| Parameter | Type | Description |
|-----------|------|-------------|
| Index | int | Zero-based device index |
| SerialNumber | string | Device serial number |
| LocationId | string | USB hub+port address |

### Set-PsGadgetFtdiMode

Sets the operating mode on an FTDI device. Takes a connected `PsGadgetFtdi`
object from `New-PsGadgetFtdi`.

```powershell
Set-PsGadgetFtdiMode -PsGadget <PsGadgetFtdi> -Mode <string> [-Mask <int>] [-Pins <int[]>]
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| PsGadget | PsGadgetFtdi | required | Connected device object |
| Mode | string | required | `MPSSE`, `CBUS`, `AsyncBitBang`, `SyncBitBang`, or `UART` |
| Mask | int | 0xFF | Direction mask byte (1 = output) |
| Pins | int[] | @(0,1,2,3) | Pin subset for CBUS operations |

**Notes**: `CBUS` mode on FT232R writes to EEPROM and requires a USB replug.
All other modes take effect immediately on the open connection.

### Get-PsGadgetFtdiEeprom

Reads the EEPROM contents from an FTDI device.

```powershell
Get-PsGadgetFtdiEeprom -Index <int>
Get-PsGadgetFtdiEeprom -SerialNumber <string>
Get-PsGadgetFtdiEeprom -PsGadget <PsGadgetFtdi>
```

---

## GPIO

### Set-PsGadgetGpio

Sets GPIO pin state on a connected FTDI device.

```powershell
Set-PsGadgetGpio -Index <int> -Pins <int[]> -State <string> [-DurationMs <int>]
Set-PsGadgetGpio -SerialNumber <string> -Pins <int[]> -State <string> [-DurationMs <int>]
Set-PsGadgetGpio -Connection <object> -Pins <int[]> -State <string> [-DurationMs <int>]
Set-PsGadgetGpio -PsGadget <PsGadgetFtdi> -Pins <int[]> -State <string> [-DurationMs <int>]
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Index | int | Zero-based device index |
| SerialNumber | string | Device serial number |
| Connection | object | Open connection from `Connect-PsGadgetFtdi` |
| PsGadget | PsGadgetFtdi | Object from `New-PsGadgetFtdi` |
| Pins | int[] | Pin numbers to set (e.g. `@(0, 1)`) |
| State | string | `HIGH` or `LOW` |
| DurationMs | int | If set, pin returns to opposite state after this many ms |

**Pin numbering:**
- FT232H: ACBUS0 = 0, ACBUS1 = 1, ... ACBUS7 = 7
- FT232R: CBUS0 = 0, CBUS1 = 1, CBUS2 = 2, CBUS3 = 3

### Set-PsGadgetFt232rCbusMode

Programs the FT232R EEPROM to enable CBUS bit-bang mode. Run once per device.
Prompts to cycle the USB port automatically after writing.

```powershell
Set-PsGadgetFt232rCbusMode -Index <int> [-Pins <int[]>] [-Mode <string>] [-HighDriveIOs <bool>] [-PullDownEnable <bool>] [-RIsD2XX <bool>]
Set-PsGadgetFt232rCbusMode -SerialNumber <string> [-Pins <int[]>] [-Mode <string>] [-HighDriveIOs <bool>] [-PullDownEnable <bool>] [-RIsD2XX <bool>]
Set-PsGadgetFt232rCbusMode -PsGadget <PsGadgetFtdi> [-Pins <int[]>] [-Mode <string>] [-HighDriveIOs <bool>] [-PullDownEnable <bool>] [-RIsD2XX <bool>]
```

**Parameters** (one device selector required):

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Index | int | -- | Zero-based device index |
| SerialNumber | string | -- | Device serial number |
| PsGadget | PsGadgetFtdi | -- | Connected device object |
| Pins | int[] | @(0,1,2,3) | CBUS pins to configure (0-4; only 0-3 are runtime-driveable) |
| Mode | string | `FT_CBUS_IOMODE` | CBUS function to assign to all specified pins |
| HighDriveIOs | bool | from config | 8 mA drive strength (default 4 mA) |
| PullDownEnable | bool | from config | Weak pull-downs during USB suspend |
| RIsD2XX | bool | from config | D2XX-only enumeration (suppresses duplicate COM port) |

**Valid `-Mode` values**: `FT_CBUS_IOMODE`, `FT_CBUS_TXLED`, `FT_CBUS_RXLED`,
`FT_CBUS_TXRXLED`, `FT_CBUS_PWREN`, `FT_CBUS_SLEEP`, `FT_CBUS_CLK48`,
`FT_CBUS_CLK24`, `FT_CBUS_CLK12`, `FT_CBUS_CLK6`, `FT_CBUS_TXDEN`,
`FT_CBUS_BITBANG_WR`, `FT_CBUS_BITBANG_RD`

**Notes**: Supports `-WhatIf`. Windows + D2XX only. Replug (or accept the CyclePort prompt) required for changes to take effect.

---

## SSD1306 OLED display

### Connect-PsGadgetSsd1306

Connects to an SSD1306 display over I2C via an FTDI device.

```powershell
Connect-PsGadgetSsd1306 -FtdiDevice <object> [-Address <byte>] [-Force]
Connect-PsGadgetSsd1306 -PsGadget <PsGadgetFtdi> [-Address <byte>] [-Force]
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| FtdiDevice | object | -- | Raw connection from `Connect-PsGadgetFtdi` |
| PsGadget | PsGadgetFtdi | -- | Object from `New-PsGadgetFtdi`; uses cached display via `GetDisplay()` |
| Address | byte | 0x3C | I2C address (0x3C standard; 0x3D if ADDR pin pulled high) |
| Force | switch | -- | Re-initialize even if a display object is already cached |

### Clear-PsGadgetSsd1306

Clears the SSD1306 display. Without `-Page`, clears all 8 pages.

```powershell
Clear-PsGadgetSsd1306 -Display <object> [-Page <int>]
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Display | object | Display object from `Connect-PsGadgetSsd1306` |
| Page | int | Optional. Clear only this page row (0-7). Omit to clear entire display. |

### Write-PsGadgetSsd1306

Writes text to a page of the SSD1306 display.

```powershell
Write-PsGadgetSsd1306 -Display <object> -Text <string> -Page <int> [-Align <string>] [-FontSize <int>] [-Invert]
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Display | object | required | Display object from `Connect-PsGadgetSsd1306` |
| Text | string | required | Text to render |
| Page | int | required | Page row 0-7 (0 = top, 7 = bottom) |
| Align | string | `left` | Text alignment: `left`, `center`, or `right` |
| FontSize | int | 1 | Font scale: 1 = normal (6x8), 2 = double-wide |
| Invert | switch | -- | Render as dark text on white background |

### Set-PsGadgetSsd1306Cursor

Sets the cursor position on the SSD1306 display.

```powershell
Set-PsGadgetSsd1306Cursor -Display <object> -Page <int> -Column <int>
```

---

## MicroPython

### List-PsGadgetMpy

Lists available serial ports. With `-Detailed`, adds VID/PID and board
identification via WMI (Windows) or port metadata (Unix).

```powershell
List-PsGadgetMpy [-Detailed]
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Detailed | switch | Return enriched objects with VID, PID, Manufacturer, IsMicroPython |

### Connect-PsGadgetMpy

Connects to a MicroPython board over serial REPL.

```powershell
Connect-PsGadgetMpy -SerialPort <string>
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| SerialPort | string | Port name (`COM3`, `/dev/ttyUSB0`, etc.) |

**Returns**: `PsGadgetMpy` object. Call `.Invoke(code)` to execute MicroPython,
`.GetInfo()` for device details, `.PushFile(path)` to upload a file.

---

## Configuration

### Get-PsGadgetConfig

Returns the current user configuration.

```powershell
Get-PsGadgetConfig [-Section <string>]
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Section | string | Optional. Return only this config section (e.g. `ftdi`, `logging`) |

**Returns**: `PSCustomObject` (full config) or section sub-object.

### Set-PsGadgetConfig

Sets a configuration key.

```powershell
Set-PsGadgetConfig -Key <string> -Value <object>
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| Key | string | Dot-path key: `ftdi.highDriveIOs`, `logging.level`, etc. |
| Value | object | New value. PowerShell type-coerces bool and int automatically. |

---

## Aliases

| Alias | Resolves to |
|-------|-------------|
| `Test-PsGadgetSetup` | `Test-PsGadgetEnvironment` |
