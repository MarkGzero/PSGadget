@{
    # Module metadata
    RootModule           = 'PSGadget.psm1'
    ModuleVersion        = '0.3.7'
    CompatiblePSEditions = @('Desktop', 'Core')
    GUID                 = '72440f23-d3c6-4249-83eb-9affa6df882b'

    # PowerShell version requirements
    PowerShellVersion = '5.1'

    # Author information
    Author      = 'Mark Go'
    CompanyName = 'Mark Go'
    Copyright   = '(c) 2026 Mark Go. All rights reserved.'
    
    # Description
    Description = 'Production-grade PowerShell module for FTDI hardware control and MicroPython orchestration'
    
    # Exported functions - explicitly declared, no wildcards
    FunctionsToExport = @(
        'New-PsGadgetFtdi',
        'Test-PsGadgetEnvironment',
        'Get-FtdiDevice',
        'Connect-PsGadgetFtdi',
        'Get-PsGadgetMpy',
        'Connect-PsGadgetMpy',
        'Set-PsGadgetGpio',
        'Get-PsGadgetFtdiEeprom',
        'Set-PsGadgetFt232rCbusMode',
        'Set-PsGadgetFtdiEeprom',
        'Set-PsGadgetFtdiMode',
        'Get-PsGadgetConfig',
        'Get-PsGadgetLog',
        'Set-PsGadgetConfig',
        'Install-PsGadgetMpyScript',
        'Get-PsGadgetEspNowDevices',
        'Invoke-PsGadgetI2CScan',
        'Invoke-PsGadgetI2C',
        'Invoke-PsGadgetStepper',
        'Open-PsGadgetTrace'
    )
    
    # No cmdlets, variables, or aliases exported
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @('Test-PsGadgetSetup')
    
    # Files included in this module
    FileList = @(
        'PSGadget.psm1',
        'Classes/PsGadgetTrace.ps1',
        'Classes/PsGadgetLogger.ps1',
        'Classes/PsGadgetI2CDevice.ps1',
        'Classes/PsGadgetSsd1306.ps1',
        'Classes/PsGadgetFtdi.ps1',
        'Classes/PsGadgetMpy.ps1',
        'Classes/PsGadgetPca9685.ps1',
        'Private/Ftdi.PInvoke.ps1',
        'Private/Stepper.Backend.ps1',
        'Private/Ftdi.Backend.ps1',
        'Private/Ftdi.Cbus.ps1',
        'Private/Ftdi.IoT.ps1',
        'Private/Ftdi.Mpsse.ps1',
        'Private/Ftdi.Unix.ps1',
        'Private/Ftdi.Windows.ps1',
        'Private/Initialize-FtdiAssembly.ps1',
        'Private/Initialize-PsGadgetConfig.ps1',
        'Private/Initialize-PsGadgetEnvironment.ps1',
        'Private/Invoke-NativeProcess.ps1',
        'Private/Mpy.Backend.ps1',
        'Private/Send-PsGadgetI2CWrite.ps1',
        'Private/Ssd1306.Backend.ps1',
        'Public/Connect-PsGadgetFtdi.ps1',
        'Public/Connect-PsGadgetMpy.ps1',
        'Public/Get-PsGadgetConfig.ps1',
        'Public/Get-PsGadgetLog.ps1',
        'Public/Get-PsGadgetEspNowDevices.ps1',
        'Public/Get-PsGadgetFtdiEeprom.ps1',
        'Public/Install-PsGadgetMpyScript.ps1',
        'Public/Invoke-PsGadgetStepper.ps1',
        'Public/Invoke-PsGadgetI2CScan.ps1',
        'Public/Invoke-PsGadgetI2C.ps1',
        'Public/Get-FtdiDevice.ps1',
        'Public/Get-PsGadgetMpy.ps1',
        'Public/New-PsGadgetFtdi.ps1',
        'Public/Test-PsGadgetEnvironment.ps1',
        'Public/Set-PsGadgetConfig.ps1',
        'Public/Set-PsGadgetFt232rCbusMode.ps1',
        'Public/Set-PsGadgetFtdiEeprom.ps1',
        'Public/Set-PsGadgetFtdiMode.ps1',
        'Public/Set-PsGadgetGpio.ps1',
        'Public/Open-PsGadgetTrace.ps1',
        'lib/net48/FTD2XX_NET.dll',
        'lib/net48/FTD2XX_NET.xml',
        'lib/netstandard20/FTD2XX_NET.dll',
        'lib/netstandard20/FTD2XX_NET.xml',
        'lib/netstandard20/FTD2XX_NET.deps.json',
        'lib/native/FTD2XX.dll',
        'lib/README.md'
    )
    
    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('FTDI', 'Hardware', 'GPIO', 'UART', 'I2C', 'SPI', 'PsGadget',
                     'MicroPython', 'ESP32', 'ESP-NOW', 'IoT', 'FT232H', 'FT232R',
                     'SSD1306', 'OLED', 'Telemetry')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/MarkGzero/PsGadget'
            IconUri      = ''
            ReleaseNotes = 'v0.3.7: Removed 9 deprecated SSD1306/PCA9685 wrapper functions; Send-PsGadgetI2CWrite demoted to internal private helper. Invoke-PsGadgetI2C is now the sole I2C entry point. PsGadgetFtdi.GetDisplay/Display/ClearDisplay use class methods directly. v0.3.6: Invoke-PsGadgetStepper - unified stepper motor cmdlet for FT232R/FT232H via async bit-bang. Bulk USB write for jitter-free step timing. Calibrated StepsPerRevolution (28BYJ-48: ~4075.77 half-steps, NOT 4096). Angle-based moves via -Degrees. PsGadgetFtdi.Step() and .StepDegrees() shorthand methods. v0.3.5: SSD1306 OLED integrated into Invoke-PsGadgetI2C. v0.3.4: ESP-NOW wireless telemetry.'
        }
    }
}