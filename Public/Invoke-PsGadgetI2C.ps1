#Requires -Version 5.1

function Invoke-PsGadgetI2C {
    <#
    .SYNOPSIS
    Configures an I2C peripheral attached to an FTDI device in a single command.

    .DESCRIPTION
    High-level I2C dispatch function.  Connects to an FTDI device, configures it
    for MPSSE I2C, initialises the selected I2C module, drives it with the
    supplied parameters, then closes the connection automatically.

    -I2CModule selects the target chip and activates module-specific parameters.
    Currently supports:

        PCA9685    16-channel 12-bit PWM controller (RC servos, LEDs, fans).
                   Add -ServoAngle to set one or more channels:
                     Single channel:    -ServoAngle @(0, 90)
                     Multiple channels: -ServoAngle @(@(0,90), @(1,180), @(2,45))

        SSD1306    128x64 I2C OLED display (default address 0x3C).
                   -Text     Write a single line of text to a page (0-7).
                   -FontSize 2 renders double-height text spanning page and page+1.
                   -Symbol   Draw a named 8x8/16x16 sysadmin icon.
                   -Clear    Blank the display or a specific page.
                   Supported symbols: Warning, Alert, Checkmark, Error, Info, Lock, Unlock, Network.

    .PARAMETER PsGadget
    An already-open PsGadgetFtdi object (from New-PsGadgetFtdi).
    When supplied the device is NOT closed after the call.

    .PARAMETER Index
    FTDI device index (0-based) from List-PsGadgetFtdi.
    Default is 0.

    .PARAMETER SerialNumber
    FTDI device serial number (e.g. "FTAXBFCQ").
    Preferred over Index for stable identification across USB re-plugs.

    .PARAMETER I2CAddress
    I2C address of the target module.  Default is 0x40 (PCA9685 standard address).

    .PARAMETER I2CModule
    The I2C module type.  Activates module-specific dynamic parameters.
    Supported values: 'PCA9685'

    .PARAMETER Frequency
    PWM frequency in Hz.  Default is 50 (standard RC servo frequency).
    Valid range: 23-1526 Hz.  Only used when -I2CModule is 'PCA9685'.

    .PARAMETER ServoAngle (dynamic - PCA9685 only)
    Channel and servo angle specification.  Two accepted shapes:

        Single pair:
            @(<channel>, <degrees>)
            e.g. @(0, 90)

        Multiple pairs (any collection of 2-element arrays):
            @(@(<ch>, <deg>), @(<ch>, <deg>), ...)
            e.g. @(@(0, 90), @(1, 180), @(2, 45))

        Channel range:  0-15
        Degrees range:  0-180

    .PARAMETER PulseMinUs
    Minimum servo pulse width in microseconds.  Default is 500 (0.5 ms).
    Adjust for servos with non-standard pulse ranges.  Valid range: 100-3000.

    .PARAMETER PulseMaxUs
    Maximum servo pulse width in microseconds.  Default is 2500 (2.5 ms).
    Adjust for servos with non-standard pulse ranges.  Valid range: 100-3000.

    .EXAMPLE
    # Move servo on channel 0 to 90 degrees
    Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -ServoAngle @(0, 90)

    .EXAMPLE
    # Move servos on channels 0, 1, 2 simultaneously
    Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -ServoAngle @(@(0,90), @(1,180), @(2,45))

    .EXAMPLE
    # Use an already-open device object (device stays open after call)
    $dev = New-PsGadgetFtdi -Index 0
    Invoke-PsGadgetI2C -PsGadget $dev -I2CModule PCA9685 -ServoAngle @(0, 90)

    .EXAMPLE
    # Use device serial number (stable across replug)
    Invoke-PsGadgetI2C -SerialNumber "FTAXBFCQ" -I2CModule PCA9685 -ServoAngle @(0, 0)

    .EXAMPLE
    # 200 Hz frequency for LED dimming (not servo)
    Invoke-PsGadgetI2C -Index 0 -I2CModule PCA9685 -Frequency 200 -ServoAngle @(0, 90)

    .OUTPUTS
    PSCustomObject with Module, Address, Frequency, and ChannelsSet (array of Channel/Degrees records).

    .NOTES
    When using -Index or -SerialNumber the FTDI device is opened and closed within
    this call.  When using -PsGadget the caller retains ownership and the device
    is NOT closed after the call.
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    [OutputType('PSCustomObject')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByDevice', Position = 0)]
        [ValidateNotNull()]
        [object]$PsGadget,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByIndex')]
        [ValidateRange(0, 127)]
        [int]$Index = 0,

        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0x08, 0x77)]
        [byte]$I2CAddress = 0x40,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PCA9685','SSD1306')]
        [string]$I2CModule,

        [Parameter(Mandatory = $false)]
        [ValidateRange(23, 1526)]
        [int]$Frequency = 50,

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 3000)]
        [int]$PulseMinUs = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 3000)]
        [int]$PulseMaxUs = 2500
    )

    DynamicParam {
        $dynParams = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

        if ($PSBoundParameters['I2CModule'] -eq 'PCA9685') {
            # ServoAngle (mandatory)
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $true
            $paramAttr.HelpMessage = 'Single @(channel,degrees) or array of pairs @(@(ch,deg),...)'
            $attrs.Add($paramAttr)
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new(
                'ServoAngle', [object[]], $attrs
            )
            $dynParams.Add('ServoAngle', $rp)

        }

        if ($PSBoundParameters['I2CModule'] -eq 'SSD1306') {
            # Text
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('Text', [string], $attrs)
            $dynParams.Add('Text', $rp)

            # Page
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $attrs.Add([System.Management.Automation.ValidateRangeAttribute]::new(0, 7))
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('Page', [int], $attrs)
            $dynParams.Add('Page', $rp)

            # Align
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $attrs.Add([System.Management.Automation.ValidateSetAttribute]::new([string[]]@('left','center','right')))
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('Align', [string], $attrs)
            $dynParams.Add('Align', $rp)

            # FontSize
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $attrs.Add([System.Management.Automation.ValidateRangeAttribute]::new(1, 2))
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('FontSize', [int], $attrs)
            $dynParams.Add('FontSize', $rp)

            # Invert
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('Invert', [switch], $attrs)
            $dynParams.Add('Invert', $rp)

            # Symbol
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $attrs.Add([System.Management.Automation.ValidateSetAttribute]::new([string[]]@('Warning','Alert','Checkmark','Error','Info','Lock','Unlock','Network')))
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('Symbol', [string], $attrs)
            $dynParams.Add('Symbol', $rp)

            # Clear
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('Clear', [switch], $attrs)
            $dynParams.Add('Clear', $rp)

            # Column
            $attrs = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $paramAttr = [System.Management.Automation.ParameterAttribute]::new()
            $paramAttr.Mandatory = $false
            $attrs.Add($paramAttr)
            $attrs.Add([System.Management.Automation.ValidateRangeAttribute]::new(0, 127))
            $rp = [System.Management.Automation.RuntimeDefinedParameter]::new('Column', [int], $attrs)
            $dynParams.Add('Column', $rp)
        }

        return $dynParams
    }

    process {
        $ownsDevice = $PSCmdlet.ParameterSetName -ne 'ByDevice'
        $ftdi = $null
        try {
            if ($PSCmdlet.ParameterSetName -eq 'ByDevice') {
                $ftdi = $PsGadget
                if (-not $ftdi -or -not $ftdi.IsOpen) {
                    throw "PsGadgetFtdi object is not open."
                }
                Write-Verbose "Using provided PsGadgetFtdi device"
            } elseif ($PSCmdlet.ParameterSetName -eq 'BySerial') {
                Write-Verbose "Opening FTDI device serial '$SerialNumber'"
                $ftdi = New-PsGadgetFtdi -SerialNumber $SerialNumber
            } else {
                Write-Verbose "Opening FTDI device index $Index"
                $ftdi = New-PsGadgetFtdi -Index $Index
            }

            if (-not $ftdi -or -not $ftdi.IsOpen) {
                throw "Failed to open FTDI device"
            }

            # --- apply module-specific address default if not supplied by caller ---
            if (-not $PSBoundParameters.ContainsKey('I2CAddress')) {
                if ($I2CModule -eq 'SSD1306') { $I2CAddress = 0x3C }
                # PCA9685 keeps its param-block default of 0x40
            }

            # --- configure MPSSE I2C (skip if already initialized this session) ---
            if ($null -eq $ftdi._connection -or $ftdi._connection.GpioMethod -ne 'MpsseI2c') {
                Write-Verbose "Setting FTDI to MpsseI2c mode"
                Set-PsGadgetFtdiMode -PsGadget $ftdi -Mode MpsseI2c | Out-Null
            } else {
                Write-Verbose "FTDI already in MpsseI2c mode"
            }

            # --- dispatch to module handler ---
            switch ($I2CModule) {
                'PCA9685' {
                    $pulseMinUs = $PulseMinUs
                    $pulseMaxUs = $PulseMaxUs
                    return Invoke-PsGadgetI2CPca9685 `
                        -Ftdi         $ftdi `
                        -I2CAddress   $I2CAddress `
                        -Frequency    $Frequency `
                        -ServoAngle   $PSBoundParameters['ServoAngle'] `
                        -PulseMinUs   $pulseMinUs `
                        -PulseMaxUs   $pulseMaxUs
                }
                'SSD1306' {
                    $text     = $PSBoundParameters['Text']
                    $page     = if ($PSBoundParameters.ContainsKey('Page')) { $PSBoundParameters['Page'] } else { -1 }
                    $align    = if ($PSBoundParameters['Align']) { $PSBoundParameters['Align'] } else { 'left' }
                    $fontSize = if ($PSBoundParameters.ContainsKey('FontSize')) { $PSBoundParameters['FontSize'] } else { 1 }
                    $invert   = [bool]$PSBoundParameters['Invert']
                    $symbol   = $PSBoundParameters['Symbol']
                    $clear    = [bool]$PSBoundParameters['Clear']
                    $column   = if ($PSBoundParameters.ContainsKey('Column')) { $PSBoundParameters['Column'] } else { 0 }
                    return Invoke-PsGadgetI2CSsd1306 `
                        -Ftdi       $ftdi `
                        -I2CAddress $I2CAddress `
                        -Text       $text `
                        -Page       $page `
                        -Align      $align `
                        -FontSize   $fontSize `
                        -Invert:$invert `
                        -Symbol     $symbol `
                        -Clear:$clear `
                        -Column     $column
                }
            }
        } finally {
            if ($ownsDevice -and $ftdi -and $ftdi.IsOpen) {
                Write-Verbose "Closing FTDI device"
                $ftdi.Close()
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Private helper: PCA9685 dispatch
# Not exported.  Called only by Invoke-PsGadgetI2C.
# ---------------------------------------------------------------------------
function Invoke-PsGadgetI2CPca9685 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Ftdi,

        [Parameter(Mandatory = $true)]
        [byte]$I2CAddress,

        [Parameter(Mandatory = $true)]
        [int]$Frequency,

        [Parameter(Mandatory = $true)]
        [object[]]$ServoAngle,

        [Parameter(Mandatory = $false)]
        [int]$PulseMinUs = 500,

        [Parameter(Mandatory = $false)]
        [int]$PulseMaxUs = 2500
    )

    # --- parse ServoAngle into normalised list of [channel, degrees] pairs ---
    # Shape 1: flat 2-element int array  @(0, 90)         -> single pair
    # Shape 2: array of 2-element arrays @(@(0,90),@(1,180)) -> multiple pairs
    $pairs = @()

    if ($ServoAngle[0] -is [int] -or $ServoAngle[0] -is [long]) {
        # Flat pair - treat as single channel specification
        if ($ServoAngle.Count -ne 2) {
            throw "ServoAngle flat pair must have exactly 2 elements: @(channel, degrees). Got $($ServoAngle.Count) elements."
        }
        $pairs = @(, @([int]$ServoAngle[0], [int]$ServoAngle[1]))
    } else {
        # Array of pairs
        foreach ($item in $ServoAngle) {
            $arr = @($item)
            if ($arr.Count -ne 2) {
                throw "Each ServoAngle pair must have exactly 2 elements: @(channel, degrees). Got $($arr.Count) elements in one pair."
            }
            $pairs += , @([int]$arr[0], [int]$arr[1])
        }
    }

    if ($pairs.Count -eq 0) {
        throw "ServoAngle must contain at least one channel/degrees pair."
    }

    # --- validate all pairs before touching hardware ---
    foreach ($pair in $pairs) {
        $ch  = $pair[0]
        $deg = $pair[1]
        if ($ch -lt 0 -or $ch -gt 15) {
            throw "Channel $ch is out of range.  Valid range: 0-15."
        }
        if ($deg -lt 0 -or $deg -gt 180) {
            throw "Degrees $deg is out of range.  Valid range: 0-180."
        }
    }

    # --- get or create PCA9685 instance (cached per FTDI device + address) ---
    $cacheKey = "PCA9685:$($I2CAddress.ToString('X2'))"
    $pca = $null
    if ($Ftdi._i2cDevices -and $Ftdi._i2cDevices.ContainsKey($cacheKey)) {
        $pca = $Ftdi._i2cDevices[$cacheKey]
        if ($pca.Frequency -ne $Frequency) {
            Write-Verbose "PCA9685 frequency changed ($($pca.Frequency)->$Frequency Hz), reinitializing"
            $pca.Frequency = $Frequency
            if (-not $pca.Initialize($true)) {
                throw "PCA9685 reinitialize failed at address 0x$($I2CAddress.ToString('X2'))"
            }
        } else {
            Write-Verbose "Using cached PCA9685 at 0x$($I2CAddress.ToString('X2')) ($($pca.Frequency) Hz)"
        }
        if ($pca.PulseMinUs -ne $PulseMinUs -or $pca.PulseMaxUs -ne $PulseMaxUs) {
            Write-Verbose "PCA9685 pulse range updated: $($pca.PulseMinUs)-$($pca.PulseMaxUs) -> $PulseMinUs-$PulseMaxUs us"
            $pca.PulseMinUs = $PulseMinUs
            $pca.PulseMaxUs = $PulseMaxUs
        }
    } else {
        Write-Verbose "Creating PCA9685 at I2C address 0x$($I2CAddress.ToString('X2')), frequency $Frequency Hz"
        $pca = [PsGadgetPca9685]::new($Ftdi._connection, $I2CAddress)
        $pca.Frequency = $Frequency
        $pca.PulseMinUs = $PulseMinUs
        $pca.PulseMaxUs = $PulseMaxUs
        if (-not $pca.Initialize($false)) {
            throw "PCA9685 Initialize() failed at address 0x$($I2CAddress.ToString('X2'))"
        }
        if ($Ftdi._i2cDevices) { $Ftdi._i2cDevices[$cacheKey] = $pca }
    }

    # --- set channels ---
    $channelsSet = @()
    foreach ($pair in $pairs) {
        $ch  = $pair[0]
        $deg = $pair[1]
        Write-Verbose "PCA9685 ch$ch -> $deg deg"
        if (-not $pca.SetChannel($ch, $deg)) {
            throw "PCA9685 SetChannel failed: channel=$ch degrees=$deg"
        }
        $channelsSet += [PSCustomObject]@{ Channel = $ch; Degrees = $deg }
    }

    # --- return summary ---
    return [PSCustomObject]@{
        Module      = 'PCA9685'
        Address     = '0x' + $I2CAddress.ToString('X2')
        Frequency   = $Frequency
        ChannelsSet = $channelsSet
    }
}

# ---------------------------------------------------------------------------
# Private helper: SSD1306 dispatch
# Not exported.  Called only by Invoke-PsGadgetI2C.
# ---------------------------------------------------------------------------
function Invoke-PsGadgetI2CSsd1306 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Ftdi,

        [Parameter(Mandatory = $true)]
        [byte]$I2CAddress,

        [Parameter(Mandatory = $false)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [int]$Page = -1,

        [Parameter(Mandatory = $false)]
        [string]$Align = 'left',

        [Parameter(Mandatory = $false)]
        [int]$FontSize = 1,

        [Parameter(Mandatory = $false)]
        [switch]$Invert,

        [Parameter(Mandatory = $false)]
        [string]$Symbol,

        [Parameter(Mandatory = $false)]
        [switch]$Clear,

        [Parameter(Mandatory = $false)]
        [int]$Column = 0
    )

    # --- validate mutual exclusions ---
    if ($Text -and $Symbol) {
        throw "Specify either -Text or -Symbol, not both."
    }
    if (($Text -or $Symbol) -and $Page -lt 0) {
        throw "-Page (0-7) is required when using -Text or -Symbol."
    }

    # --- get or create cached SSD1306 instance ---
    $cacheKey = "SSD1306:$($I2CAddress.ToString('X2'))"
    $ssd = $null
    if ($Ftdi._i2cDevices -and $Ftdi._i2cDevices.ContainsKey($cacheKey)) {
        $ssd = $Ftdi._i2cDevices[$cacheKey]
        Write-Verbose "Using cached SSD1306 at 0x$($I2CAddress.ToString('X2'))"
    } else {
        Write-Verbose "Creating SSD1306 at I2C address 0x$($I2CAddress.ToString('X2'))"
        $ssd = [PsGadgetSsd1306]::new($Ftdi._connection, $I2CAddress)
        if (-not $ssd.Initialize($false)) {
            throw "SSD1306 Initialize() failed at address 0x$($I2CAddress.ToString('X2'))"
        }
        if ($Ftdi._i2cDevices) { $Ftdi._i2cDevices[$cacheKey] = $ssd }
    }

    # --- dispatch ---
    $action = 'init'

    if ($Clear) {
        if ($Page -ge 0) {
            if (-not $ssd.ClearPage($Page)) { throw "SSD1306 ClearPage($Page) failed" }
            $action = "clear-page-$Page"
        } else {
            if (-not $ssd.Clear()) { throw "SSD1306 Clear() failed" }
            $action = 'clear'
        }
    } elseif ($Symbol) {
        if (-not $ssd.DrawSymbol($Symbol, $Page, $Column)) {
            throw "SSD1306 DrawSymbol('$Symbol', page=$Page, col=$Column) failed"
        }
        $action = "symbol-$Symbol"
    } elseif ($Text) {
        if ($FontSize -eq 2) {
            if (-not $ssd.WriteTextTall($Text, $Page, $Align, [bool]$Invert)) {
                throw "SSD1306 WriteTextTall('$Text', page=$Page) failed"
            }
        } else {
            if (-not $ssd.WriteText($Text, $Page, $Align, 1, [bool]$Invert)) {
                throw "SSD1306 WriteText('$Text', page=$Page) failed"
            }
        }
        $action = "write-text"
    }

    return [PSCustomObject]@{
        Module  = 'SSD1306'
        Address = '0x{0:X2}' -f $I2CAddress
        Action  = $action
        Page    = $Page
    }
}
