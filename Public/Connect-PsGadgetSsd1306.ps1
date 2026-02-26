# Connect-PsGadgetSsd1306.ps1
# Create and initialize SSD1306 OLED display connection

function Connect-PsGadgetSsd1306 {
    <#
    .SYNOPSIS
    Creates a connection to an SSD1306 OLED display via FTDI I2C.
    
    .DESCRIPTION
    Initializes an SSD1306 OLED display connected to an FTDI device via I2C.
    Creates a PsGadgetSsd1306 instance and performs display initialization.
    
    .PARAMETER FtdiDevice
    FTDI device handle from Connect-PsGadgetFtdi
    
    .PARAMETER Address
    I2C address of the SSD1306 display (default: 0x3C)
    
    .PARAMETER Force
    Force re-initialization even if already initialized
    
    .EXAMPLE
    $ftdi = Connect-PsGadgetFtdi -Index 0
    $display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi
    
    .EXAMPLE
    $display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi -Address 0x3D
    
    .OUTPUTS
    PsGadgetSsd1306 object if successful, $null if failed
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByConnection')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByConnection', Position = 0)]
        [System.Object]$FtdiDevice,

        [Parameter(Mandatory = $true, ParameterSetName = 'PsGadget', Position = 0)]
        [ValidateNotNull()]
        [PsGadgetFtdi]$PsGadget,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0x08, 0x77)]
        [byte]$Address = 0x3C,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        # Resolve the underlying connection object
        if ($PSCmdlet.ParameterSetName -eq 'PsGadget') {
            if (-not $PsGadget.IsOpen -or -not $PsGadget._connection) {
                throw "PsGadgetFtdi is not open. Call .Connect() first."
            }
            $FtdiDevice = $PsGadget._connection
        }

        # Validate FTDI device
        if (-not $FtdiDevice -or -not $FtdiDevice.IsOpen) {
            throw "FTDI device is not valid or not open"
        }
        
        # Create SSD1306 instance
        $ssd1306 = [PsGadgetSsd1306]::new($FtdiDevice, $Address)
        
        # Initialize the display
        if (-not $ssd1306.Initialize($Force)) {
            throw "Failed to initialize SSD1306 display"
        }
        
        Write-Verbose ("SSD1306 display connected successfully at address 0x{0:X2}" -f $Address)
        return $ssd1306
        
    } catch {
        Write-Error "Failed to connect SSD1306 display: $_"
        return $null
    }
}