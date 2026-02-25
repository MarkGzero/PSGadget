@{
    # Module metadata
    RootModule = 'PSGadget.psm1'
    ModuleVersion = '0.1.0'
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
        'List-PsGadgetFtdi',
        'Connect-PsGadgetFtdi',
        'List-PsGadgetMpy',
        'Connect-PsGadgetMpy'
    )
    
    # No cmdlets, variables, or aliases exported
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    
    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('FTDI', 'MicroPython', 'Hardware', 'Gadget')
            LicenseUri = 'https://github.com/MarkGzero/PsGadget/blob/main/LICENSE'
            ProjectUri = 'https://github.com/MarkGzero/PsGadget'
            IconUri = ''
            ReleaseNotes = 'Initial release v0.1.0'
        }
    }
}