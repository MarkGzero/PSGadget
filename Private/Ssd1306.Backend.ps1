# Ssd1306.Backend.ps1
# SSD1306 low-level I2C command/data helpers
#
# All functions accept [PsGadgetI2CDevice]$device and call $device.I2CWrite() so the
# FtdiSharp / MPSSE / IoT transport layer remains entirely transparent to these helpers.
# PSGadget.psm1 picks this file up automatically via the Private/*.ps1 glob.
#
# Design decisions:
#   - PAGE addressing mode (0x20, 0x02) — cursor commands 0xB0+page / 0x00 / 0x10 stay valid.
#   - Init sequence is sent as ONE batched I2C command write (single USB transaction).
#   - Page and full-display writes use two I2C transactions each (cursor/window + data).
#   - No per-command Start-Sleep calls; 5ms settling sleep after the init sequence only.

function Send-Ssd1306Command {
    <#
    .SYNOPSIS
        Send one or more SSD1306 command bytes in a single I2C write transaction.
    .PARAMETER device
        PsGadgetI2CDevice wrapping the I2C transport (MPSSE, FtdiSharp, or IoT).
    .PARAMETER commands
        Byte array of SSD1306 command bytes (without the 0x00 control byte).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$device,

        [Parameter(Mandatory = $true)]
        [byte[]]$commands
    )

    try {
        # 0x00 = Co=0 D/C#=0 — single control byte that applies to all following command bytes.
        $payload = [byte[]]::new($commands.Length + 1)
        $payload[0] = [byte]0x00
        [System.Array]::Copy($commands, 0, $payload, 1, $commands.Length)
        if (-not $device.I2CWrite($payload)) {
            throw "I2CWrite returned false sending SSD1306 command(s)"
        }
        return $true
    } catch {
        Write-Verbose ("Send-Ssd1306Command failed: {0}" -f $_)
        throw
    }
}

function Send-Ssd1306Data {
    <#
    .SYNOPSIS
        Send one or more SSD1306 data bytes in a single I2C write transaction.
    .PARAMETER device
        PsGadgetI2CDevice wrapping the I2C transport.
    .PARAMETER data
        Byte array of display data (GDDRAM bytes, without the 0x40 control byte).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$device,

        [Parameter(Mandatory = $true)]
        [byte[]]$data
    )

    try {
        # 0x40 = Co=0 D/C#=1 — single control byte indicating all following bytes are data.
        $payload = [byte[]]::new($data.Length + 1)
        $payload[0] = [byte]0x40
        [System.Array]::Copy($data, 0, $payload, 1, $data.Length)
        if (-not $device.I2CWrite($payload)) {
            throw "I2CWrite returned false sending SSD1306 data"
        }
        return $true
    } catch {
        Write-Verbose ("Send-Ssd1306Data failed: {0}" -f $_)
        throw
    }
}

