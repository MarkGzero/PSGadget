# Classes/PsGadgetSsd1306.ps1
# SSD1306 OLED Display Class

class PsGadgetSsd1306 : PsGadgetI2CDevice {
    [int]$Width          # Physical pixel width  (always 128)
    [int]$Height         # Physical pixel height (32 or 64)
    [int]$Pages          # Physical pages = Height/8
    [int]$Rotation       # 0, 90, 180, or 270 degrees
    [int]$LogicalWidth   # Canvas width  seen by callers (swapped for 90/270)
    [int]$LogicalHeight  # Canvas height seen by callers (swapped for 90/270)
    [int]$LogicalPages   # LogicalHeight / 8
    [byte[]]$FrameBuffer # Width * Pages bytes; index = page*Width + col; bit0 = top of page
    [hashtable]$Glyphs
    [hashtable]$Symbols

    PsGadgetSsd1306() {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance")
        $this.I2CAddress = 0x3C
        $this.Width = 128
        $this.Height = 64
        $this.Pages = 8
        $this.Rotation = 0
        $this.UpdateLogicalDimensions()
        $this.FrameBuffer = New-Object byte[] ($this.Width * $this.Pages)
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
        $this.InitializeSymbols()
    }

    PsGadgetSsd1306([System.Object]$ftdiDevice) {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance with FTDI device")
        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = 0x3C
        $this.Width = 128
        $this.Height = 64
        $this.Pages = 8
        $this.Rotation = 0
        $this.UpdateLogicalDimensions()
        $this.FrameBuffer = New-Object byte[] ($this.Width * $this.Pages)
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
        $this.InitializeSymbols()
    }

    PsGadgetSsd1306([System.Object]$ftdiDevice, [byte]$address) {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance with FTDI device and address 0x$($address.ToString('X2'))")
        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = $address
        $this.Width = 128
        $this.Height = 64
        $this.Pages = 8
        $this.Rotation = 0
        $this.UpdateLogicalDimensions()
        $this.FrameBuffer = New-Object byte[] ($this.Width * $this.Pages)
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
        $this.InitializeSymbols()
    }

    PsGadgetSsd1306([System.Object]$ftdiDevice, [byte]$address, [int]$height) {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance: address 0x$($address.ToString('X2')), height $height")
        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = $address
        $this.Width = 128
        $this.Height = $height
        $this.Pages = [int]($height / 8)
        $this.Rotation = 0
        $this.UpdateLogicalDimensions()
        $this.FrameBuffer = New-Object byte[] ($this.Width * $this.Pages)
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
        $this.InitializeSymbols()
    }

    PsGadgetSsd1306([System.Object]$ftdiDevice, [byte]$address, [int]$height, [int]$rotation) {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance: address 0x$($address.ToString('X2')), height $height, rotation $rotation")
        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = $address
        $this.Width = 128
        $this.Height = $height
        $this.Pages = [int]($height / 8)
        $this.Rotation = $rotation
        $this.UpdateLogicalDimensions()
        $this.FrameBuffer = New-Object byte[] ($this.Width * $this.Pages)
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
        $this.InitializeSymbols()
    }

