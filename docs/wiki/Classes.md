# PSGadget Class Reference

Reference for classes exposed by PSGadget. Create instances via the
corresponding `New-*` or `Connect-*` cmdlets -- do not call `::new()` directly.

---

## PsGadgetFtdi

Represents an open connection to an FTDI device. Create with `New-PsGadgetFtdi`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| Index | int | Zero-based index of this device |
| SerialNumber | string | Device serial number |
| LocationId | string | USB hub+port address |
| Description | string | USB device description string |
| Type | string | Chip type string (e.g. `FT232H`, `FT232R`) |
| GpioMethod | string | `MPSSE`, `CBUS`, or `AsyncBitBang` |
| IsOpen | bool | True if connection is open |
| Logger | PsGadgetLogger | Per-instance logger |

### Methods

#### Connect

```powershell
$dev.Connect()
```

Re-opens the device after `Close()`. No-op if already open.

#### Close

```powershell
$dev.Close()
```

Closes the device connection and releases the handle.

#### SetPin

```powershell
$dev.SetPin([int]$pin, [string]$state)   # state: HIGH/LOW/H/L/1/0
$dev.SetPin([int]$pin, [bool]$high)
```

Sets a single GPIO pin. Uses read-modify-write to preserve other pin states.

#### SetPins

```powershell
$dev.SetPins([int[]]$pins, [string]$state)
$dev.SetPins([int[]]$pins, [bool]$high)
```

Sets multiple GPIO pins to the same state in a single operation.

#### PulsePin

```powershell
$dev.PulsePin([int]$pin, [string]$state, [int]$durationMs)
```

Sets a pin to `state`, waits `durationMs` milliseconds, then sets it to the
opposite state.

#### GetDisplay

```powershell
$dev.GetDisplay()                    # default address 0x3C
$dev.GetDisplay([byte]$address)
```

Returns (and caches) a `PsGadgetSsd1306` instance. Subsequent calls return
the same cached object unless the connection is recreated or a different
address is requested with `GetDisplay([byte]$address)`.
FT232H (MPSSE) only.

#### Display

```powershell
$dev.Display([string]$text)
$dev.Display([string]$text, [int]$page)
$dev.Display([string]$text, [int]$page, [byte]$address)
```

Convenience shortcut: writes text to an SSD1306 on the I2C bus without
having to manage the display object. Calls `GetDisplay()` internally.
FT232H (MPSSE) only.

#### ClearDisplay

```powershell
$dev.ClearDisplay()                           # clears all 8 pages
$dev.ClearDisplay([int]$page)                 # clears one page
$dev.ClearDisplay([int]$page, [byte]$address) # specific I2C address
```

Clears the SSD1306 display. FT232H (MPSSE) only.

#### Scan

```powershell
$dev.Scan()
```

Performs an I2C bus scan. Returns an array of 7-bit addresses that responded
with ACK. FT232H (MPSSE) only.

#### Reset

```powershell
$dev.Reset()
```

Issues a D2XX `ResetDevice()` -- clears internal buffers and restores chip
state without closing the handle.

#### CyclePort

```powershell
$dev.CyclePort()
```

Triggers a USB port cycle (equivalent to a physical replug). Automatically
reconnects after re-enumeration. Use after writing EEPROM to apply changes
without manually unplugging the cable. Windows only.

#### Write

```powershell
$dev.Write([byte[]]$data)
```

Writes raw bytes to the device. For low-level MPSSE command sequences.

#### Read

```powershell
$dev.Read([int]$count)
```

Reads `count` bytes from the device. Returns `byte[]`.

---

## PsGadgetSsd1306

Represents a connected SSD1306 OLED display. Create via
`New-PsGadgetFtdi` then `$dev.GetDisplay()`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| I2CAddress | byte | I2C address (default 0x3C) |
| Width | int | Display width in pixels (128) |
| Height | int | Display height in pixels (64) |
| Pages | int | Number of pages (8) |
| IsInitialized | bool | True after display init sequence completes |

### Methods

#### WriteText

```powershell
$display.WriteText([string]$text, [int]$page)
$display.WriteText([string]$text, [int]$page, [string]$align)
$display.WriteText([string]$text, [int]$page, [string]$align, [int]$fontSize, [bool]$invert)
```

Renders text to the specified page row (0-7). `align` is `left`, `center`,
or `right`. `fontSize` 1 = normal 6x8, 2 = double-wide. `invert` renders dark
text on white background.

#### Clear

```powershell
$display.Clear()
```

Clears all 8 pages.

#### ClearPage

```powershell
$display.ClearPage([int]$page)
```

Clears a single page row (0-7).

#### SetCursor

```powershell
$display.SetCursor([int]$column, [int]$page)
```

Sets the write cursor to a column and page position.

#### Initialize

```powershell
$display.Initialize()
$display.Initialize([bool]$force)
```

Sends the SSD1306 initialization command sequence. Called automatically on
construction. Pass `$true` to force re-initialization.

---

## PsGadgetMpy

Represents an open MicroPython serial REPL connection. Create with `Connect-PsGadgetMpy`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| SerialPort | string | Port name (`COM3`, `/dev/ttyUSB0`, etc.) |

### Methods

#### GetInfo

```powershell
$mpy.GetInfo()
```

Returns a hashtable with `Port`, `PythonVersion`, `Board`, `ChipFamily`,
`FreeMemory`, `Connected`, `Stub`. Calls `mpremote` on the live board;
returns stub values when `mpremote` is not in PATH.

#### Invoke

```powershell
$mpy.Invoke([string]$code)
```

Executes a MicroPython code string on the connected board via `mpremote exec`
and returns stdout as a string. Throws on non-zero exit.

#### PushFile

```powershell
$mpy.PushFile([string]$localPath)
$mpy.PushFile([string]$localPath, [string]$remotePath)
```

Copies a local file to the board via `mpremote cp`. When `remotePath` is
omitted, defaults to the filename portion of `localPath`.

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
