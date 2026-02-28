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
$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()

if (-not $dev.IsOpen) {
    Write-Error "Failed to open device. Check USB and index."
    return
}

Write-Host ("Connected: {0} [{1}]" -f $dev.Description, $dev.Type)
```

> **Scripter**: In long-running scripts, prefer `-SerialNumber` or `-LocationId` over
> `-Index` so the reference stays stable when the USB hub order changes:
>
> ```powershell
> $dev = New-PsGadgetFtdi -SerialNumber "FT4ABCDE"
> $dev = New-PsGadgetFtdi -LocationId 197634
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

## Step 4 - Initialize the Display

### Option A: shorthand Display() method

The simplest way -- no separate `$display` object needed:

```powershell
$dev.Display("Hello World")          # page 0, address 0x3C
$dev.Display("PS Summit 2026!", 2)   # page 2
$dev.Display("Alt addr", 0, 0x3D)   # different I2C address
```

`Display()` lazily connects and initializes the SSD1306 on the first call and reuses the
connection on subsequent calls.

> **Scripter**: `Display()` is the fastest way to get text on screen. Use Option B when
> you need to clear individual pages, control alignment/font size, or manage the display
> object directly.

### Option B: explicit display object

```powershell
$display = Connect-PsGadgetSsd1306 -PsGadget $dev

# If your module uses 0x3D:
$display = Connect-PsGadgetSsd1306 -PsGadget $dev -Address 0x3D

if (-not $display) {
    Write-Error "SSD1306 init failed. Check wiring and I2C address."
    $dev.Close()
    return
}

Write-Host ("SSD1306 ready - address 0x{0:X2}, {1} glyphs loaded" -f `
    $display.I2CAddress, $display.Glyphs.Count)
```

> **Beginner**: If you see "SSD1306 init failed", check your four wires. The most common
> mistake is swapping SCL and SDA (ADBUS0 and ADBUS1).

---

## Step 5 - Clear the Display

Always clear the display before writing new content to avoid leftover pixels.

### Option A: shorthand ClearDisplay() method

```powershell
$dev.ClearDisplay()      # clear all pages
$dev.ClearDisplay(3)     # clear only page 3
```

Lazily inits the display (same as `Display()`) -- no separate object needed.

### Option B: explicit display object

```powershell
Clear-PsGadgetSsd1306 -Display $display
```

Clear only a single page row (faster than clearing the whole screen):

```powershell
Clear-PsGadgetSsd1306 -Display $display -Page 3
```

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
Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text "PSGadget"                              -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "Hello World"                           -Page 1
Write-PsGadgetSsd1306 -Display $display -Text ("Date: " + (Get-Date -f "yyyy-MM-dd")) -Page 3
```

> **Beginner**: `-Page` is just which row of the screen to write on. Page 0 is the top row,
> page 7 is the bottom. `-Align center` centers the text horizontally.

### Text alignment

```powershell
Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text "left"   -Page 1 -Align left
Write-PsGadgetSsd1306 -Display $display -Text "center" -Page 3 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "right"  -Page 5 -Align right
```

### Large text (double-width font)

`-FontSize 2` doubles each column horizontally, giving 12-pixel-wide characters.
It occupies one page (8px tall) and roughly 10-11 characters per row.

```powershell
Write-PsGadgetSsd1306 -Display $display -Text "BIG" -Page 0 -Align center -FontSize 2
```

### Inverted text (dark on white)

`-Invert` flips all pixel values in the page before sending so text appears as
dark characters on a white background.

```powershell
Write-PsGadgetSsd1306 -Display $display -Text "ALARM" -Page 4 -Align center -Invert
```

> **Engineer**: Inversion is applied in software before the byte array is sent. The SSD1306
> hardware inversion command (0xA7) inverts the entire display; PSGadget's `-Invert` is
> per-write, which allows mixed normal and inverted rows simultaneously.

---

## Step 7 - Live Clock Example

