# PSGadget Class Reference

Reference for classes exposed by PSGadget. Create instances via the
corresponding `New-*` or `Connect-*` cmdlets -- do not call `::new()` directly.

---

## PsGadgetFtdi

Represents an open connection to an FTDI device. Create with `New-PsGadgetFtdi`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| DeviceIndex | int | Zero-based index of this device |
| SerialNumber | string | Device serial number |
| DeviceType | string | Chip type string (e.g. `FT232H`) |
| IsOpen | bool | True if connection is open |
| GpioMethod | string | `MPSSE`, `CBUS`, or `AsyncBitBang` |

### Methods

#### SetPin

```powershell
$dev.SetPin([int]$pinNumber, [string]$state)
```

Sets a single GPIO pin HIGH or LOW. Uses read-modify-write to preserve other
pin states.

#### SetPins

```powershell
$dev.SetPins([int[]]$pinNumbers, [string]$state)
```

Sets multiple GPIO pins to the same state in a single operation.

#### PulsePin

```powershell
$dev.PulsePin([int]$pinNumber, [string]$state, [int]$durationMs)
```

Sets a pin to `state`, waits `durationMs` milliseconds, then sets it to the
opposite state.

#### Scan

```powershell
$dev.Scan()
```

Performs an I2C bus scan and returns an array of 7-bit addresses that responded
with ACK. FT232H (MPSSE) only.

#### Display

```powershell
$dev.Display([string]$text, [int]$page)
```

Writes text to an SSD1306 display on the I2C bus at the default address (0x3C).
Convenience wrapper around `Connect-PsGadgetSsd1306` + `Write-PsGadgetSsd1306`.

#### Close

```powershell
$dev.Close()
```

Closes the device connection and releases the handle.

---

## PsGadgetSsd1306

Represents a connected SSD1306 OLED display. Create with `Connect-PsGadgetSsd1306`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| Address | byte | I2C address (default 0x3C) |
| Width | int | Display width in pixels (128) |
| Height | int | Display height in pixels (64) |
| Pages | int | Number of pages (8) |

### Methods

#### Write

```powershell
$display.Write([string]$text, [int]$page)
```

Renders text to the specified page row (0-7).

#### Clear

```powershell
$display.Clear()
```

Clears all pages.

#### SetCursor

```powershell
$display.SetCursor([int]$page, [int]$column)
```

Sets the write cursor to a page and column position.

---

## PsGadgetMpy

Represents an open MicroPython serial REPL connection. Create with `Connect-PsGadgetMpy`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| SerialPort | string | Port name |
| BaudRate | int | Baud rate |
| IsOpen | bool | True if connection is open |

### Methods

#### Invoke

```powershell
$mpy.Invoke([string]$code)
```

Executes a MicroPython code string on the connected board via mpremote and
returns the output as a string.

---

## PsGadgetLogger

Internal logging class. Every other class holds a `[PsGadgetLogger]$Logger`
member instantiated in its constructor.

### Log file location

```
~/.psgadget/logs/psgadget.log
```

Logging to file is always on. Verbose console output is controlled by
`$VerbosePreference` or `-Verbose` on cmdlets.

### Log levels

| Level | Method | When to use |
|-------|--------|-------------|
| INFO | `WriteInfo` | Significant operations (connect, close, write) |
| DEBUG | `WriteDebug` | Parameter values, decision points |
| TRACE | `WriteTrace` | Detailed flow, byte values |
| ERROR | `WriteError` | Failures before throwing |
