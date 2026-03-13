#Requires -Version 5.1

function Connect-PsGadgetPca9685 {
    <#
    .SYNOPSIS
    Connects to a PCA9685 PWM controller and initializes it.

    .DESCRIPTION
    Opens an FTDI connection and initializes a PCA9685 16-channel PWM controller
    at the specified I2C address. Returns a PsGadgetPca9685 class instance ready for use.

    .PARAMETER Index
    The index of the FTDI device to connect to (from List-PsGadgetFtdi).
    Default is 0 (first device).

    .PARAMETER Address
    The I2C address of the PCA9685 device. Default is 0x40 (standard address).

    .PARAMETER Frequency
    The PWM frequency in Hz. Default is 50 (for RC servos). Valid range: 23-1526 Hz.

    .PARAMETER Connection
    An existing PsGadgetFtdi connection object (from New-PsGadgetFtdi or Connect-PsGadgetFtdi).
    If provided, -Index is ignored.

    .EXAMPLE
    # Connect to PCA9685 at standard address, default 50 Hz
    $pca = Connect-PsGadgetPca9685 -Index 0

    .EXAMPLE
    # Connect to PCA9685 at custom address
    $pca = Connect-PsGadgetPca9685 -Index 0 -Address 0x41

    .EXAMPLE
    # Reuse existing FTDI connection
    $dev = New-PsGadgetFtdi -Index 0
    $pca = Connect-PsGadgetPca9685 -Connection $dev

    .NOTES
    Requires MpsseI2c mode. If the device is not already in MpsseI2c mode,
    this function will configure it.

    Wire your FTDI device:
    - D0 (ADBUS0) -> SCL
    - D1 (ADBUS1) -> SDA
    - Add 4.7k pull-up resistors on both SCL and SDA lines
    #>

    [CmdletBinding(DefaultParameterSetName = 'Index')]
    [OutputType([PsGadgetPca9685])]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Index')]
        [ValidateRange(0, 127)]
        [int]$Index = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0x40, 0x47)]
        [byte]$Address = 0x40,

        [Parameter(Mandatory = $false)]
        [ValidateRange(23, 1526)]
        [int]$Frequency = 50,

        [Parameter(Mandatory = $true, ParameterSetName = 'Connection')]
        [ValidateNotNull()]
        [PsGadgetFtdi]$Connection
    )

    try {
        # Get or open FTDI connection
        $ftdi = $null

        if ($PSCmdlet.ParameterSetName -eq 'Connection') {
            if (-not $Connection.IsOpen) {
                throw "Provided FTDI connection is not open"
            }
            $ftdi = $Connection
        } else {
            $ftdi = New-PsGadgetFtdi -Index $Index
            if (-not $ftdi -or -not $ftdi.IsOpen) {
                throw "Failed to open FTDI device at index $Index"
            }
        }

        # Configure for I2C if not already
        Write-Verbose "Setting FTDI device to MpsseI2c mode"
        Set-PsGadgetFtdiMode -PsGadget $ftdi -Mode MpsseI2c | Out-Null

        # Create PCA9685 instance
        $pca = [PsGadgetPca9685]::new($ftdi._connection, $Address)
        $pca.Frequency = $Frequency

        # Initialize
        if (-not $pca.Initialize()) {
            throw "Failed to initialize PCA9685"
        }

        Write-Verbose "PCA9685 connected and initialized at address 0x$($Address.ToString('X2'))"

        return $pca

    } catch {
        Write-Error "Failed to connect PCA9685: $_"
        if ($PSCmdlet.ParameterSetName -eq 'Index' -and $null -ne $ftdi) {
            $ftdi.Close()
        }
        return $null
    }
}
