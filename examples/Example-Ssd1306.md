# Example: SSD1306 OLED Display via FT232H I2C

Drive a 128x64 SSD1306 OLED display from a Windows PC using an FT232H USB adapter.
PSGadget automatically selects the best backend for your PowerShell version:
FtdiSharp on PS 5.1, .NET IoT on PS 7.

---

## Who This Is For

- **Beginner** - new to electronics, I2C, and PowerShell
- **Scripter** - comfortable with PowerShell, new to hardware buses and FTDI
- **Engineer** - familiar with I2C and electronics, less familiar with the Windows driver
  stack and PowerShell module system
- **Pro** - experienced with both; skip to the Quick Reference at the bottom

---

## What You Need

- An FT232H USB adapter (any breakout; must have MPSSE -- verify with `HasMpsse = True`)
- An SSD1306 128x64 I2C OLED module (0.96" or 1.3", common on Amazon / eBay)
- 4 jumper wires
- Windows PC with FTDI CDM drivers installed, USB cable
- PowerShell 5.1 or 7.x
- PSGadget module cloned locally

> **Beginner**: The FT232H is a USB adapter chip that speaks multiple hardware protocols.
> The SSD1306 is the driver chip inside a small black OLED screen -- the same kind seen
> on Arduino starter kits. Instead of an Arduino, we connect it directly to the PC's USB
> port through the FT232H.

---

## Hardware Background

> **Engineer**: The FT232H includes the MPSSE (Multi-Protocol Synchronous Serial Engine),
> a hardware block that implements I2C, SPI, and JTAG. On PS 5.1, PSGadget uses the
> FtdiSharp library which wraps D2XX and handles MPSSE setup internally. On PS 7, PSGadget
> uses the .NET IoT `Iot.Device.Ft232H` binding. Both backends use ADBUS0 as SCL and
> ADBUS1 as SDA at 100 kHz standard mode.
>
> The SSD1306 is a write-only I2C peripheral. PSGadget does not need to implement I2C read
> for display purposes. The initialization sequence sets contrast, scan direction, and
> blanks the GDDRAM before the first write.

### I2C address

| ADDR pin state | I2C address |
|---|---|
| Pulled LOW (default on most modules) | 0x3C |
| Pulled HIGH | 0x3D |

Check your module's datasheet or silkscreen. Most cheap 0.96" modules are fixed at 0x3C.

---

## Hardware Wiring

Connect four wires between the FT232H breakout and the SSD1306 module:

| FT232H pin | MPSSE function | SSD1306 pin |
|---|---|---|
| ADBUS0 | TCK / SCK | SCL |
| ADBUS1 | TDI / DO  | SDA |
| 3.3V   | Power     | VCC |
| GND    | Ground    | GND |

> **Beginner**: Look for pin labels printed on your FT232H board. ADBUS0 and ADBUS1 are
> usually the first two pins in a row. The SSD1306 has 4 pins labeled SCL, SDA, VCC, GND.

> **Engineer**: The FT232H I/O is 3.3V. Most SSD1306 modules accept 3.3V logic.
> FtdiSharp and .NET IoT both drive SCL/SDA as push-pull outputs (not strict open-drain),
> which works reliably for short wires to a single peripheral. Keep wires under 20 cm.

---

## Step 1 - Load the Module and Verify Detection

```powershell
Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force -DisableNameChecking

List-PsGadgetFtdi | Format-Table Index, Type, SerialNumber, LocationId, HasMpsse
```

Expected output:

```
Index  Type    SerialNumber  LocationId  HasMpsse
-----  ----    ------------  ----------  --------
  0    FT232H  FT4ABCDE      197634      True
```

You need a row with `HasMpsse = True`. If you see `FT232R` with `HasMpsse = False`, that
device cannot drive the SSD1306 -- you need an FT232H.

> **Beginner**: "HasMpsse" means the chip has the special hardware inside that speaks I2C.
> The FT232H has it. The FT232R does not. Make sure your adapter's Type column shows FT232H.

---

## Step 2 - Connect the Device

