# Clear-PsGadgetSsd1306.ps1
# Clear SSD1306 OLED display

function Clear-PsGadgetSsd1306 {
    <#
    .SYNOPSIS
    Clears an SSD1306 OLED display.
    
    .DESCRIPTION
    Clears the entire SSD1306 display or a specific page.
    
    .PARAMETER Display
    SSD1306 display instance from Connect-PsGadgetSsd1306
    
    .PARAMETER Page
    Specific page to clear (0-7). If not specified, clears entire display.
    
    .EXAMPLE
    Clear-PsGadgetSsd1306 -Display $display
    
    .EXAMPLE
    Clear-PsGadgetSsd1306 -Display $display -Page 2
    
    .OUTPUTS
    [bool] $true if successful, $false if failed
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$Display,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 7)]
        [int]$Page
    )
    
    try {
        if ($null -eq $Display) {
            throw "Display instance is null"
        }
        
        if ($PSBoundParameters.ContainsKey('Page')) {
            # Clear specific page
            $result = $Display.ClearPage($Page)
            if ($result) {
                Write-Verbose "SSD1306 page $Page cleared successfully"
            }
            return $result
        } else {
            # Clear entire display
            $result = $Display.Clear()
            if ($result) {
                Write-Verbose "SSD1306 display cleared successfully"
            }
            return $result
        }
        
    } catch {
        Write-Error "Failed to clear SSD1306 display: $_"
        return $false
    }
}