# Example: SSD1306 OLED Display via FT232H MPSSE I2C

Drive a 128x64 SSD1306 OLED display from a Windows PC using an FT232H USB adapter and
PSGadget's built-in MPSSE I2C bit-bang engine. No Arduino or microcontroller required.

---

## Who This Is For

- **Beginner** - new to electronics, I2C, and PowerShell
- **Scripter** - comfortable with PowerShell, new to hardware buses and FTDI MPSSE
- **Engineer** - familiar with I2C and electronics, less familiar with the Windows D2XX driver
  and PowerShell module system
- **Pro** - experienced with both; skip to the Quick Reference at the bottom

---

## What You Need

- An FT232H USB adapter (any breakout; must have MPSSE -- verify with `HasMpsse = True`)
- An SSD1306 128x64 I2C OLED module (0.96" or 1.3", common on Amazon / eBay)
- 4 jumper wires
- Windows PC with FTDI CDM drivers, USB cable
- PowerShell 5.1 or later
- PSGadget module cloned locally

> **Beginner**: The FT232H is a USB adapter chip that speaks multiple hardware protocols.
> The SSD1306 is the driver chip inside a small black OLED screen -- exactly the kind
> you see on Arduino starter kits. Instead of an Arduino, we connect it directly to the
> PC's USB port through the FT232H adapter.

---

## Hardware Background

> **Engineer**: The FT232H includes the MPSSE (Multi-Protocol Synchronous Serial Engine), a
> hardware block that implements I2C, SPI, and JTAG bit-bang in firmware. PSGadget uses
> the FTD2XX D2XX API to write raw MPSSE command sequences to the device, implementing
> an I2C master at roughly 100 kHz. The SSD1306 is a write-only I2C peripheral; PSGadget
> does not need to implement I2C read for display purposes.
>
> The SSD1306 uses a two-byte command prefix: 0x00 for command mode, 0x40 for data mode,
> followed by the payload. The initialization sequence sets contrast, scan direction, and
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

> **Beginner**: Look for the pin labels printed on your FT232H board. ADBUS0 and ADBUS1
> are usually the first two pins in a row. GND and 3.3V are usually labeled directly.
> The SSD1306 module has 4 pins; they are almost always labeled SCL, SDA, VCC, and GND.

> **Engineer**: The FT232H I/O is 3.3V. Most SSD1306 modules accept 3.3V logic levels on
> SCL/SDA. If your module has on-board level shifters, 3.3V is still safe. The VCC pin
> of most SSD1306 modules accepts 3.3V to 5V (check your module datasheet). Do not
> connect VCC to 5V I/O if the display data sheet says 3.3V max.

> **Scripter**: No pull-up resistors are required. The FT232H MPSSE engine drives SCL and
> SDA as push-pull outputs. This is not strict I2C (which requires open-drain with
> pull-ups) but it works reliably for short wires to a single peripheral.

---

## Step 1 - Install Drivers and Verify Detection

```powershell
Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force

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

## Step 2 - Connect the FTDI Device

```powershell
$dev = New-PsGadgetFtdi -Index 0    # use your FT232H index
$dev.Connect()

if (-not $dev.IsOpen) {
    Write-Error "Failed to open device. Check USB and index."
    return
}

Write-Host ("Connected: {0} [{1}]" -f $dev.Description, $dev.Type)
```

> **Scripter**: `New-PsGadgetFtdi` creates a device object. `-Index` uses the row number
> from `List-PsGadgetFtdi`. Prefer `-SerialNumber` or `-LocationId` in long-running
> scripts so the reference stays stable when other USB devices are present or the USB
> hub order changes.

```powershell
# Stable alternatives to -Index:
$dev = New-PsGadgetFtdi -SerialNumber "FT4ABCDE"
$dev = New-PsGadgetFtdi -LocationId 197634     # use LocationId from List output
```

---

## Step 3 - Initialize the Display

```powershell
$display = Connect-PsGadgetSsd1306 -PsGadget $dev

# If your module uses address 0x3D instead of 0x3C:
$display = Connect-PsGadgetSsd1306 -PsGadget $dev -Address 0x3D

if (-not $display) {
    Write-Error "SSD1306 init failed. Check wiring and I2C address."
    $dev.Close()
    return
}

