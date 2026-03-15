# PSGadget PowerShell Module

Control LEDs, drive an OLED screen, and talk to microcontrollers from PowerShell.

**PowerShell**: 5.1+  |  **Platforms**: Windows, Linux, macOS

---

## Quick Start

```powershell
Import-Module ./PSGadget.psd1
Test-PsGadgetEnvironment -Verbose
Get-PsGadgetFtdi
Set-PsGadgetGpio -Index 0 -Pins @(0) -State HIGH
```

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
