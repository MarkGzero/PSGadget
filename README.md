# PSGadget PowerShell Module

PowerShell module for FTDI hardware control and MicroPython orchestration.

## Features

- **FTDI-First Design**: Direct hardware control via D2XX drivers
- **MicroPython Integration**: Built-in orchestration via `mpremote` 
- **Cross-Platform**: PowerShell 5.1+ compatible (Windows, Linux, macOS)
- **Automatic Logging**: Session tracking with timestamped logs
- **Clean Architecture**: Separation of Public/Private/Classes
- **Stub-First Development**: Safe hardware integration patterns

## Quick Start

```powershell
# Load the module
Import-Module ./PsGadget.psd1

# List available FTDI devices
List-PsGadgetFtdi | Format-Table

# Connect to an FTDI device
$ftdi = Connect-PsGadgetFtdi -Index 0
$ftdi.Open()

# List available serial ports for MicroPython
List-PsGadgetMpy

# Connect to a MicroPython device
$mpy = Connect-PsGadgetMpy -SerialPort "/dev/ttyUSB0"
$info = $mpy.GetInfo()
```

## Architecture

```
PsGadget/
├── PsGadget.psd1              # Module manifest
├── PsGadget.psm1              # Module loader
├── Public/                    # Exported functions
├── Classes/                   # PowerShell classes  
├── Private/                   # Internal functions
└── Tests/                     # Pester tests
```

## Development

```bash
# Load module for development
pwsh -c "Import-Module ./PsGadget.psd1 -Force"

# Run tests
pwsh -c "Import-Module Pester; Invoke-Pester ./Tests/"
```

## Environment

The module automatically creates `~/.psgadget/logs/` for session logging.

## License

See [LICENSE](LICENSE) for details.

## Contributing

See [.github/copilot-instructions.md](.github/copilot-instructions.md) for AI agent guidelines and development patterns.