Write-Host ("SSD1306 ready - address 0x{0:X2}, {1} glyphs loaded" -f `
    $display.I2CAddress, $display.Glyphs.Count)
```

> **Beginner**: If you see "SSD1306 init failed", check your four wires first. The most
> common mistake is swapping SCL and SDA.

> **Engineer**: `Connect-PsGadgetSsd1306` sends the SSD1306 initialization sequence over
> MPSSE I2C: display off, oscillator frequency, multiplex ratio, COM pin hardware config,
> memory addressing mode, and display on. If any I2C ACK is missing (wrong address or
> broken wiring) the function returns `$null`.

---

## Step 4 - Clear the Display

Always clear the display before writing new content to avoid leftover pixels.

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

## Step 5 - Write Text

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
# Basic text on specific pages
Write-PsGadgetSsd1306 -Display $display -Text "PSGadget" -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "Hello World" -Page 1
Write-PsGadgetSsd1306 -Display $display -Text ("Date: " + (Get-Date -Format "yyyy-MM-dd")) -Page 3
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

## Step 6 - Live Clock Example

Update a single page every second without re-drawing the header:

```powershell
Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text "Live Clock" -Page 0 -Align center

Write-Host "Running for 10 seconds..."

for ($i = 0; $i -lt 10; $i++) {
    $timeStr = Get-Date -Format "HH:mm:ss"
    Clear-PsGadgetSsd1306 -Display $display -Page 3
    Write-PsGadgetSsd1306 -Display $display -Text $timeStr -Page 3 -Align center -FontSize 2
    Start-Sleep -Seconds 1
}
```

> **Scripter**: Clearing only the target page before each update avoids ghosting from the
> previous value while keeping the rest of the screen intact. Writing the whole display
> every second would be slower and cause a visible flicker.

---

## Step 7 - Scrolling Status Display

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

## Step 8 - Cursor Positioning for Raw Layout

`Set-PsGadgetSsd1306Cursor` sets the column and page before the next write, allowing
precise placement without using the full `Write-PsGadgetSsd1306` text layout engine.

```powershell
Set-PsGadgetSsd1306Cursor -Display $display -Column 64 -Page 3
```

> **Engineer**: This sends the I2C command sequence: set column address (0x21, col, 127),
> set page address (0x22, page, 7). After this, sending 0x40 data bytes writes directly
> to GDDRAM at the specified offset.

---

## Step 9 - Close the Connection

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

Import-Module C:\path\to\PSGadget\PSGadget.psd1 -Force

# 1. Connect FTDI
$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()

if (-not $dev.IsOpen) {
    Write-Error "Failed to open device."
    return
}

# 2. Init display
$display = Connect-PsGadgetSsd1306 -PsGadget $dev

if (-not $display) {
    Write-Error "SSD1306 init failed."
    $dev.Close()
    return
}

try {
    # 3. Header
    Clear-PsGadgetSsd1306 -Display $display
    Write-PsGadgetSsd1306 -Display $display -Text "PSGadget"        -Page 0 -Align center
    Write-PsGadgetSsd1306 -Display $display -Text "SSD1306 via I2C" -Page 1 -Align center
    Start-Sleep -Seconds 2

    # 4. Live clock loop
    Clear-PsGadgetSsd1306 -Display $display
    Write-PsGadgetSsd1306 -Display $display -Text "Clock" -Page 0 -Align center
    for ($i = 0; $i -lt 10; $i++) {
        Clear-PsGadgetSsd1306 -Display $display -Page 3
        Write-PsGadgetSsd1306 -Display $display -Text (Get-Date -Format "HH:mm:ss") -Page 3 -Align center -FontSize 2
        Start-Sleep -Seconds 1
    }

    # 5. Done
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
- The most common mistake is swapping ADBUS0 and ADBUS1
- Run `List-PsGadgetFtdi | Format-Table HasMpsse` and confirm your device shows `True`
- Try `-Address 0x3D` if 0x3C fails

### "Failed to open device"

- Another application may have the D2XX handle open
- Close any serial terminal software (PuTTY, TeraTerm) pointing at the COM port
- Unplug and replug the USB cable

### Partial or garbled text

- Loose wire on SCL can cause clock glitches; reseat connectors
- Keep wires under 20 cm to avoid capacitance at 100 kHz

---

## Quick Reference (Pro)

```powershell
# Connect
$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()
$display = Connect-PsGadgetSsd1306 -PsGadget $dev

# Write
Clear-PsGadgetSsd1306 -Display $display
Write-PsGadgetSsd1306 -Display $display -Text "Hello" -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "BIG"   -Page 2 -Align center -FontSize 2
Write-PsGadgetSsd1306 -Display $display -Text "ALERT" -Page 4 -Invert
Clear-PsGadgetSsd1306 -Display $display -Page 1       # clear one page

# Cursor
Set-PsGadgetSsd1306Cursor -Display $display -Column 32 -Page 3

# Close
$dev.Close()
```