function Initialize-Ssd1306 {
    <#
    .SYNOPSIS
        Send the full SSD1306 initialization sequence as a single batched I2C command write.
    .PARAMETER device
        PsGadgetI2CDevice wrapping the I2C transport.
    .PARAMETER height
        Display height in pixels (32 or 64).
    .PARAMETER rotation
        Display rotation in degrees (0, 90, 180, 270).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$device,

        [Parameter(Mandatory = $true)]
        [int]$height,

        [Parameter(Mandatory = $false)]
        [int]$rotation = 0
    )

    try {
        # Height-dependent init values:
        #   128x64: mux=0x3F (63), COM pins=0x12 (alt config)
        #   128x32: mux=0x1F (31), COM pins=0x02 (sequential)
        [byte]$muxRatio = [byte]($height - 1)
        [byte]$comPins  = if ($height -eq 32) { 0x02 } else { 0x12 }

        # Segment remap and COM scan direction depend on rotation.
        # 0/90/270 deg = standard orientation; 180 deg = both flipped.
        [byte]$segRemap = if ($rotation -eq 180) { 0xA0 } else { 0xA1 }
        [byte]$comScan  = if ($rotation -eq 180) { 0xC0 } else { 0xC8 }

        # Full SSD1306 initialization sequence — HORIZONTAL addressing mode (0x20 0x00).
        # Commands are sent one byte per I2C transaction (matching the proven reference
        # implementation). Some SSD1306 clones do not handle multi-byte streaming mode
        # (Co=0) reliably during init; per-byte writes are universally compatible.
        [byte[]]$initCommands = @(
            0xAE,                      # Display OFF
            0xD5, 0x80,                # Set Display Clock Divide Ratio / Oscillator Frequency
            0xA8, $muxRatio,           # Set Multiplex Ratio (height-dependent)
            0xD3, 0x00,                # Set Display Offset (no offset)
            0x40,                      # Set Display Start Line = 0
            0x8D, 0x14,                # Charge Pump Setting (Enable)
            0x20, 0x00,                # Memory Addressing Mode = HORIZONTAL
            $segRemap,                 # Segment re-map (rotation-dependent)
            $comScan,                  # COM output scan direction (rotation-dependent)
            0xDA, $comPins,            # Set COM Pins Hardware Configuration (height-dependent)
            0x81, 0xCF,                # Set Contrast Control (0xCF = high)
            0xD9, 0xF1,                # Set Pre-charge Period
            0xDB, 0x40,                # Set VCOMH Deselect Level
            0xA4,                      # Resume to RAM content display
            0xA6,                      # Normal display (non-inverted)
            0xAF                       # Display ON
        )

        Write-Verbose ("Initialize-Ssd1306: sending {0} init bytes (height={1}, rotation={2})" -f $initCommands.Length, $height, $rotation)
        foreach ($cmd in $initCommands) {
            $device.I2CWrite([byte[]](0x00, $cmd)) | Out-Null
            Start-Sleep -Milliseconds 1
        }

        return $true
    } catch {
        Write-Verbose ("Initialize-Ssd1306 failed: {0}" -f $_)
        throw
    }
}

function Write-Ssd1306Page {
    <#
    .SYNOPSIS
        Write one physical page from the framebuffer to the SSD1306 using 2 I2C transactions.
    .DESCRIPTION
        Transaction 1: PAGE-mode cursor set command (0xB0+page, 0x00, 0x10).
        Transaction 2: 128 data bytes from the framebuffer for this page.
    .PARAMETER device
        PsGadgetI2CDevice wrapping the I2C transport.
    .PARAMETER physPage
        Physical page number (0-based).
    .PARAMETER frameBuffer
        Flat byte array: width * pages bytes, row-major, page-interleaved.
    .PARAMETER width
        Display width in pixels (nominally 128).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$device,

        [Parameter(Mandatory = $true)]
        [int]$physPage,

        [Parameter(Mandatory = $true)]
        [byte[]]$frameBuffer,

        [Parameter(Mandatory = $true)]
        [int]$width
    )

    try {
        # HORIZONTAL addressing mode window: constrain column 0-127, page N-N.
        # 0xB0+page cursor commands are PAGE mode only and are ignored in HORIZONTAL mode.
        # Each command byte is sent as its own I2C transaction (same pattern as init).
        $device.I2CWrite([byte[]](0x00, [byte]0x21)) | Out-Null              # SET_COL_ADDR
        $device.I2CWrite([byte[]](0x00, [byte]0x00)) | Out-Null              # col start = 0
        $device.I2CWrite([byte[]](0x00, [byte]0x7F)) | Out-Null              # col end   = 127
        $device.I2CWrite([byte[]](0x00, [byte]0x22)) | Out-Null              # SET_PAGE_ADDR
        $device.I2CWrite([byte[]](0x00, [byte]$physPage)) | Out-Null         # page start
        $device.I2CWrite([byte[]](0x00, [byte]$physPage)) | Out-Null         # page end (same)

        # Page data: $width bytes from the framebuffer starting at this page's offset.
        [byte[]]$pageData = [byte[]]::new($width)
        [System.Array]::Copy($frameBuffer, $physPage * $width, $pageData, 0, $width)
        Send-Ssd1306Data -device $device -data $pageData | Out-Null

        Write-Verbose ("Write-Ssd1306Page: page {0} written ({1} bytes)" -f $physPage, $width)
        return $true
    } catch {
        Write-Verbose ("Write-Ssd1306Page failed for page {0}: {1}" -f $physPage, $_)
        throw
    }
}

