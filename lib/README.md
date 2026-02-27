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

**FTD2XX_NET.dll** (v1.3.4): FTDI's official managed .NET wrapper for the D2XX driver
- Provides managed (.NET) access to FTDI USB devices
- Supports device enumeration, configuration, and I/O operations
- Required for Windows FTDI device communication
- Download: https://ftdichip.com/wp-content/uploads/2026/01/FTD2XX_NET_v1.3.4.zip
  - Extract `net48/FTD2XX_NET.dll` -> `lib/net48/`
  - Extract `netstandard20/FTD2XX_NET.dll` -> `lib/netstandard20/`

**FTD2XX.dll**: Native FTDI D2XX driver library (installed with the CDM package)
- Low-level USB communication with FTDI devices
- FTD2XX_NET.dll depends on this native library at runtime
- Installed system-wide by the FTDI CDM driver package (see below)

## Version Requirements

- **PowerShell 5.1**: Uses net48/FTD2XX_NET.dll (.NET Framework 4.8)
- **PowerShell 7+**: Uses netstandard20/FTD2XX_NET.dll (.NET Standard 2.0)

## Downloads

| Component | What it provides | Download |
|-----------|-----------------|----------|
| FTD2XX_NET managed wrapper (v1.3.4) | `FTD2XX_NET.dll` for net48 and netstandard20 | https://ftdichip.com/wp-content/uploads/2026/01/FTD2XX_NET_v1.3.4.zip |
| FTDI CDM driver package | Native `FTD2XX.dll` + VCP drivers, installs system-wide | https://ftdichip.com/drivers/d2xx-drivers/ |

Both are required on Windows. The CDM package is installed once per machine.
The managed wrapper DLLs are bundled in this `lib/` directory.

## Licensing

These assemblies are provided by FTDI and are subject to FTDI's licensing terms.
They are redistributed here under the terms that allow inclusion with applications
that use FTDI hardware.

## Installation Notes

The PsGadget module automatically detects the PowerShell version and loads the 
appropriate assembly. No manual installation is required - simply import the 
PsGadget module and the FTDI functionality will be available.

If you encounter assembly loading issues:
1. Ensure FTDI drivers are installed on your system
2. Check that FTD2XX.dll is accessible (in PATH or same directory)
3. Verify your PowerShell execution policy allows loading assemblies