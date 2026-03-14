# Set-PsGadgetSsd1306Cursor.ps1
# DEPRECATED - use Invoke-PsGadgetI2C -I2CModule SSD1306 instead.
# Set cursor position on SSD1306 OLED display

function Set-PsGadgetSsd1306Cursor {
    <#
    .SYNOPSIS
    Sets the cursor position on an SSD1306 OLED display.
    
    .DESCRIPTION
    Sets the cursor position for the next write operation on an SSD1306 display.
    Useful for precise positioning of text or graphics.
    
    .PARAMETER Display
    SSD1306 display instance from Connect-PsGadgetSsd1306
    
    .PARAMETER Column
    Column position (0-127)
    
    .PARAMETER Page
    Page (row) position (0-7)
    
    .EXAMPLE
    Set-PsGadgetSsd1306Cursor -Display $display -Column 32 -Page 2
    
    .EXAMPLE
    Set-PsGadgetSsd1306Cursor -Display $display -Column 0 -Page 0  # Top-left corner
    
    .OUTPUTS
    [bool] $true if successful, $false if failed
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$Display,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 127)]
        [int]$Column,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 7)]
        [int]$Page
    )
    
    try {
        if ($null -eq $Display) {
            throw "Display instance is null"
        }
        
        $result = $Display.SetCursor($Column, $Page)
        
        if ($result) {
            Write-Verbose "SSD1306 cursor set to column $Column, page $Page"
        }
        
        return $result
        
    } catch {
        Write-Error "Failed to set SSD1306 cursor position: $_"
        return $false
    }
}