```powershell
$dev = New-PsGadgetFtdi -Index 0   # connected immediately - no .Connect() needed

if (-not $dev.IsOpen) {
    Write-Error "Failed to open device. Check USB and index."
    return
}

Write-Host ("Connected: {0} [{1}]" -f $dev.Description, $dev.Type)
```

`New-PsGadgetFtdi` follows the MicroPython convention: construction implies connection.
The device is open and ready to use on the line immediately after.

> **Scripter**: In long-running scripts, prefer `-SerialNumber` or `-LocationId` over
> `-Index` so the reference stays stable when the USB hub order changes:
>
> ```powershell
> $dev = New-PsGadgetFtdi -SerialNumber "FT4ABCDE"   # stable across hub reorder
> $dev = New-PsGadgetFtdi -LocationId 197634          # stable for fixed physical port
> ```

---

## Step 3 - Scan the I2C Bus (recommended)

Before initializing the display, confirm it is visible on the bus:

```powershell
$dev.Scan() | Format-Table

# Expected:
# Address  Hex
# -------  ---
#      60  0x3C
```

> **Scripter**: `Scan()` probes addresses 0x08 through 0x77. If nothing appears, check
> your VCC/GND wires first, then SCL/SDA. If you see 0x3D instead of 0x3C, pass
> `-Address 0x3D` in the next step.

> **Engineer**: On PS 5.1, `Scan()` calls `[FtdiSharp.Protocols.I2C]::new(device).Scan()`
> which returns `byte[]` of ACK'd addresses. On PS 7, it calls
> `Iot.Device.Ft232H.Ft232HDevice.CreateOrGetI2cBus()` and probes each address with a
> `ReadByte()` -- NACK throws and is caught silently as no-device. Both paths are
> selected automatically.

---

## Step 4 - Write to the Display

Two functions, pick based on what you need:

| Need | Use |
|---|---|
| Just write a line of text | `$dev.Display("text", page)` |
| Alignment, font size, or invert | `$dev.GetDisplay()` then `Write-PsGadgetSsd1306` |

### Simple text

```powershell
$dev.Display("Hello World")          # page 0, address 0x3C
$dev.Display("PS Summit 2026!", 2)   # page 2
$dev.Display("Alt addr", 0, 0x3D)   # different I2C address
```

The display is initialized on the first call and reused on all subsequent calls.

### Advanced formatting

`GetDisplay()` returns the cached display object (initializing it on first call).
Use it when you need alignment, larger text, or inverted rows:

```powershell
$d = $dev.GetDisplay()               # init once, reuse every call
Write-PsGadgetSsd1306 -Display $d -Text "PSGadget"  -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $d -Text "12:34:56"  -Page 2 -Align center -FontSize 2
Write-PsGadgetSsd1306 -Display $d -Text "ALARM"     -Page 6 -Align center -Invert
```

> **Beginner**: `$dev.GetDisplay()` just gives you a handle to the screen. Think of it
> like opening a file before you can format what's written in it. `$dev.Display()` is the
> shortcut that does everything in one step but without formatting options.

> **Scripter**: `$dev.GetDisplay()` and `$dev.Display()` share the same underlying
> connection object -- calling either one first is fine. No re-init, no conflicts.

> **Engineer**: `GetDisplay()` returns `$dev._display` (a `PsGadgetSsd1306` instance with
> the FtdiSharp or IoT I2C handle baked in). Both `Display()` and `ClearDisplay()` call
> `GetDisplay()` internally, so there is only ever one I2C handle per device.

---

## Step 5 - Clear the Display

Always clear before writing new content to avoid leftover pixels.

```powershell
$dev.ClearDisplay()      # clear all 8 pages
$dev.ClearDisplay(3)     # clear only page 3 (faster for live updates)
```

If you already have `$d` from `GetDisplay()`, you can also call the function directly:

```powershell
Clear-PsGadgetSsd1306 -Display $d           # clear all pages
Clear-PsGadgetSsd1306 -Display $d -Page 3   # clear one page
```

Both operate on the same cached object -- use whichever is more readable in context.

> **Engineer**: The SSD1306 128x64 frame buffer is organized as 8 horizontal pages (rows),
> each 8 pixels tall and 128 bytes wide. One byte per column, one bit per pixel row.
> `Clear-PsGadgetSsd1306` writes 0x00 to every byte in the target page(s).

