# Classes/PsGadgetSsd1306.ps1
# SSD1306 OLED Display Class

class PsGadgetSsd1306 : PsGadgetI2CDevice {
    [int]$Width
    [int]$Height
    [int]$Pages
    [hashtable]$Glyphs
    
    PsGadgetSsd1306() {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance")
        
        # Default SSD1306 128x64 configuration
        $this.I2CAddress = 0x3C
        $this.Width = 128
        $this.Height = 64
        $this.Pages = 8  # 64 pixels / 8 pixels per page
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
    }
    
    PsGadgetSsd1306([System.Object]$ftdiDevice) {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance with FTDI device")
        
        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = 0x3C
        $this.Width = 128
        $this.Height = 64
        $this.Pages = 8
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
    }
    
    PsGadgetSsd1306([System.Object]$ftdiDevice, [byte]$address) {
        $this.Logger.WriteInfo("Creating PsGadgetSsd1306 instance with FTDI device and address 0x{0:X2}" -f $address)
        
        $this.FtdiDevice = $ftdiDevice
        $this.I2CAddress = $address
        $this.Width = 128
        $this.Height = 64
        $this.Pages = 8
        $this.IsInitialized = $false
        $this.InitializeGlyphs()
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
            
            $this.Logger.WriteDebug("Loaded {0} character glyphs" -f $this.Glyphs.Count)
            
        } catch {
            $this.Logger.WriteError("Failed to initialize glyphs: $_")
            throw
        }
    }
    
    [bool] Initialize([bool]$force) {
        if (-not $this.BeginInitialize($force)) {
            return $this.IsInitialized
        }

        $this.Logger.WriteInfo("Initializing SSD1306 display at address 0x{0:X2}" -f $this.I2CAddress)

        try {
            # SSD1306 initialization sequence
            $initCommands = @(
                0xAE,       # Display OFF
                0xD5, 0x80, # Set Display Clock Divide Ratio / Oscillator Frequency
                0xA8, 0x3F, # Set Multiplex Ratio (1/64 duty)
                0xD3, 0x00, # Set Display Offset (no offset)
                0x40,       # Set Display Start Line = 0
                0x8D, 0x14, # Charge Pump Setting (Enable)
                0x20, 0x00, # Memory Addressing Mode = Horizontal
                0xA1,       # Set Segment Re-map (column address 127 is SEG0)
                0xC8,       # Set COM Output Scan Direction (remapped mode)
                0xDA, 0x12, # Set COM Pins Hardware Configuration
                0x81, 0xCF, # Set Contrast Control (0xCF = high)
                0xD9, 0xF1, # Set Pre-charge Period
                0xDB, 0x40, # Set VCOMH Deselect Level
                0xA4,       # Resume to RAM content display
                0xA6,       # Normal display (non-inverted)
                0xAF        # Display ON
            )
            
            # Send each command with control byte 0x00
            foreach ($cmd in $initCommands) {
                [byte[]]$data = @(0x00, $cmd)
                if (-not $this.I2CWrite($data)) {
                    throw ("Failed to send initialization command: 0x{0:X2}" -f $cmd)
                }
                Start-Sleep -Milliseconds 1
            }
            
            $this.IsInitialized = $true
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
            # Clear all pages
            for ($page = 0; $page -lt $this.Pages; $page++) {
                if (-not $this.ClearPage($page)) {
                    throw "Failed to clear page $page"
                }
            }
            
            $this.Logger.WriteDebug("Display cleared successfully")
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
        
        if ($page -lt 0 -or $page -ge $this.Pages) {
            $this.Logger.WriteError("Invalid page number: $page (valid range: 0-{0})" -f ($this.Pages - 1))
            return $false
        }
        
        try {
            # Set cursor to beginning of page
            if (-not $this.SetCursor(0, $page)) {
                throw "Failed to set cursor"
            }
            
            # Send empty data to fill the page
            [byte[]]$emptyData = @(0x40) + (@(0x00) * $this.Width)

            if (-not $this.I2CWrite($emptyData)) {
                throw "Failed to send clear data"
            }
            
            $this.Logger.WriteTrace("Cleared page $page")
            return $true
            
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
            $this.Logger.WriteError("Invalid column: $column (valid range: 0-{0})" -f ($this.Width - 1))
            return $false
        }
        
        if ($page -lt 0 -or $page -ge $this.Pages) {
            $this.Logger.WriteError("Invalid page: $page (valid range: 0-{0})" -f ($this.Pages - 1))
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
        if (-not $this.IsInitialized) {
            $this.Logger.WriteError("SSD1306 not initialized")
            return $false
        }
        
        if ([string]::IsNullOrEmpty($text)) {
            $this.Logger.WriteDebug("Empty text string, nothing to write")
            return $true
        }
        
        $this.Logger.WriteInfo("Writing text '$text' to page $page (align: $align, size: ${fontSize}x)")
        
        try {
            # Convert text to glyph data
            [System.Collections.Generic.List[byte]]$buffer = @()
            
            foreach ($char in $text.ToCharArray()) {
                if ($this.Glyphs.ContainsKey([string]$char)) {
                    $glyph = $this.Glyphs[[string]$char]
                    foreach ($byte in $glyph) {
                        $buffer.Add([byte]$byte)
                    }
                } else {
                    # Unknown character - use space
                    $space = $this.Glyphs[' ']
                    foreach ($byte in $space) {
                        $buffer.Add([byte]$byte)
                    }
                    $this.Logger.WriteTrace("Unknown character '$char' replaced with space")
                }
            }
            
            # Apply inversion if requested
            if ($invert) {
                for ($i = 0; $i -lt $buffer.Count; $i++) {
                    $buffer[$i] = $buffer[$i] -bxor 0xFF
                }
            }
            
            # Apply font scaling if requested
            if ($fontSize -eq 2) {
                [System.Collections.Generic.List[byte]]$scaled = @()
                foreach ($byte in $buffer) {
                    $scaled.Add($byte)
                    $scaled.Add($byte)  # Duplicate each column horizontally
                }
                $buffer = $scaled
            }
            
            # Determine starting column based on alignment
            $startColumn = switch ($align.ToLower()) {
                'center' { [math]::Max(0, [math]::Floor(($this.Width - $buffer.Count) / 2)) }
                'right'  { [math]::Max(0, $this.Width - $buffer.Count) }
                default  { 0 }
            }
            
            # Set cursor position
            if (-not $this.SetCursor($startColumn, $page)) {
                throw "Failed to set cursor position"
            }
            
            # Send data with control byte 0x40
            [byte[]]$payload = @(0x40) + $buffer.ToArray()

            if (-not $this.I2CWrite($payload)) {
                throw "Failed to send text data"
            }
            
            $this.Logger.WriteDebug("Text written successfully ({0} bytes)" -f $buffer.Count)
            return $true
            
        } catch {
            $this.Logger.WriteError("Failed to write text: $_")
            return $false
        }
    }
}