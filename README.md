# PSGadget PowerShell Module

Control LEDs, drive an OLED screen, and talk to microcontrollers from PowerShell.

**PowerShell**: 5.1+  |  **Platforms**: Windows, Linux, macOS  |  **[PSGallery](https://www.powershellgallery.com/packages/PSGadget)**

---

## Install

**From PSGallery (recommended for most users):**

```powershell
Install-Module PSGadget
```

Or pin to a specific version:

```powershell
Install-Module PSGadget -RequiredVersion 0.3.7
```

**From source (latest development build):**

```powershell
git clone https://github.com/MarkGzero/PSGadget.git
Import-Module ./PSGadget/PSGadget.psd1
```

PSGallery releases lag source by one version at most. Use the source path
if you need a fix that has not been published yet, or to contribute changes.

---

## Quick Start

```powershell
Import-Module PSGadget

# Always run this first -- it tells you if everything is ready
# and prints a NextStep hint if anything is wrong
Test-PsGadgetEnvironment -Verbose

# List connected FTDI devices
Get-FTDevice

# Set ACBUS0 HIGH on device at index 0 (FT232H)
# Pin numbers map to ACBUS0-7 on FT232H, CBUS0-3 on FT232R
Set-PsGadgetGpio -Index 0 -Pins @(0) -State HIGH
```

If `Test-PsGadgetEnvironment` reports `Status: Fail`, read the `NextStep`
field -- it gives you the exact command to run to fix the problem.
See [Troubleshooting](docs/wiki/Troubleshooting.md) for a full symptom index.

---

## Documentation

| Page | Description |
|------|-------------|
| [Getting Started](docs/wiki/Getting-Started.md) | Install, connect your first device |
| [Hardware Kit](docs/wiki/Hardware-Kit.md) | Shopping list for examples |
| [Architecture](docs/wiki/Architecture.md) | Internal layering and maintenance |
| [Troubleshooting](docs/wiki/Troubleshooting.md) | Symptom index and fixes |
| [Configuration](docs/wiki/Configuration.md) | `~/.psgadget/config.json` keys |
| [Function Reference](docs/wiki/Function-Reference.md) | All exported cmdlets |
| [Daemon Reference](docs/wiki/Daemon.md) | Background daemon IPC |
| [Classes Reference](docs/wiki/Classes.md) | PsGadgetFtdi, Ssd1306, Mpy, Logger |