---

## Step 6 - Write Text

### Display layout reference

| Page | Pixel rows | Approx use |
|---|---|---|
| 0 | 0 - 7   | Header / title |
| 1 | 8 - 15  | Status line 1 |
| 2 | 16 - 23 | Status line 2 |
| 3 | 24 - 31 | Status line 3 |
| 4 | 32 - 39 | Status line 4 |
| 5 | 40 - 47 | Status line 5 |
| 6 | 48 - 55 | Status line 6 |
| 7 | 56 - 63 | Footer |

The built-in font is 6x8 pixels per character, giving up to ~21 characters per row.

```powershell
$d = $dev.GetDisplay()
$dev.ClearDisplay()
Write-PsGadgetSsd1306 -Display $d -Text "PSGadget"                              -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $d -Text "Hello World"                           -Page 1
Write-PsGadgetSsd1306 -Display $d -Text ("Date: " + (Get-Date -f "yyyy-MM-dd")) -Page 3
```

> **Beginner**: `-Page` is just which row of the screen to write on. Page 0 is the top row,
> page 7 is the bottom. `-Align center` centers the text horizontally.

### Text alignment

```powershell
$d = $dev.GetDisplay()
$dev.ClearDisplay()
Write-PsGadgetSsd1306 -Display $d -Text "left"   -Page 1 -Align left
Write-PsGadgetSsd1306 -Display $d -Text "center" -Page 3 -Align center
Write-PsGadgetSsd1306 -Display $d -Text "right"  -Page 5 -Align right
```

### Large text (double-width font)

`-FontSize 2` doubles each column horizontally, giving 12-pixel-wide characters.
It occupies one page (8px tall) and roughly 10-11 characters per row.

```powershell
Write-PsGadgetSsd1306 -Display $d -Text "BIG" -Page 0 -Align center -FontSize 2
```

### Inverted text (dark on white)

`-Invert` flips all pixel values in the page before sending so text appears as
dark characters on a white background.

```powershell
Write-PsGadgetSsd1306 -Display $d -Text "ALARM" -Page 4 -Align center -Invert
```

> **Engineer**: Inversion is applied in software before the byte array is sent. The SSD1306
> hardware inversion command (0xA7) inverts the entire display; PSGadget's `-Invert` is
> per-write, which allows mixed normal and inverted rows simultaneously.

---

## Step 7 - Live Clock Example

```powershell
$d = $dev.GetDisplay()
$dev.ClearDisplay()
Write-PsGadgetSsd1306 -Display $d -Text "Live Clock" -Page 0 -Align center

$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
    $dev.ClearDisplay(3)
    Write-PsGadgetSsd1306 -Display $d -Text (Get-Date -Format "HH:mm:ss") `
        -Page 3 -Align center -FontSize 2
    Start-Sleep -Milliseconds 500
}
```

> **Scripter**: Update twice per second (`500ms`) to stay current — `ClearDisplay` + `Write` takes
> ~300-500ms over I2C, so `Start-Sleep -Seconds 1` will visibly skip every other second.

---

## Step 8 - Scrolling Status Display

Write multiple status lines pulled from live system data:

```powershell
$d = $dev.GetDisplay()
$dev.ClearDisplay()
Write-PsGadgetSsd1306 -Display $d -Text "-- STATUS --" -Page 0 -Align center

$lines = @(
    "CPU: (Get-WmiObject Win32_Processor | Select -Expand LoadPercentage)%",
    ("MEM: {0}MB free" -f [Math]::Round((Get-WmiObject Win32_OS).FreePhysicalMemory / 1024)),
    ("Time: " + (Get-Date -Format "HH:mm:ss"))
)

