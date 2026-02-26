# Example-Ssd1306.ps1
# End-to-end example: driving an SSD1306 OLED display over I2C
# using an FT232H and PSGadget's MPSSE I2C bit-banging.
#
# Hardware wiring (FT232H -> SSD1306):
#   ADBUS0 (TCK/SCK) -> SCL
#   ADBUS1 (TDI/DO)  -> SDA
#   3.3V             -> VCC
#   GND              -> GND
#
# Most 128x64 SSD1306 modules use I2C address 0x3C.
# Modules with the ADDR pin pulled high use 0x3D.

#Requires -Version 5.1

Import-Module "$PSScriptRoot/../PSGadget.psd1" -Force

# ── 1. Enumerate devices ────────────────────────────────────────────────────

Write-Host "Connected FTDI devices:"
List-PsGadgetFtdi | Format-Table Index, Type, SerialNumber, LocationId, HasMpsse

# ── 2. Connect FTDI ─────────────────────────────────────────────────────────
# Use the index of your FT232H (HasMpsse = True).

$dev = New-PsGadgetFtdi -Index 0
$dev.Connect()

if (-not $dev.IsOpen) {
    Write-Error "Failed to open FTDI device. Check USB connection and Index."
    return
}

Write-Host ("Connected: {0} [{1}]" -f $dev.Description, $dev.Type)

# ── 3. Connect SSD1306 ──────────────────────────────────────────────────────
# Default address 0x3C.  Use -Address 0x3D if your module wires ADDR pin high.

$display = Connect-PsGadgetSsd1306 -PsGadget $dev

if (-not $display) {
    Write-Error "Failed to initialize SSD1306. Check I2C wiring and address."
    $dev.Close()
    return
}

Write-Host ("SSD1306 ready - address 0x{0:X2}, {1} glyphs loaded" -f `
    $display.I2CAddress, $display.Glyphs.Count)

# ── 4. Clear the display ────────────────────────────────────────────────────

Clear-PsGadgetSsd1306 -Display $display | Out-Null
Write-Host "Display cleared"

# ── 5. Basic text ───────────────────────────────────────────────────────────
# The 128x64 display has 8 pages (rows) of 8 pixels each.
# Each character is 6 pixels wide, so a full row fits ~21 chars.

Write-PsGadgetSsd1306 -Display $display -Text "PSGadget" -Page 0 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "SSD1306 via I2C" -Page 1 -Align center
Write-PsGadgetSsd1306 -Display $display -Text ("Date: " + (Get-Date -Format "yyyy-MM-dd")) -Page 3
Write-PsGadgetSsd1306 -Display $display -Text ("Time: " + (Get-Date -Format "HH:mm:ss")) -Page 4

Write-Host "Basic text written to display"
Start-Sleep -Seconds 3

# ── 6. Alignment demo ───────────────────────────────────────────────────────

Clear-PsGadgetSsd1306 -Display $display | Out-Null
Write-PsGadgetSsd1306 -Display $display -Text "left"   -Page 1 -Align left
Write-PsGadgetSsd1306 -Display $display -Text "center" -Page 3 -Align center
Write-PsGadgetSsd1306 -Display $display -Text "right"  -Page 5 -Align right

Write-Host "Alignment demo active"
Start-Sleep -Seconds 3

# ── 7. Large and inverted text ──────────────────────────────────────────────
# FontSize 2 doubles each column horizontally (12px wide chars).
# Invert flips pixel values so text appears as dark-on-white.

Clear-PsGadgetSsd1306 -Display $display | Out-Null
Write-PsGadgetSsd1306 -Display $display -Text "BIG" -Page 0 -Align center -FontSize 2
Write-PsGadgetSsd1306 -Display $display -Text "INVERTED" -Page 4 -Align center -Invert

Write-Host "Large and inverted text"
Start-Sleep -Seconds 3

# ── 8. Live clock ───────────────────────────────────────────────────────────
# Update the display every second for 10 cycles.

Clear-PsGadgetSsd1306 -Display $display | Out-Null
Write-PsGadgetSsd1306 -Display $display -Text "Live Clock" -Page 0 -Align center

Write-Host "Running live clock for 10 seconds..."

for ($i = 0; $i -lt 10; $i++) {
    $timeStr = Get-Date -Format "HH:mm:ss"
    # Clear just page 3 before each update to avoid ghosting
    Clear-PsGadgetSsd1306 -Display $display -Page 3 | Out-Null
    Write-PsGadgetSsd1306 -Display $display -Text $timeStr -Page 3 -Align center -FontSize 2
    Start-Sleep -Seconds 1
}

# ── 9. Scrolling status lines ───────────────────────────────────────────────

$statusLines = @(
    "CPU: 12%",
    "MEM: 44%",
    "DISK: 67%",
    "NET: OK",
    "TEMP: 42C",
    "UPTIME: 3d"
)

Clear-PsGadgetSsd1306 -Display $display | Out-Null
Write-PsGadgetSsd1306 -Display $display -Text "-- STATUS --" -Page 0 -Align center

for ($i = 0; $i -lt $statusLines.Count; $i++) {
    $page = $i + 1
    if ($page -lt 8) {
        Write-PsGadgetSsd1306 -Display $display -Text $statusLines[$i] -Page $page
    }
}

Write-Host "Status screen written"
Start-Sleep -Seconds 3

# ── 10. Clear and close ─────────────────────────────────────────────────────

Clear-PsGadgetSsd1306 -Display $display | Out-Null
$dev.Close()

Write-Host "Done. Device closed."
