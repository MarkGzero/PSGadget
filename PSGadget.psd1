# Module manifest for PSGadget

@{
    # Script module or binary module file associated with this manifest.
    RootModule           = 'PsGadget.psm1'
    ModuleVersion        = '0.0.3'
    CompatiblePSEditions = @('Desktop', 'Core')
    PowerShellVersion    = '5.1'

    # ID used to uniquely identify this module
    GUID                 = '72440f23-d3c6-4249-83eb-9affa6df882b'

    # Author of this module
    Author               = 'Mark Go'
    CompanyName          = 'Mark Go'

    # Description of the functionality provided by this module
    Description          = 'PsGadget hardware + PowerShell -- (Under Development)'

    FunctionsToExport    = @('Get-PsGadgetInfo')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData          = @{
        PSData = @{
            Tags         = @('FTDI', 'Hardware', 'GPIO', 'UART', 'I2C', 'PsGadget')
            ProjectUri   = 'https://github.com/MarkGzero/PsGadget'
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ReleaseNotes = 'v0.0.3: Fixed project URI.'
        }
    }
}