for ($i = 0; $i -lt $lines.Count; $i++) {
    Write-PsGadgetSsd1306 -Display $d -Text $lines[$i] -Page ($i + 2)
}
```

> **Pro**: SSD1306 hardware scrolling commands (continuous scroll, diagonal scroll) are
> not yet implemented in PSGadget. Implement via MPSSE raw write if needed.

---

## Step 9 - Cursor Positioning for Raw Layout

```powershell
Set-PsGadgetSsd1306Cursor -Display $d -Column 64 -Page 3
```

> **Engineer**: Sends command sequence: set column address (0x21, col, 127), set page
> address (0x22, page, 7). Subsequent 0x40 data bytes write directly to GDDRAM at the
> specified offset.

---

## Step 10 - Close the Connection

Always release the D2XX handle when done:

```powershell
$dev.Close()
Write-Host "Device closed."
```

> **Beginner**: The `.Close()` call tells Windows to release the USB device so other
> programs can use it. If you forget and try to reconnect, you may get a "device busy"
> error.

---

## Complete Examples

Two versions of the same clock demo. Pick the one that suits your situation.

---

### Example 1 - Standard (quiet output)

Clean console — no extra messages. Errors still surface via `Write-Error`.
This is what you use once everything is working.

```powershell
#Requires -Version 5.1

Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force -DisableNameChecking

$dev = New-PsGadgetFtdi -Index 0   # connected immediately

if (-not $dev.IsOpen) { Write-Error "Failed to open device."; return }

$scan = $dev.Scan()
if (-not ($scan | Where-Object Address -eq 0x3C)) {
    Write-Warning "SSD1306 not found at 0x3C. Check wiring."
    $scan | Format-Table
}

try {
    $dev.Display("PSGadget", 0)
    $dev.Display("SSD1306 via I2C", 1)
    Start-Sleep -Seconds 2

    $d = $dev.GetDisplay()
    $dev.ClearDisplay()
    Write-PsGadgetSsd1306 -Display $d -Text "Clock" -Page 0 -Align center

    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $dev.ClearDisplay(3)
        Write-PsGadgetSsd1306 -Display $d -Text (Get-Date -Format "HH:mm:ss") `
            -Page 3 -Align center -FontSize 2
        Start-Sleep -Milliseconds 500
    }

    $dev.ClearDisplay()
    Write-PsGadgetSsd1306 -Display $d -Text "Done." -Page 3 -Align center

} finally {
    $dev.Close()
    Write-Host "Device closed."
}
```

Expected console output (nothing but the final line):

```
Device closed.
```

---

### Example 2 - Verbose (beginner-friendly)

Adds `$VerbosePreference = 'Continue'` and `Test-PsGadgetSetup -Verbose` so every step
tells you what is happening. Use this when setting up for the first time or debugging.

```powershell
#Requires -Version 5.1

$VerbosePreference = 'Continue'   # turn on VERBOSE: messages for this session

Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force -DisableNameChecking

# Check that the environment, driver, and device are all healthy before doing anything
$setup = Test-PsGadgetSetup -Verbose
if (-not $setup.IsReady) {
    Write-Warning "Setup check failed. Fix the issues above before continuing."
    return
}

# List devices so Verbose shows the connect hint automatically
List-PsGadgetFtdi -Verbose | Format-Table Index, Type, SerialNumber, HasMpsse

$dev = New-PsGadgetFtdi -Index 0   # connected immediately - no .Connect() needed

if (-not $dev.IsOpen) { Write-Error "Failed to open device."; return }

# Scan confirms the display is visible on the I2C bus
$scan = $dev.Scan()
$scan | Format-Table

if (-not ($scan | Where-Object Address -eq 0x3C)) {
    Write-Warning "SSD1306 not found at 0x3C. Check wiring."
    return
}

try {
    $dev.Display("PSGadget", 0)
    $dev.Display("SSD1306 via I2C", 1)
    Start-Sleep -Seconds 2

    $d = $dev.GetDisplay()
    $dev.ClearDisplay()
    Write-PsGadgetSsd1306 -Display $d -Text "Clock" -Page 0 -Align center -Verbose

    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $dev.ClearDisplay(3)
        Write-PsGadgetSsd1306 -Display $d -Text (Get-Date -Format "HH:mm:ss") `
            -Page 3 -Align center -FontSize 2 -Verbose
        Start-Sleep -Milliseconds 500
    }

    $dev.ClearDisplay()
    Write-PsGadgetSsd1306 -Display $d -Text "Done." -Page 3 -Align center -Verbose

} finally {
    $dev.Close()
    Write-Host "Device closed."
}
```

Expected console output (abbreviated):

```
PsGadget Setup Check
----------------------------------------------------
Platform  : Windows / PS 7.5.4 / .NET 9.0.x
Backend   : FtdiSharp (D2XX / PS 5.1) -or- IoT (Iot.Device.Bindings / PS 7)
Native lib: [OK] FTD2XX.dll
Devices   : 1 device(s) found
Config    : [OK] C:\Users\you\.psgadget\config.json
----------------------------------------------------
  [0] FT232H     SN=FT4ABCDE    GPIO=MPSSE
