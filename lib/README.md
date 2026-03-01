# FTDI Library Dependencies

This directory contains the FTDI D2XX .NET wrapper assemblies required for PsGadget FTDI device communication.

## Directory Structure

```
lib/
+-- net48/              # .NET Framework 4.8 assemblies (PowerShell 5.1 / ISE)
|   +-- FTD2XX_NET.dll
|   +-- FTD2XX_NET.xml  # XML documentation
+-- netstandard20/      # .NET Standard 2.0 assemblies (PowerShell 7.0 - 7.3)
|   +-- FTD2XX_NET.dll
|   +-- FTD2XX_NET.xml  # XML documentation
|   +-- FTD2XX_NET.deps.json
+-- net8/               # .NET IoT assemblies (PowerShell 7.4+ / .NET 8+)
|   +-- System.Device.Gpio.dll              # GPIO / I2C / SPI abstractions
|   +-- Iot.Device.Bindings.dll             # FT232H driver + 400+ device bindings
|   +-- UnitsNet.dll                        # Physical units (required by Iot.Device.Bindings)
|   +-- Microsoft.Extensions.Logging.Abstractions.dll  # Logging interface
+-- ftdisharp/          # FtdiSharp (all PS versions, Windows only)
|   +-- FtdiSharp.dll   # High-level MPSSE I2C/SPI/GPIO wrapper; used by SSD1306 and I2C devices
+-- native/             # Native FTDI drivers (Windows)
    +-- FTD2XX.dll      # FTDI D2XX driver library
```

## Assembly Information

**FtdiSharp.dll** (v0.1.2, NuGet: FtdiSharp): High-level MPSSE I2C/SPI/GPIO wrapper
- Provides clean Ft232H I2C and SPI device abstractions used by the SSD1306 driver
- Install: `Install-Package FtdiSharp` or via `dotnet add package FtdiSharp`
- NuGet: https://www.nuget.org/packages/FtdiSharp/0.1.2

**FTD2XX_NET.dll** (v1.3.4): FTDI's official managed .NET wrapper for the D2XX driver
- Provides managed (.NET) access to FTDI USB devices
- Supports device enumeration, configuration, and I/O operations
- Required for Windows FTDI device communication
- Download: https://ftdichip.com/wp-content/uploads/2026/01/FTD2XX_NET_v1.3.4.zip
  - Extract `net48/FTD2XX_NET.dll` -> `lib/net48/`
  - Extract `netstandard20/FTD2XX_NET.dll` -> `lib/netstandard20/`

**System.Device.Gpio.dll** (v4.1.0, NuGet: System.Device.Gpio): Microsoft .NET IoT GPIO abstraction
- Provides `GpioController`, `I2cDevice`, `SpiDevice`, `PwmChannel` standard interfaces
- Platform-independent - works on Windows, Linux, macOS

**Iot.Device.Bindings.dll** (v4.1.0, NuGet: Iot.Device.Bindings): Microsoft .NET IoT device drivers
- Includes `Ft232HDevice` for FT232H / FT2232H / FT4232H GPIO + I2C + SPI via D2XX
- Includes 400+ pre-built device bindings (sensors, displays, ADCs, etc.)
- All bindings use the standard `System.Device.Gpio` interfaces -- any binding works with FT232H

**FTD2XX.dll**: Native FTDI D2XX driver library (installed with the CDM package)
- Low-level USB communication with FTDI devices
- Both FTD2XX_NET.dll and Iot.Device.Bindings.dll depend on this at runtime
- Installed system-wide by the FTDI CDM driver package (see Downloads)

## Version Requirements

- **PowerShell 5.1 / ISE**: Uses `net48/FTD2XX_NET.dll` (.NET Framework 4.8)
- **PowerShell 7.0 - 7.3**: Uses `netstandard20/FTD2XX_NET.dll` (.NET Standard 2.0)
- **PowerShell 7.4+ / .NET 8+**: Uses `net8/` IoT DLLs (primary) + `netstandard20/FTD2XX_NET.dll` (FT232R CBUS fallback, Windows only)

The correct path is selected automatically by `Initialize-FtdiAssembly.ps1` at module import.
No user configuration is needed -- all three environments produce an identical public API.

## Downloads

| Component | What it provides | Bundled? | Download |
|-----------|-----------------|----------|----------|
| FTD2XX_NET managed wrapper (v1.3.4) | `FTD2XX_NET.dll` for net48 and netstandard20 | Yes | https://ftdichip.com/wp-content/uploads/2026/01/FTD2XX_NET_v1.3.4.zip |
| FTDI CDM driver package | Native `FTD2XX.dll` + VCP drivers, installs system-wide | No (system driver) | https://ftdichip.com/drivers/d2xx-drivers/ |
| FtdiSharp (v0.1.2) | SSD1306 MPSSE I2C/SPI wrapper | Yes (ftdisharp/) | https://www.nuget.org/packages/FtdiSharp/0.1.2 |
| System.Device.Gpio (v4.1.0) | GPIO / I2C / SPI .NET abstractions | Yes (net8/) | https://www.nuget.org/packages/System.Device.Gpio/4.1.0 |
| Iot.Device.Bindings (v4.1.0) | FT232H driver + 400+ IoT device bindings | Yes (net8/) | https://www.nuget.org/packages/Iot.Device.Bindings/4.1.0 |
| UnitsNet (v5.75.0) | Physical units library (dep of Iot.Device.Bindings) | Yes (net8/) | https://www.nuget.org/packages/UnitsNet/5.75.0 |
| Microsoft.Extensions.Logging.Abstractions (v10.0.3) | Logging interface (dep of Iot.Device.Bindings) | Yes (net8/) | https://www.nuget.org/packages/Microsoft.Extensions.Logging.Abstractions/10.0.3 |

The CDM driver package must be installed once per Windows machine.
All DLL files are bundled in this `lib/` directory and require no manual installation.

## Security and Updates

NuGet-sourced DLLs (System.Device.Gpio, Iot.Device.Bindings, UnitsNet,
Microsoft.Extensions.Logging.Abstractions, FtdiSharp) are tracked in
`lib/nuget-deps.csproj` for automated auditing.

**Automated vulnerability scanning** runs weekly via GitHub Actions
(`.github/workflows/lib-audit.yml`). The workflow:
- Runs `dotnet list package --vulnerable --include-transitive` and fails the build on any CVE hit
- Runs `dotnet list package --outdated` and uploads an artifact report

**Manual audit and update** (run locally):
```powershell
# Vulnerability + outdated report only
pwsh ./Tools/Update-PsGadgetLibs.ps1 -Audit

# Check what would change (dry run)
pwsh ./Tools/Update-PsGadgetLibs.ps1

# Download latest NuGet versions and replace DLLs
pwsh ./Tools/Update-PsGadgetLibs.ps1 -Apply
```

**NON-NuGet DLLs (manual update only)**:

| File | Source | How to update |
|------|--------|---------------|
| `lib/native/FTD2XX.dll` | FTDI vendor zip | https://ftdichip.com/drivers/d2xx-drivers/ |
| `lib/net48/FTD2XX_NET.dll` | FTDI vendor zip | https://ftdichip.com/drivers/d2xx-drivers/ |
| `lib/netstandard20/FTD2XX_NET.dll` | FTDI vendor zip | same as above |

After updating any DLL, update the version comment in `lib/nuget-deps.csproj`
and bump `ModuleVersion` in `PSGadget.psd1`.

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