    [void] InitializeGlyphs() {
        $this.Logger.WriteDebug("Initializing SSD1306 glyph font table")
        
        # Create case-sensitive hashtable for character glyphs
        $this.Glyphs = [hashtable]::new([System.StringComparer]::Ordinal)
        
        # Load 6x8 ASCII font based on reference implementation
        try {
            $this.Glyphs.Add('0', @( 0x00, 0x3E, 0x51, 0x49, 0x45, 0x3E ))
            $this.Glyphs.Add('1', @( 0x00, 0x00, 0x42, 0x7F, 0x40, 0x00 ))
            $this.Glyphs.Add('2', @( 0x00, 0x42, 0x61, 0x51, 0x49, 0x46 ))
            $this.Glyphs.Add('3', @( 0x00, 0x21, 0x41, 0x45, 0x4B, 0x31 ))
            $this.Glyphs.Add('4', @( 0x00, 0x18, 0x14, 0x12, 0x7F, 0x10 ))
            $this.Glyphs.Add('5', @( 0x00, 0x27, 0x45, 0x45, 0x45, 0x39 ))
            $this.Glyphs.Add('6', @( 0x00, 0x3C, 0x4A, 0x49, 0x49, 0x30 ))
            $this.Glyphs.Add('7', @( 0x00, 0x01, 0x71, 0x09, 0x05, 0x03 ))
            $this.Glyphs.Add('8', @( 0x00, 0x36, 0x49, 0x49, 0x49, 0x36 ))
            $this.Glyphs.Add('9', @( 0x00, 0x06, 0x49, 0x49, 0x29, 0x1E ))
            $this.Glyphs.Add('A', @( 0x00, 0x7C, 0x12, 0x11, 0x12, 0x7C ))
            $this.Glyphs.Add('B', @( 0x00, 0x7F, 0x49, 0x49, 0x49, 0x36 ))
            $this.Glyphs.Add('C', @( 0x00, 0x3E, 0x41, 0x41, 0x41, 0x22 ))
            $this.Glyphs.Add('D', @( 0x00, 0x7F, 0x41, 0x41, 0x22, 0x1C ))
            $this.Glyphs.Add('E', @( 0x00, 0x7F, 0x49, 0x49, 0x49, 0x41 ))
            $this.Glyphs.Add('F', @( 0x00, 0x7F, 0x09, 0x09, 0x09, 0x01 ))
            $this.Glyphs.Add('G', @( 0x00, 0x3E, 0x41, 0x49, 0x49, 0x7A ))
            $this.Glyphs.Add('H', @( 0x00, 0x7F, 0x08, 0x08, 0x08, 0x7F ))
            $this.Glyphs.Add('I', @( 0x00, 0x00, 0x41, 0x7F, 0x41, 0x00 ))
            $this.Glyphs.Add('J', @( 0x00, 0x20, 0x40, 0x41, 0x3F, 0x01 ))
            $this.Glyphs.Add('K', @( 0x00, 0x7F, 0x08, 0x14, 0x22, 0x41 ))
            $this.Glyphs.Add('L', @( 0x00, 0x7F, 0x40, 0x40, 0x40, 0x40 ))
            $this.Glyphs.Add('M', @( 0x00, 0x7F, 0x02, 0x0C, 0x02, 0x7F ))
            $this.Glyphs.Add('N', @( 0x00, 0x7F, 0x04, 0x08, 0x10, 0x7F ))
            $this.Glyphs.Add('O', @( 0x00, 0x3E, 0x41, 0x41, 0x41, 0x3E ))
            $this.Glyphs.Add('P', @( 0x00, 0x7F, 0x09, 0x09, 0x09, 0x06 ))
            $this.Glyphs.Add('Q', @( 0x00, 0x3E, 0x41, 0x51, 0x21, 0x5E ))
            $this.Glyphs.Add('R', @( 0x00, 0x7F, 0x09, 0x19, 0x29, 0x46 ))
            $this.Glyphs.Add('S', @( 0x00, 0x46, 0x49, 0x49, 0x49, 0x31 ))
            $this.Glyphs.Add('T', @( 0x00, 0x01, 0x01, 0x7F, 0x01, 0x01 ))
            $this.Glyphs.Add('U', @( 0x00, 0x3F, 0x40, 0x40, 0x40, 0x3F ))
            $this.Glyphs.Add('V', @( 0x00, 0x1F, 0x20, 0x40, 0x20, 0x1F ))
            $this.Glyphs.Add('W', @( 0x00, 0x3F, 0x40, 0x38, 0x40, 0x3F ))
            $this.Glyphs.Add('X', @( 0x00, 0x63, 0x14, 0x08, 0x14, 0x63 ))
            $this.Glyphs.Add('Y', @( 0x00, 0x07, 0x08, 0x70, 0x08, 0x07 ))
            $this.Glyphs.Add('Z', @( 0x00, 0x61, 0x51, 0x49, 0x45, 0x43 ))
            $this.Glyphs.Add('a', @( 0x00, 0x20, 0x54, 0x54, 0x54, 0x78 ))
            $this.Glyphs.Add('b', @( 0x00, 0x7F, 0x48, 0x44, 0x44, 0x38 ))
            $this.Glyphs.Add('c', @( 0x00, 0x38, 0x44, 0x44, 0x44, 0x20 ))
            $this.Glyphs.Add('d', @( 0x00, 0x38, 0x44, 0x44, 0x48, 0x7F ))
            $this.Glyphs.Add('e', @( 0x00, 0x38, 0x54, 0x54, 0x54, 0x18 ))
            $this.Glyphs.Add('f', @( 0x00, 0x08, 0x7E, 0x09, 0x01, 0x02 ))
            $this.Glyphs.Add('g', @( 0x00, 0x18, 0xA4, 0xA4, 0xA4, 0x7C ))
            $this.Glyphs.Add('h', @( 0x00, 0x7F, 0x08, 0x04, 0x04, 0x78 ))
            $this.Glyphs.Add('i', @( 0x00, 0x00, 0x44, 0x7D, 0x40, 0x00 ))
            $this.Glyphs.Add('j', @( 0x00, 0x40, 0x80, 0x84, 0x7D, 0x00 ))
            $this.Glyphs.Add('k', @( 0x00, 0x7F, 0x10, 0x28, 0x44, 0x00 ))
            $this.Glyphs.Add('l', @( 0x00, 0x00, 0x41, 0x7F, 0x40, 0x00 ))
            $this.Glyphs.Add('m', @( 0x00, 0x7C, 0x04, 0x18, 0x04, 0x78 ))
            $this.Glyphs.Add('n', @( 0x00, 0x7C, 0x08, 0x04, 0x04, 0x78 ))
            $this.Glyphs.Add('o', @( 0x00, 0x38, 0x44, 0x44, 0x44, 0x38 ))
            $this.Glyphs.Add('p', @( 0x00, 0xFC, 0x24, 0x24, 0x24, 0x18 ))
            $this.Glyphs.Add('q', @( 0x00, 0x18, 0x24, 0x24, 0x18, 0xFC ))
            $this.Glyphs.Add('r', @( 0x00, 0x7C, 0x08, 0x04, 0x04, 0x08 ))
            $this.Glyphs.Add('s', @( 0x00, 0x48, 0x54, 0x54, 0x54, 0x20 ))
            $this.Glyphs.Add('t', @( 0x00, 0x04, 0x3F, 0x44, 0x40, 0x20 ))
            $this.Glyphs.Add('u', @( 0x00, 0x3C, 0x40, 0x40, 0x20, 0x7C ))
            $this.Glyphs.Add('v', @( 0x00, 0x1C, 0x20, 0x40, 0x20, 0x1C ))
            $this.Glyphs.Add('w', @( 0x00, 0x3C, 0x40, 0x30, 0x40, 0x3C ))
            $this.Glyphs.Add('x', @( 0x00, 0x44, 0x28, 0x10, 0x28, 0x44 ))
            $this.Glyphs.Add('y', @( 0x00, 0x1C, 0xA0, 0xA0, 0xA0, 0x7C ))
            $this.Glyphs.Add('z', @( 0x00, 0x44, 0x64, 0x54, 0x4C, 0x44 ))
            $this.Glyphs.Add(' ', @( 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ))
            $this.Glyphs.Add('!', @( 0x00, 0x00, 0x6F, 0x00, 0x00, 0x00 ))
            $this.Glyphs.Add('"', @( 0x00, 0x00, 0x07, 0x00, 0x07, 0x00 ))
            $this.Glyphs.Add('#', @( 0x00, 0x14, 0x7f, 0x14, 0x7f, 0x14 ))
            $this.Glyphs.Add('$', @( 0x00, 0x24, 0x2a, 0x7f, 0x2a, 0x12 ))
            $this.Glyphs.Add('%', @( 0x00, 0x23, 0x13, 0x08, 0x64, 0x62 ))
            $this.Glyphs.Add('&', @( 0x00, 0x36, 0x49, 0x55, 0x22, 0x50 ))
            $this.Glyphs.Add("'", @( 0x00, 0x00, 0x05, 0x03, 0x00, 0x00 ))
            $this.Glyphs.Add('(', @( 0x00, 0x00, 0x1c, 0x22, 0x41, 0x00 ))
            $this.Glyphs.Add(')', @( 0x00, 0x00, 0x41, 0x22, 0x1c, 0x00 ))
            $this.Glyphs.Add('*', @( 0x00, 0x0a, 0x04, 0x1f, 0x04, 0x0a ))
            $this.Glyphs.Add('+', @( 0x00, 0x08, 0x08, 0x3e, 0x08, 0x08 ))
            $this.Glyphs.Add(',', @( 0x00, 0x00, 0x50, 0x30, 0x00, 0x00 ))
            $this.Glyphs.Add('-', @( 0x00, 0x08, 0x08, 0x08, 0x08, 0x08 ))
            $this.Glyphs.Add('.', @( 0x00, 0x00, 0x60, 0x60, 0x00, 0x00 ))
            $this.Glyphs.Add('/', @( 0x00, 0x20, 0x10, 0x08, 0x04, 0x02 ))
            $this.Glyphs.Add(':', @( 0x00, 0x00, 0x36, 0x36, 0x00, 0x00 ))
            $this.Glyphs.Add(';', @( 0x00, 0x00, 0x56, 0x36, 0x00, 0x00 ))
            $this.Glyphs.Add('<', @( 0x00, 0x08, 0x14, 0x22, 0x41, 0x00 ))
            $this.Glyphs.Add('=', @( 0x00, 0x14, 0x14, 0x14, 0x14, 0x14 ))
            $this.Glyphs.Add('>', @( 0x00, 0x00, 0x41, 0x22, 0x14, 0x08 ))
            $this.Glyphs.Add('?', @( 0x00, 0x02, 0x01, 0x51, 0x09, 0x06 ))
            $this.Glyphs.Add('@', @( 0x00, 0x32, 0x49, 0x79, 0x41, 0x3e ))
            $this.Glyphs.Add('[', @( 0x00, 0x00, 0x7F, 0x41, 0x41, 0x00 ))
            $this.Glyphs.Add('\', @( 0x00, 0x02, 0x04, 0x08, 0x10, 0x20 ))
            $this.Glyphs.Add(']', @( 0x00, 0x00, 0x41, 0x41, 0x7F, 0x00 ))
            $this.Glyphs.Add('^', @( 0x00, 0x04, 0x02, 0x01, 0x02, 0x04 ))
            $this.Glyphs.Add('_', @( 0x00, 0x40, 0x40, 0x40, 0x40, 0x40 ))
            $this.Glyphs.Add('`', @( 0x00, 0x00, 0x01, 0x02, 0x04, 0x00 ))
            $this.Glyphs.Add('{', @( 0x00, 0x00, 0x08, 0x77, 0x00, 0x00 ))
            $this.Glyphs.Add('|', @( 0x00, 0x00, 0x00, 0x7F, 0x00, 0x00 ))
            $this.Glyphs.Add('}', @( 0x00, 0x00, 0x77, 0x08, 0x00, 0x00 ))
            $this.Glyphs.Add('~', @( 0x00, 0x10, 0x08, 0x10, 0x08, 0x00 ))
            
            $this.Logger.WriteDebug("Loaded $($this.Glyphs.Count) character glyphs")
            
        } catch {
            $this.Logger.WriteError("Failed to initialize glyphs: $_")
            throw
        }
    }
    
    [bool] Initialize([bool]$force) {
        if (-not $this.BeginInitialize($force)) {
            return $this.IsInitialized
        }

        $this.Logger.WriteInfo("Initializing SSD1306 display at address 0x$($this.I2CAddress.ToString('X2'))")

        try {
            # Height-dependent init values:
            #   128x64: mux=0x3F (63), COM pins=0x12 (alt config, left/right remap)
            #   128x32: mux=0x1F (31), COM pins=0x02 (sequential, no remap)
            [byte]$muxRatio = [byte]($this.Height - 1)
            [byte]$comPins  = if ($this.Height -eq 32) { 0x02 } else { 0x12 }

            # Send the full initialization sequence as one batched I2C transaction.
            # PAGE addressing mode (0x20 0x02): page-mode cursor commands (0xB0+page, 0x00, 0x10)
            # remain valid and FlushPhysPage continues to work without change.
            Initialize-Ssd1306 -device $this -height $this.Height -rotation $this.Rotation | Out-Null

            $this.IsInitialized = $true
            $this.FrameBuffer = New-Object byte[] ($this.Width * $this.Pages)
            # Clear the hardware GDDRAM to match the zeroed framebuffer.
            # Reference implementation always clears after init; some displays retain
            # GDDRAM across power cycles and will show stale data without this.
            Write-Ssd1306Display -device $this -frameBuffer $this.FrameBuffer -pages $this.Pages | Out-Null
            $this.Logger.WriteInfo("SSD1306 initialization completed successfully")
            return $true
            
        } catch {
            $this.Logger.WriteError("SSD1306 initialization failed: $_")
            $this.IsInitialized = $false
            return $false
        }
    }
    
    [bool] Clear() {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }
        $this.Logger.WriteInfo("Clearing SSD1306 display")
        try {
            Clear-Ssd1306Display -device $this -frameBuffer $this.FrameBuffer -pages $this.Pages | Out-Null
            return $true
        } catch {
            $this.Logger.WriteError("Failed to clear display: $_")
            return $false
        }
    }
    
