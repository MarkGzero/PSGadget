@{
    # Module metadata
    RootModule           = 'PSGadget.psm1'
    ModuleVersion        = '0.3.5'
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
        'List-PsGadgetFtdi',
        'Connect-PsGadgetFtdi',
        'List-PsGadgetMpy',
        'Connect-PsGadgetMpy',
        'Set-PsGadgetGpio',
        'Get-PsGadgetFtdiEeprom',
        'Set-PsGadgetFt232rCbusMode',
        'Set-PsGadgetFtdiEeprom',
        'Set-PsGadgetFtdiMode',
        'Get-PsGadgetConfig',
        'Set-PsGadgetConfig',
        'Connect-PsGadgetSsd1306',
        'Clear-PsGadgetSsd1306',
        'Write-PsGadgetSsd1306',
        'Set-PsGadgetSsd1306Cursor',
        'Install-PsGadgetMpyScript',
        'Get-PsGadgetEspNowDevices',
        'Send-PsGadgetI2CWrite',
        'Invoke-PsGadgetI2CScan',
        'Connect-PsGadgetPca9685',
        'Invoke-PsGadgetPca9685SetChannel',
        'Invoke-PsGadgetPca9685SetChannels',
        'Get-PsGadgetPca9685Channel',
        'Get-PsGadgetPca9685Frequency'
    )
    
    # No cmdlets, variables, or aliases exported
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @('Test-PsGadgetSetup')
    
    # Files included in this module
    FileList = @(
        'PSGadget.psm1',
        'Classes/PsGadgetLogger.ps1',
        'Classes/PsGadgetI2CDevice.ps1',
        'Classes/PsGadgetSsd1306.ps1',
        'Classes/PsGadgetFtdi.ps1',
        'Classes/PsGadgetMpy.ps1',
        'Classes/PsGadgetPca9685.ps1',
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
        'Public/Clear-PsGadgetSsd1306.ps1',
        'Public/Connect-PsGadgetFtdi.ps1',
        'Public/Connect-PsGadgetMpy.ps1',
        'Public/Connect-PsGadgetPca9685.ps1',
        'Public/Connect-PsGadgetSsd1306.ps1',
        'Public/Get-PsGadgetConfig.ps1',
        'Public/Get-PsGadgetEspNowDevices.ps1',
        'Public/Get-PsGadgetFtdiEeprom.ps1',
        'Public/Get-PsGadgetPca9685Channel.ps1',
        'Public/Get-PsGadgetPca9685Frequency.ps1',
        'Public/Install-PsGadgetMpyScript.ps1',
        'Public/Invoke-PsGadgetI2CScan.ps1',
        'Public/Invoke-PsGadgetPca9685SetChannel.ps1',
        'Public/Invoke-PsGadgetPca9685SetChannels.ps1',
        'Public/List-PsGadgetFtdi.ps1',
        'Public/List-PsGadgetMpy.ps1',
        'Public/New-PsGadgetFtdi.ps1',
        'Public/Test-PsGadgetEnvironment.ps1',
        'Public/Set-PsGadgetConfig.ps1',
        'Public/Set-PsGadgetFt232rCbusMode.ps1',
        'Public/Set-PsGadgetFtdiEeprom.ps1',
        'Public/Set-PsGadgetFtdiMode.ps1',
        'Public/Send-PsGadgetI2CWrite.ps1',
        'Public/Set-PsGadgetGpio.ps1',
        'Public/Set-PsGadgetSsd1306Cursor.ps1',
        'Public/Write-PsGadgetSsd1306.ps1',
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
                     'SSD1306', 'OLED', 'CTF', 'Telemetry')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/MarkGzero/PsGadget'
            IconUri      = ''
            ReleaseNotes = 'v0.3.4: ESP-NOW wireless telemetry support (Install-PsGadgetMpyScript, Get-PsGadgetEspNowDevices). ESP32-S3 receiver/transmitter scripts bundled. v0.3.x: SSD1306 OLED display, MicroPython mpremote backend, FT232R CBUS GPIO, FT232H MPSSE GPIO.'
        }
    }
}