Status    : READY
VERBOSE: All checks passed. Hardware is ready.
VERBOSE: Quick start: List-PsGadgetFtdi | Format-Table
VERBOSE: Then:        $dev = New-PsGadgetFtdi -SerialNumber <SN>

VERBOSE:   [0] FT232H  SN=FT4ABCDE  -> $dev = New-PsGadgetFtdi -SerialNumber 'FT4ABCDE'
VERBOSE:       I2C scan: $dev.Scan()
VERBOSE:       Display : $dev.Display('Hello world', 0)

VERBOSE: Text 'Clock' written to SSD1306 page 0
VERBOSE: Text '14:23:01' written to SSD1306 page 3
...
Device closed.
```

> **Beginner**: `$VerbosePreference = 'Continue'` is a session-wide switch that tells
> PSGadget (and any PowerShell command) to print its internal progress messages. Set it
> back to `'SilentlyContinue'` (the default) once you are comfortable with the workflow.

> **Scripter**: You can also pass `-Verbose` to individual commands rather than setting
> the preference globally. This lets you be selective about which steps surface detail.

---

## Troubleshooting

### Display stays blank after init

- Check all four wires (SCL, SDA, VCC, GND)
- Most common mistake: ADBUS0/ADBUS1 swapped (SCL and SDA reversed)
- Run `$dev.Scan()` -- if no output, I2C bus is dead (wiring issue)
- Try `-Address 0x3D` if scan shows 0x3D instead of 0x3C

### "Failed to open device"

- Another application may hold the D2XX handle
- Close any serial terminal (PuTTY, TeraTerm) pointing at the COM port
- Unplug and replug the USB cable

### Scan returns nothing

- Check VCC and GND first -- display may be unpowered
- Confirm `HasMpsse = True` via `List-PsGadgetFtdi`
- Reseat all four jumper wires

### Partial or garbled text

- Loose SCL wire causes clock glitches -- reseat connectors
- Keep wires under 20 cm to avoid capacitance at 100 kHz

### PS version differences

PSGadget auto-selects the backend -- no configuration needed:

| PS Version | Backend used | Source |
|---|---|---|
| 5.1 | FtdiSharp `Protocols.I2C` | `lib/ftdisharp/FtdiSharp.dll` |
| 7.x | .NET IoT `Iot.Device.Ft232H` | `lib/net8/` |

---

## Quick Reference (Pro)

```powershell
# Load and connect
Import-Module .\PSGadget.psd1 -DisableNameChecking
$dev = New-PsGadgetFtdi -Index 0   # connected immediately

# Scan I2C bus
$dev.Scan() | Format-Table

# Simple text -- no display object needed
$dev.Display("Hello World")           # page 0, default 0x3C
$dev.Display("line 2", 2)             # specific page
$dev.Display("alt addr", 0, 0x3D)     # alternate address
$dev.ClearDisplay()                   # clear all pages
$dev.ClearDisplay(2)                  # clear one page

# Advanced formatting -- GetDisplay() returns the same cached object
$d = $dev.GetDisplay()                # (or GetDisplay(0x3D) for alternate address)
Write-PsGadgetSsd1306 -Display $d -Text "Hello"  -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $d -Text "BIG"    -Page 2 -Align center -FontSize 2
Write-PsGadgetSsd1306 -Display $d -Text "ALERT"  -Page 4 -Align center -Invert
Clear-PsGadgetSsd1306 -Display $d -Page 1

# Cursor
Set-PsGadgetSsd1306Cursor -Display $d -Column 32 -Page 3

# Close
$dev.Close()
```
