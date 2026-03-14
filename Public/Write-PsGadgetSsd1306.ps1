# Write-PsGadgetSsd1306.ps1
# DEPRECATED - use Invoke-PsGadgetI2C -I2CModule SSD1306 -Text instead.
# Write text to SSD1306 OLED display

function Write-PsGadgetSsd1306 {
    <#
    .SYNOPSIS
    Writes text to an SSD1306 OLED display.
    
    .DESCRIPTION
    Writes text to a specific page on an SSD1306 display with various formatting options.
    Supports alignment, font scaling, and text inversion.
    
    .PARAMETER Display
    SSD1306 display instance from Connect-PsGadgetSsd1306
    
    .PARAMETER Text
    Text string to display
    
    .PARAMETER Page
    Display page (row) to write to (0-7)
    
    .PARAMETER Align
    Text alignment: 'left', 'center', or 'right' (default: 'left')
    
    .PARAMETER FontSize
    Font size scaling: 1 (normal) or 2 (double width) (default: 1)
    
    .PARAMETER Invert
    Invert text colors (white on black becomes black on white)
    
    .EXAMPLE
    Write-PsGadgetSsd1306 -Display $display -Text "Hello World" -Page 0
    
    .EXAMPLE
    Write-PsGadgetSsd1306 -Display $display -Text "ALARM" -Page 1 -Align center -FontSize 2 -Invert
    
    .EXAMPLE
    Write-PsGadgetSsd1306 -Display $display -Text "Status: OK" -Page 3 -Align right
    
    .OUTPUTS
    None. Throws on failure.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$Display,
        
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 7)]
        [int]$Page,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('left', 'center', 'right')]
        [string]$Align = 'left',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet(1, 2)]
        [int]$FontSize = 1,
        
        [Parameter(Mandatory = $false)]
        [switch]$Invert
    )
    
    try {
        if ($null -eq $Display) {
            throw "Display instance is null"
        }
        
        $result = $Display.WriteText($Text, $Page, $Align, $FontSize, $Invert)
        Write-Verbose "Text '$Text' written to SSD1306 page $Page"
        
    } catch {
        Write-Error "Failed to write text to SSD1306 display: $_"
    }
}