    [bool] ClearPage([int]$page) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }
        if ($page -lt 0 -or $page -ge $this.LogicalPages) {
            $this.Logger.WriteError("Invalid page: $page (valid: 0-$($this.LogicalPages - 1))")
            return $false
        }
        try {
            [int]$yStart = $page * 8
            $this.ClearLogicalRows($yStart, $yStart + 7)
            $result = $this.FlushLogicalRows($yStart, $yStart + 7)
            $this.Logger.WriteTrace("Cleared logical page $page")
            return $result
        } catch {
            $this.Logger.WriteError("Failed to clear page $page : $_")
            return $false
        }
    }
    
    [bool] SetCursor([int]$column, [int]$page) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }
        
        if ($column -lt 0 -or $column -ge $this.Width) {
            $this.Logger.WriteError("Invalid column: $column (valid range: 0-$($this.Width - 1))")
            return $false
        }
        
        if ($page -lt 0 -or $page -ge $this.Pages) {
            $this.Logger.WriteError("Invalid page: $page (valid range: 0-$($this.Pages - 1))")
            return $false
        }
        
        try {
            # Set page address
            [byte[]]$pageCmd = @(0x00, [byte](0xB0 + $page))
            if (-not $this.I2CWrite($pageCmd)) { throw "Failed to set page address" }

            # Set column address (lower nibble)
            [byte[]]$colLowCmd = @(0x00, [byte](0x00 + ($column -band 0x0F)))
            if (-not $this.I2CWrite($colLowCmd)) { throw "Failed to set column low address" }

            # Set column address (upper nibble)
            [byte[]]$colHighCmd = @(0x00, [byte](0x10 + (($column -shr 4) -band 0x0F)))
            if (-not $this.I2CWrite($colHighCmd)) { throw "Failed to set column high address" }
            
            $this.Logger.WriteTrace("Set cursor to column $column, page $page")
            return $true
            
        } catch {
            $this.Logger.WriteError("Failed to set cursor: $_")
            return $false
        }
    }
    
    [bool] WriteText([string]$text, [int]$page) {
        return $this.WriteText($text, $page, 'left', 1, $false)
    }
    
    [bool] WriteText([string]$text, [int]$page, [string]$align) {
        return $this.WriteText($text, $page, $align, 1, $false)
    }
    
    [bool] WriteText([string]$text, [int]$page, [string]$align, [int]$fontSize, [bool]$invert) {
        if ($fontSize -eq 2) {
            if ($this.Rotation -eq 90 -or $this.Rotation -eq 270) {
                $this.Logger.WriteError("FontSize 2 is not supported in portrait (90/270) orientation")
                return $false
            }
            return $this.WriteTextTall($text, $page, $align, $invert)
        }

        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }

        if ($page -lt 0 -or $page -ge $this.LogicalPages) {
            $this.Logger.WriteError("Invalid page: $page (valid: 0-$($this.LogicalPages - 1))")
            return $false
        }

        if ([string]::IsNullOrEmpty($text)) {
            $this.Logger.WriteDebug("Empty text string, nothing to write")
            return $true
        }

        $this.Logger.WriteInfo("WriteText '$text' -> logical page $page (align: $align, rotation: $($this.Rotation))")

        try {
            # Build per-character glyph list and total pixel width
            [System.Collections.Generic.List[byte[]]]$glyphList = [System.Collections.Generic.List[byte[]]]::new()
            [int]$totalWidth = 0
            foreach ($char in $text.ToCharArray()) {
                $key = [string]$char
                [byte[]]$g = if ($this.Glyphs.ContainsKey($key)) { [byte[]]$this.Glyphs[$key] } else { [byte[]]$this.Glyphs[' '] }
                $glyphList.Add($g)
                $totalWidth += $g.Count
            }

            # Compute logical start X based on alignment
            [int]$startX = switch ($align.ToLower()) {
                'center' { [math]::Max(0, [math]::Floor(($this.LogicalWidth - $totalWidth) / 2)) }
                'right'  { [math]::Max(0, $this.LogicalWidth - $totalWidth) }
                default  { 0 }
            }
            [int]$startY = $page * 8

            # Clear target logical rows before rendering (eliminates stray pixels)
            $this.ClearLogicalRows($startY, $startY + 7)

            # Render each glyph column-by-column into the framebuffer via SetLogicalPixel
            [int]$lx = $startX
            foreach ($g in $glyphList) {
                if ($lx -ge $this.LogicalWidth) { break }
                for ($col = 0; $col -lt $g.Count; $col++) {
                    [byte]$colByte = $g[$col]
                    if ($invert) { $colByte = [byte]($colByte -bxor 0xFF) }
                    for ($bit = 0; $bit -lt 8; $bit++) {
                        if ($colByte -band (1 -shl $bit)) {
                            $this.SetLogicalPixel($lx + $col, $startY + $bit, $true)
                        }
                    }
                }
                $lx += $g.Count
            }

            # Flush modified physical pages to the display
            return $this.FlushLogicalRows($startY, $startY + 7)

        } catch {
            $this.Logger.WriteError("WriteText failed: $_")
            return $false
        }
    }

    # ---------------------------------------------------------------------------
    # Symbols support
    # ---------------------------------------------------------------------------

    [void] InitializeSymbols() {
        $this.Logger.WriteDebug("Initializing SSD1306 symbol table")
        $this.Symbols = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

        # All symbols: 8-byte arrays, column-major, bit0=top pixel (row 0), bit7=bottom (row 7).
        # 8x8 is the Small (1-page) form. DrawSymbol auto-scales to 16x16 (2-page) using
        # ExpandNibble when page <= 6, falling back to 8x8 when page == 7.

        # Warning: upward-pointing triangle with ! in center column
        #  col:  0     1     2     3     4     5     6     7
        #  R0:   .     .     .     *     .     .     .     .   peak
        #  R1:   .     .     *     *     *     .     .     .
        #  R2:   .     .     *     *     *     .     .     .
        #  R3:   .     *     *     .     *     *     .     .
        #  R4:   .     *     *     *     *     *     .     .
        #  R5:   *     *     *     *     *     *     *     .   base fill
        #  R6:   *     *     *     *     *     *     *     .   base
        #  R7:   .     .     .     .     .     .     .     .
        $this.Symbols['Warning'] = [byte[]]@(0x60, 0x78, 0x7E, 0x17, 0x7E, 0x78, 0x60, 0x00)

        # Alert: rectangle box with ! inside
        #  col:  0     1     2     3     4     5     6     7
        #  R0:   *     *     *     *     *     *     *     .   top border
        #  R1:   *     .     .     *     .     .     *     .
        #  R2:   *     .     .     *     .     .     *     .
        #  R3:   *     .     .     *     .     .     *     .   ! stem
        #  R4:   *     .     .     .     .     .     *     .   ! gap
        #  R5:   *     .     .     *     .     .     *     .   ! dot
        #  R6:   *     *     *     *     *     *     *     .   bottom border
        #  R7:   .     .     .     .     .     .     .     .
        $this.Symbols['Alert'] = [byte[]]@(0x7F, 0x41, 0x41, 0x6F, 0x41, 0x41, 0x7F, 0x00)

        # Checkmark: tick/check mark shape
        #  col:  0     1     2     3     4     5     6     7
        #  R0:   .     .     .     .     .     .     .     .
        #  R1:   .     .     .     .     .     .     *     .
        #  R2:   .     .     .     .     .     *     *     .
        #  R3:   .     .     .     .     *     *     .     .
        #  R4:   *     .     .     *     *     .     .     .
        #  R5:   *     *     *     *     .     .     .     .
        #  R6:   .     *     *     .     .     .     .     .
        #  R7:   .     .     .     .     .     .     .     .
        $this.Symbols['Checkmark'] = [byte[]]@(0x30, 0x60, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x00)

        # Error: X inside a circle
        #  col:  0     1     2     3     4     5     6     7
        #  R0:   .     .     *     *     *     *     .     .   circle top
        #  R1:   .     *     .     .     .     .     *     .
        #  R2:   *     .     *     .     .     *     .     *   X mark
        #  R3:   *     .     .     *     *     .     .     *
        #  R4:   *     .     .     *     *     .     .     *
        #  R5:   *     .     *     .     .     *     .     *   X mark
        #  R6:   .     *     .     .     .     .     *     .
        #  R7:   .     .     *     *     *     *     .     .   circle bottom
        $this.Symbols['Error'] = [byte[]]@(0x3C, 0x42, 0xA5, 0x99, 0x99, 0xA5, 0x42, 0x3C)

        # Info: circle with "i" indicator (dot then bar)
        #  Outer circle: cols 0,7=sides rows 2-5; cols 1,6=rows 1,6; cols 2,5=rows 0,7
        #  Center (cols 3,4): circle boundary + i dot at R2 + i bar at R4-R6
        $this.Symbols['Info'] = [byte[]]@(0x3C, 0x42, 0x81, 0xF5, 0xF5, 0x81, 0x42, 0x3C)

        # Lock: closed padlock
        #  R0-R2: arc (shackle top)
        #  R3:    gap
        #  R4-R7: rectangular body with keyhole
        $this.Symbols['Lock'] = [byte[]]@(0xF0, 0x92, 0x91, 0xF1, 0x91, 0x92, 0x60, 0x00)

        # Unlock: open padlock (shackle released to right side)
        $this.Symbols['Unlock'] = [byte[]]@(0xF0, 0x90, 0x90, 0xF1, 0x91, 0x96, 0x60, 0x00)

        # Network: diamond / hub shape (connected nodes)
        #  col:  0     1     2     3     4     5     6     7
        #  R0:   .     .     .     *     .     .     .     .
        #  R1:   .     .     *     *     *     .     .     .
        #  R2:   .     *     *     .     *     *     .     .
        #  R3:   *     *     .     .     .     *     *     .
        #  R4:   .     *     *     .     *     *     .     .
        #  R5:   .     .     *     *     *     .     .     .
        #  R6:   .     .     .     *     .     .     .     .
        #  R7:   .     .     .     .     .     .     .     .
        $this.Symbols['Network'] = [byte[]]@(0x08, 0x1C, 0x36, 0x63, 0x36, 0x1C, 0x08, 0x00)

        $this.Logger.WriteDebug("Loaded $($this.Symbols.Count) symbols")
    }

    # Expand a 4-bit nibble to 8 bits by doubling each bit.
    # Used for 2x vertical scaling: each pixel row becomes 2 consecutive rows.
    # bit0 -> bits 0,1  (row 0 -> rows 0,1)
    # bit1 -> bits 2,3  (row 1 -> rows 2,3)
    # bit2 -> bits 4,5  (row 2 -> rows 4,5)
    # bit3 -> bits 6,7  (row 3 -> rows 6,7)
    hidden [byte] ExpandNibble([byte]$nibble) {
        [byte]$result = 0
        if ($nibble -band 0x01) { $result = $result -bor 0x03 }
        if ($nibble -band 0x02) { $result = $result -bor 0x0C }
        if ($nibble -band 0x04) { $result = $result -bor 0x30 }
        if ($nibble -band 0x08) { $result = $result -bor 0xC0 }
        return $result
    }

    # Draw a named symbol at the given logical page and column.
    # page < (LogicalPages-1): renders 16x16 (2-page) via ExpandNibble.
    # page == (LogicalPages-1): renders 8x8 (1-page) as-is.
    [bool] DrawSymbol([string]$name, [int]$page, [int]$column) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }

        if (-not $this.Symbols.ContainsKey($name)) {
            $this.Logger.WriteError("Unknown symbol '$name'. Valid symbols: $($this.Symbols.Keys -join ', ')")
            return $false
        }

        if ($page -lt 0 -or $page -ge $this.LogicalPages) {
            $this.Logger.WriteError("Invalid page: $page (valid: 0-$($this.LogicalPages - 1))")
            return $false
        }

        $sym = [byte[]]$this.Symbols[$name]
        $this.Logger.WriteInfo("Drawing symbol '$name' at logical page $page, col $column (rotation: $($this.Rotation))")

        try {
            [int]$startY = $page * 8
            [bool]$use16x16 = ($page -lt ($this.LogicalPages - 1))

            if ($use16x16) {
                $this.ClearLogicalRows($startY, $startY + 15)
                for ($col = 0; $col -lt $sym.Count; $col++) {
                    [byte]$b = $sym[$col]
                    [byte]$topByte = $this.ExpandNibble($b -band 0x0F)
                    [byte]$botByte = $this.ExpandNibble(($b -shr 4) -band 0x0F)
                    for ($bit = 0; $bit -lt 8; $bit++) {
                        if ($topByte -band (1 -shl $bit)) { $this.SetLogicalPixel($column + $col, $startY + $bit, $true) }
                        if ($botByte -band (1 -shl $bit)) { $this.SetLogicalPixel($column + $col, $startY + 8 + $bit, $true) }
                    }
                }
                return $this.FlushLogicalRows($startY, $startY + 15)
            } else {
                $this.ClearLogicalRows($startY, $startY + 7)
                for ($col = 0; $col -lt $sym.Count; $col++) {
                    [byte]$b = $sym[$col]
                    for ($bit = 0; $bit -lt 8; $bit++) {
                        if ($b -band (1 -shl $bit)) { $this.SetLogicalPixel($column + $col, $startY + $bit, $true) }
                    }
                }
                return $this.FlushLogicalRows($startY, $startY + 7)
            }

        } catch {
            $this.Logger.WriteError("DrawSymbol '$name' failed: $_")
            return $false
        }
    }

    # Write text spanning 2 logical pages (double height, 16 logical rows tall).
    # Only supported in landscape (0deg/180deg) orientation.
    # Requires page in range 0 to (LogicalPages-2) so that page+1 is valid.
    [bool] WriteTextTall([string]$text, [int]$page, [string]$align, [bool]$invert) {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }

        if ($this.Rotation -eq 90 -or $this.Rotation -eq 270) {
            $this.Logger.WriteError("WriteTextTall is not supported in portrait (90/270) orientation")
            return $false
        }

        [int]$maxPage = $this.LogicalPages - 2
        if ($page -lt 0 -or $page -gt $maxPage) {
            $this.Logger.WriteError("WriteTextTall: page must be 0-$maxPage (needs page+1). Got: $page")
            return $false
        }

        if ([string]::IsNullOrEmpty($text)) {
            $this.Logger.WriteDebug("WriteTextTall: empty text, nothing to write")
            return $true
        }

        $this.Logger.WriteInfo("WriteTextTall '$text' pages $page/$($page+1) align=$align rotation=$($this.Rotation)")

        try {
            # Build glyph list
            [System.Collections.Generic.List[byte[]]]$glyphList = [System.Collections.Generic.List[byte[]]]::new()
            [int]$totalWidth = 0
            foreach ($char in $text.ToCharArray()) {
                $key = [string]$char
                [byte[]]$g = if ($this.Glyphs.ContainsKey($key)) { [byte[]]$this.Glyphs[$key] } else { [byte[]]$this.Glyphs[' '] }
                $glyphList.Add($g)
                $totalWidth += $g.Count
            }

            [int]$startX = switch ($align.ToLower()) {
                'center' { [math]::Max(0, [math]::Floor(($this.LogicalWidth - $totalWidth) / 2)) }
                'right'  { [math]::Max(0, $this.LogicalWidth - $totalWidth) }
                default  { 0 }
            }
            [int]$startY = $page * 8

            # Clear 2 logical pages (16 rows) before rendering
            $this.ClearLogicalRows($startY, $startY + 15)

            # Render with 2x vertical scale via ExpandNibble
            [int]$lx = $startX
            foreach ($g in $glyphList) {
                if ($lx -ge $this.LogicalWidth) { break }
                for ($col = 0; $col -lt $g.Count; $col++) {
                    [byte]$bval = $g[$col]
                    if ($invert) { $bval = [byte]($bval -bxor 0xFF) }
                    [byte]$topByte = $this.ExpandNibble($bval -band 0x0F)
                    [byte]$botByte = $this.ExpandNibble(($bval -shr 4) -band 0x0F)
                    for ($bit = 0; $bit -lt 8; $bit++) {
                        if ($topByte -band (1 -shl $bit)) { $this.SetLogicalPixel($lx + $col, $startY + $bit, $true) }
                        if ($botByte -band (1 -shl $bit)) { $this.SetLogicalPixel($lx + $col, $startY + 8 + $bit, $true) }
                    }
                }
                $lx += $g.Count
            }

            return $this.FlushLogicalRows($startY, $startY + 15)

        } catch {
            $this.Logger.WriteError("WriteTextTall failed: $_")
            return $false
        }
    }

    # Draw a 2-pixel border around the entire display, render "PsGadget" centered,
    # flush once, hold for 3 seconds, then clear.
    [bool] ShowSplash() {
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }

        $this.Logger.WriteInfo("ShowSplash: 2-px border + 'PsGadget' label")

        try {
            # Start clean
            [System.Array]::Clear($this.FrameBuffer, 0, $this.FrameBuffer.Length)

            # 2-pixel border — top and bottom rows
            for ($x = 0; $x -lt $this.LogicalWidth; $x++) {
                $this.SetLogicalPixel($x, 0, $true)
                $this.SetLogicalPixel($x, 1, $true)
                $this.SetLogicalPixel($x, $this.LogicalHeight - 2, $true)
                $this.SetLogicalPixel($x, $this.LogicalHeight - 1, $true)
            }
            # 2-pixel border — left and right columns (corners already set above)
            for ($y = 2; $y -lt ($this.LogicalHeight - 2); $y++) {
                $this.SetLogicalPixel(0,                       $y, $true)
                $this.SetLogicalPixel(1,                       $y, $true)
                $this.SetLogicalPixel($this.LogicalWidth - 2,  $y, $true)
                $this.SetLogicalPixel($this.LogicalWidth - 1,  $y, $true)
            }

            # "PsGadget" — pixel-perfect center (not snapped to page boundary)
            [string]$label   = 'PsGadget'
            [int]$textWidth  = 0
            foreach ($c in $label.ToCharArray()) {
                $k = [string]$c
                $textWidth += (if ($this.Glyphs.ContainsKey($k)) { $this.Glyphs[$k] } else { $this.Glyphs[' '] }).Count
            }
            [int]$startX = [math]::Max(0, [math]::Floor(($this.LogicalWidth  - $textWidth) / 2))
            [int]$startY = [math]::Floor(($this.LogicalHeight - 8) / 2)

            [int]$lx = $startX
            foreach ($c in $label.ToCharArray()) {
                $k = [string]$c
                [byte[]]$g = if ($this.Glyphs.ContainsKey($k)) { [byte[]]$this.Glyphs[$k] } else { [byte[]]$this.Glyphs[' '] }
                for ($col = 0; $col -lt $g.Count; $col++) {
                    [byte]$colByte = $g[$col]
                    for ($bit = 0; $bit -lt 8; $bit++) {
                        if ($colByte -band (1 -shl $bit)) {
                            $this.SetLogicalPixel($lx + $col, $startY + $bit, $true)
                        }
                    }
                }
                $lx += $g.Count
            }

            # One bulk push — border + text in a single display update
            $this.FlushAll() | Out-Null

            Start-Sleep -Seconds 3

            $this.Clear() | Out-Null
            return $true

        } catch {
            $this.Logger.WriteError("ShowSplash failed: $_")
            return $false
        }
    }

    # ---------------------------------------------------------------------------
    # Rotation management
    # ---------------------------------------------------------------------------

    # Set display rotation to 0, 90, 180, or 270 degrees.
    # 0/180 = landscape; 90/270 = portrait (swaps logical width and height).
    # Re-runs hardware initialization when the rotation actually changes.
    # FontSize 2 and WriteTextTall are only supported in 0/180 orientation.
    [void] SetRotation([int]$degrees) {
        if ($degrees -notin @(0, 90, 180, 270)) {
            throw [System.ArgumentException]::new("Invalid rotation: $degrees. Must be 0, 90, 180, or 270.")
        }
        if ($this.Rotation -eq $degrees -and $this.IsInitialized) {
            $this.Logger.WriteTrace("SetRotation: already at $degrees deg, no-op")
            return
        }
        $this.Logger.WriteInfo("Setting rotation from $($this.Rotation) to $degrees degrees")
        $this.Rotation = $degrees
        $this.UpdateLogicalDimensions()
        if ($this.FtdiDevice) {
            $this.Initialize($true)
        }
    }

    # ---------------------------------------------------------------------------
    # Private rendering infrastructure
    # ---------------------------------------------------------------------------

    # Recompute LogicalWidth, LogicalHeight, LogicalPages from Width/Height/Rotation.
    hidden [void] UpdateLogicalDimensions() {
        if ($this.Rotation -eq 90 -or $this.Rotation -eq 270) {
            $this.LogicalWidth  = $this.Height
            $this.LogicalHeight = $this.Width
        } else {
            $this.LogicalWidth  = $this.Width
            $this.LogicalHeight = $this.Height
        }
        $this.LogicalPages = [int]($this.LogicalHeight / 8)
        $this.Logger.WriteDebug("Logical dims: $($this.LogicalWidth)x$($this.LogicalHeight), $($this.LogicalPages) pages")
    }

    # Set or clear one physical pixel in the framebuffer.
    # Clips silently when px/py are outside physical bounds.
    hidden [void] SetPixel([int]$px, [int]$py, [bool]$on) {
        if ($px -lt 0 -or $px -ge $this.Width -or $py -lt 0 -or $py -ge $this.Height) { return }
        [int]$idx  = ($py -shr 3) * $this.Width + $px
        [byte]$mask = [byte](1 -shl ($py -band 7))
        if ($on) {
            $this.FrameBuffer[$idx] = [byte]($this.FrameBuffer[$idx] -bor $mask)
        } else {
            $this.FrameBuffer[$idx] = [byte]($this.FrameBuffer[$idx] -band ([byte]0xFF -bxor $mask))
        }
    }

    # Map a logical (canvas) pixel to physical coordinates and write it.
    # Rotation mappings (phys Width=128, phys Height=64 or 32):
    #   0deg:   px=lx,          py=ly
    #   90deg:  px=Width-1-ly,  py=lx           (portrait: top = original right edge)
    #   180deg: px=Width-1-lx,  py=Height-1-ly  (both axes flipped)
    #   270deg: px=ly,          py=Height-1-lx  (portrait: top = original left edge)
    hidden [void] SetLogicalPixel([int]$lx, [int]$ly, [bool]$on) {
        [int]$px = 0
        [int]$py = 0
        switch ($this.Rotation) {
            0   { $px = $lx;                      $py = $ly                    }
            90  { $px = $this.Width - 1 - $ly;    $py = $lx                    }
            180 { $px = $this.Width - 1 - $lx;    $py = $this.Height - 1 - $ly }
            270 { $px = $ly;                       $py = $this.Height - 1 - $lx }
        }
        $this.SetPixel($px, $py, $on)
    }

    # Zero framebuffer bytes that correspond to logical rows yStart..yEnd.
    # Fast path for 0deg/180deg (whole physical pages); column-range path for 90deg/270deg.
    hidden [void] ClearLogicalRows([int]$yStart, [int]$yEnd) {
        switch ($this.Rotation) {
            0 {
                [int]$p0 = $yStart -shr 3
                [int]$p1 = $yEnd   -shr 3
                for ($p = $p0; $p -le $p1; $p++) {
                    [System.Array]::Clear($this.FrameBuffer, $p * $this.Width, $this.Width)
                }
            }
            180 {
                # Physical pages are mirrored (logical page 0 = physical page Pages-1)
                [int]$p0 = $this.Pages - 1 - ($yEnd   -shr 3)
                [int]$p1 = $this.Pages - 1 - ($yStart -shr 3)
                for ($p = $p0; $p -le $p1; $p++) {
                    [System.Array]::Clear($this.FrameBuffer, $p * $this.Width, $this.Width)
                }
            }
            90 {
                # Logical ly -> physical x = (Width-1-ly); all physical pages touched
                [int]$colLow  = $this.Width - 1 - $yEnd
                [int]$colHigh = $this.Width - 1 - $yStart
                for ($p = 0; $p -lt $this.Pages; $p++) {
                    for ($col = $colLow; $col -le $colHigh; $col++) {
                        $this.FrameBuffer[$p * $this.Width + $col] = 0
                    }
                }
            }
            270 {
                # Logical ly -> physical x = ly; all physical pages touched
                [int]$colLow  = $yStart
                [int]$colHigh = $yEnd
                for ($p = 0; $p -lt $this.Pages; $p++) {
                    for ($col = $colLow; $col -le $colHigh; $col++) {
                        $this.FrameBuffer[$p * $this.Width + $col] = 0
                    }
                }
            }
        }
    }

    # Send one physical page from the framebuffer to the hardware.
    hidden [bool] FlushPhysPage([int]$physPage) {
        try {
            Write-Ssd1306Page -device $this -physPage $physPage -frameBuffer $this.FrameBuffer -width $this.Width | Out-Null
            return $true
        } catch {
            $this.Logger.WriteError("FlushPhysPage $physPage failed: $_")
            return $false
        }
    }

    # Send all physical pages to the hardware as a single bulk transfer.
    hidden [bool] FlushAll() {
        try {
            Write-Ssd1306Display -device $this -frameBuffer $this.FrameBuffer -pages $this.Pages | Out-Null
            return $true
        } catch {
            $this.Logger.WriteError("FlushAll failed: $_")
            return $false
        }
    }

    # Send the physical pages affected by logical rows yStart..yEnd.
    # 0deg/180deg: only the 1-2 physical pages that overlap; 90deg/270deg: all pages.
    hidden [bool] FlushLogicalRows([int]$yStart, [int]$yEnd) {
        switch ($this.Rotation) {
            0 {
                [int]$p0 = $yStart -shr 3
                [int]$p1 = $yEnd   -shr 3
                for ($p = $p0; $p -le $p1; $p++) {
                    if (-not $this.FlushPhysPage($p)) { return $false }
                }
            }
            180 {
                [int]$p0 = $this.Pages - 1 - ($yEnd   -shr 3)
                [int]$p1 = $this.Pages - 1 - ($yStart -shr 3)
                for ($p = $p0; $p -le $p1; $p++) {
                    if (-not $this.FlushPhysPage($p)) { return $false }
                }
            }
            { $_ -eq 90 -or $_ -eq 270 } {
                # Logical rows touch all physical pages in 90/270 orientation
                if (-not $this.FlushAll()) { return $false }
            }
        }
        return $true
    }
}