function Write-Ssd1306Display {
    <#
    .SYNOPSIS
        Write the entire framebuffer to the SSD1306 in 2 I2C transactions.
    .DESCRIPTION
        Transaction 1: Set column window 0-127 and page window 0-(pages-1).
        Transaction 2: All framebuffer bytes sent as a single data write.
        Requires horizontal addressing mode (0x20 0x00) for auto-increment.
        NOTE: Used here for full-display flush in horizontal addressing mode.
              If the device was initialized with PAGE mode, use Write-Ssd1306Page per page.
    .PARAMETER device
        PsGadgetI2CDevice wrapping the I2C transport.
    .PARAMETER frameBuffer
        Flat byte array of width * pages bytes.
    .PARAMETER pages
        Number of physical pages (height / 8).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$device,

        [Parameter(Mandatory = $true)]
        [byte[]]$frameBuffer,

        [Parameter(Mandatory = $true)]
        [int]$pages
    )

    try {
        # Set column address 0-127, page address 0-(pages-1).
        [byte[]]$windowCmd = @(0x21, 0x00, 0x7F, 0x22, 0x00, [byte]($pages - 1))
        Send-Ssd1306Command -device $device -commands $windowCmd | Out-Null

        # Send the entire framebuffer as one data transaction.
        Send-Ssd1306Data -device $device -data $frameBuffer | Out-Null

        Write-Verbose ("Write-Ssd1306Display: {0} bytes written ({1} pages)" -f $frameBuffer.Length, $pages)
        return $true
    } catch {
        Write-Verbose ("Write-Ssd1306Display failed: {0}" -f $_)
        throw
    }
}

function Clear-Ssd1306Display {
    <#
    .SYNOPSIS
        Zero the framebuffer in-place and push all pages to the SSD1306.
    .PARAMETER device
        PsGadgetI2CDevice wrapping the I2C transport.
    .PARAMETER frameBuffer
        Flat byte array of width * pages bytes. Zeroed in-place (reference type).
    .PARAMETER pages
        Number of physical pages (height / 8).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$device,

        [Parameter(Mandatory = $true)]
        [byte[]]$frameBuffer,

        [Parameter(Mandatory = $true)]
        [int]$pages
    )

    try {
        [System.Array]::Clear($frameBuffer, 0, $frameBuffer.Length)
        Write-Ssd1306Display -device $device -frameBuffer $frameBuffer -pages $pages | Out-Null
        Write-Verbose "Clear-Ssd1306Display: framebuffer zeroed and display cleared"
        return $true
    } catch {
        Write-Verbose ("Clear-Ssd1306Display failed: {0}" -f $_)
        throw
    }
}

function Clear-Ssd1306Page {
    <#
    .SYNOPSIS
        Zero one physical page in the framebuffer and write it to the SSD1306.
    .PARAMETER device
        PsGadgetI2CDevice wrapping the I2C transport.
    .PARAMETER physPage
        Physical page number (0-based).
    .PARAMETER frameBuffer
        Flat byte array of width * pages bytes. Page bytes zeroed in-place.
    .PARAMETER width
        Display width in pixels (nominally 128).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$device,

        [Parameter(Mandatory = $true)]
        [int]$physPage,

        [Parameter(Mandatory = $true)]
        [byte[]]$frameBuffer,

        [Parameter(Mandatory = $true)]
        [int]$width
    )

    try {
        [System.Array]::Clear($frameBuffer, $physPage * $width, $width)
        Write-Ssd1306Page -device $device -physPage $physPage -frameBuffer $frameBuffer -width $width | Out-Null
        Write-Verbose ("Clear-Ssd1306Page: physical page {0} cleared" -f $physPage)
        return $true
    } catch {
        Write-Verbose ("Clear-Ssd1306Page failed for page {0}: {1}" -f $physPage, $_)
        throw
    }
}
