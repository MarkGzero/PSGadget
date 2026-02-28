@{
    # Module metadata
    RootModule = 'PSGadget.psm1'
    ModuleVersion = '0.3.3'
    GUID = 'a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6'
    
    # PowerShell version requirements
    PowerShellVersion = '5.1'
    
    # Author information
    Author = 'PsGadget Team'
    CompanyName = 'PsGadget'
    Copyright = '(c) 2026 PsGadget Team. All rights reserved.'
    
    # Description
    Description = 'Production-grade PowerShell module for FTDI hardware control and MicroPython orchestration'
    
    # Exported functions - explicitly declared, no wildcards
    FunctionsToExport = @(
        'New-PsGadgetFtdi',
        'Test-PsGadgetSetup',
        'List-PsGadgetFtdi',
        'Connect-PsGadgetFtdi',
        'List-PsGadgetMpy',
        'Connect-PsGadgetMpy',
        'Set-PsGadgetGpio',
        'Get-PsGadgetFtdiEeprom',
        'Set-PsGadgetFt232rCbusMode',
        'Set-PsGadgetFtdiMode',
        'Get-PsGadgetConfig',
        'Set-PsGadgetConfig',
        'Connect-PsGadgetSsd1306',
        'Clear-PsGadgetSsd1306',
        'Write-PsGadgetSsd1306',
        'Set-PsGadgetSsd1306Cursor'
    )
    
    # No cmdlets, variables, or aliases exported
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    
    # Files included in this module
    FileList = @(
        'PSGadget.psm1',
        'Classes/PsGadgetLogger.ps1',
        'Classes/PsGadgetSsd1306.ps1',
        'Classes/PsGadgetFtdi.ps1', 
        'Classes/PsGadgetMpy.ps1',
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
        'Public/Connect-PsGadgetSsd1306.ps1',
        'Public/Get-PsGadgetConfig.ps1',
        'Public/Get-PsGadgetFtdiEeprom.ps1',
        'Public/List-PsGadgetFtdi.ps1',
        'Public/List-PsGadgetMpy.ps1',
        'Public/New-PsGadgetFtdi.ps1',
        'Public/Test-PsGadgetSetup.ps1',
        'Public/Set-PsGadgetConfig.ps1',
        'Public/Set-PsGadgetFt232rCbusMode.ps1',
        'Public/Set-PsGadgetFtdiMode.ps1',
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
            Tags = @('FTDI', 'MicroPython', 'Hardware', 'Gadget')
            LicenseUri = 'https://github.com/MarkGzero/PsGadget/blob/main/LICENSE'
            ProjectUri = 'https://github.com/MarkGzero/PsGadget'
            IconUri = ''
            ReleaseNotes = 'v0.3.3: New Test-PsGadgetSetup diagnostic command. Verbose hints in List-PsGadgetFtdi show ready-to-run connect commands per device.'
        }
    }
}