# FTDI Library Dependencies

This directory contains the FTDI D2XX .NET wrapper assemblies required for PsGadget FTDI device communication.

## Directory Structure

```
lib/
├── net48/              # .NET Framework 4.8 assemblies (PowerShell 5.1)
│   ├── FTD2XX_NET.dll
│   └── FTD2XX_NET.xml  # XML documentation
├── netstandard20/      # .NET Standard 2.0 assemblies (PowerShell 7+)
│   ├── FTD2XX_NET.dll
│   ├── FTD2XX_NET.xml  # XML documentation
│   └── FTD2XX_NET.deps.json
└── native/             # Native FTDI drivers
    └── FTD2XX.dll      # FTDI D2XX driver library
```

## Assembly Information

**FTD2XX_NET.dll**: FTDI's official .NET wrapper for the D2XX driver
- Provides managed access to FTDI USB devices
- Supports device enumeration, configuration, and I/O operations
- Required for Windows FTDI device communication

**FTD2XX.dll**: Native FTDI D2XX driver library
- Low-level USB communication with FTDI devices
- FTD2XX_NET.dll depends on this native library
- Must be in system PATH or application directory

## Version Requirements

- **PowerShell 5.1**: Uses net48/FTD2XX_NET.dll (.NET Framework 4.8)
- **PowerShell 7+**: Uses netstandard20/FTD2XX_NET.dll (.NET Standard 2.0)

## Licensing

These assemblies are provided by FTDI and are subject to FTDI's licensing terms.
They are redistributed here under the terms that allow inclusion with applications
that use FTDI hardware.

For the latest versions and licensing information, visit:
https://ftdichip.com/drivers/d2xx-drivers/

## Installation Notes

The PsGadget module automatically detects the PowerShell version and loads the 
appropriate assembly. No manual installation is required - simply import the 
PsGadget module and the FTDI functionality will be available.

If you encounter assembly loading issues:
1. Ensure FTDI drivers are installed on your system
2. Check that FTD2XX.dll is accessible (in PATH or same directory)
3. Verify your PowerShell execution policy allows loading assemblies