```powershell
Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text "Live Clock" -Page 0 -Align center

for ($i = 0; $i -lt 10; $i++) {
    Clear-PsGadgetSsd1306 -Display $display -Page 3
    Write-PsGadgetSsd1306 -Display $display -Text (Get-Date -Format "HH:mm:ss") `
        -Page 3 -Align center -FontSize 2
    Start-Sleep -Seconds 1
}
```

Same loop using the shorthand (no separate `$display` needed):

```powershell
for ($i = 0; $i -lt 10; $i++) {
    $dev.ClearDisplay(3)
    $dev.Display((Get-Date -Format "HH:mm:ss"), 3)
    Start-Sleep -Seconds 1
}
```

> **Scripter**: Clear only the target page before each update to avoid ghosting while
> keeping other rows intact. Writing the full display every second causes visible flicker.

---

## Step 8 - Scrolling Status Display

Write multiple status lines pulled from live system data:

```powershell
Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text "-- STATUS --" -Page 0 -Align center

$lines = @(
    "CPU: (Get-WmiObject Win32_Processor | Select -Expand LoadPercentage)%",
    ("MEM: {0}MB free" -f [Math]::Round((Get-WmiObject Win32_OS).FreePhysicalMemory / 1024)),
    ("Time: " + (Get-Date -Format "HH:mm:ss"))
)

for ($i = 0; $i -lt $lines.Count; $i++) {
    Write-PsGadgetSsd1306 -Display $display -Text $lines[$i] -Page ($i + 2)
}
```

> **Pro**: SSD1306 hardware scrolling commands (continuous scroll, diagonal scroll) are
> not yet implemented in PSGadget. Implement via MPSSE raw write if needed.

---

## Step 9 - Cursor Positioning for Raw Layout

```powershell
Set-PsGadgetSsd1306Cursor -Display $display -Column 64 -Page 3
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

## Complete Script

```powershell
#Requires -Version 5.1

Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force -DisableNameChecking

# 1. Connect FTDI
$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()

if (-not $dev.IsOpen) { Write-Error "Failed to open device."; return }

# 2. Scan I2C bus to confirm display is present
$scan = $dev.Scan()
if (-not ($scan | Where-Object Address -eq 0x3C)) {
    Write-Warning "SSD1306 not found at 0x3C. Check wiring. Scan results:"
    $scan | Format-Table
}

try {
    # 3. Shorthand: Display() and ClearDisplay() - init happens automatically on first call
    $dev.Display("PSGadget", 0)
    $dev.Display("SSD1306 via I2C", 1)
    Start-Sleep -Seconds 2
    $dev.ClearDisplay()    # clear all pages before handing off to explicit object

    # 4. Explicit display object for full control
    $display = Connect-PsGadgetSsd1306 -PsGadget $dev
    if (-not $display) { Write-Error "SSD1306 init failed."; return }

    Clear-PsGadgetSsd1306 -Display $display
    Write-PsGadgetSsd1306 -Display $display -Text "Clock" -Page 0 -Align center

    for ($i = 0; $i -lt 10; $i++) {
        Clear-PsGadgetSsd1306 -Display $display -Page 3
        Write-PsGadgetSsd1306 -Display $display -Text (Get-Date -Format "HH:mm:ss") `
            -Page 3 -Align center -FontSize 2
        Start-Sleep -Seconds 1
    }

    Clear-PsGadgetSsd1306 -Display $display
    Write-PsGadgetSsd1306 -Display $display -Text "Done." -Page 3 -Align center

} finally {
    $dev.Close()
    Write-Host "Device closed."
}
```

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
$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()

# Scan I2C bus
$dev.Scan() | Format-Table

# Shorthand display and clear (lazy init at 0x3C)
$dev.Display("Hello World")           # page 0
$dev.Display("line 2", 2)             # page 2
$dev.Display("alt addr", 0, 0x3D)     # alternate I2C address
$dev.ClearDisplay()                   # clear all pages
$dev.ClearDisplay(2)                  # clear only page 2

# Explicit display object
$d = Connect-PsGadgetSsd1306 -PsGadget $dev
Clear-PsGadgetSsd1306 -Display $d
Write-PsGadgetSsd1306 -Display $d -Text "Hello"  -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $d -Text "BIG"    -Page 2 -FontSize 2
Write-PsGadgetSsd1306 -Display $d -Text "ALERT"  -Page 4 -Invert
Clear-PsGadgetSsd1306 -Display $d -Page 1

# Cursor
Set-PsGadgetSsd1306Cursor -Display $d -Column 32 -Page 3

# Close
$dev.Close()
```
