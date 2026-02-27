# PSGadget PowerShell Module

PowerShell module for FTDI hardware control and MicroPython orchestration.  
Supports direct GPIO, EEPROM programming, SSD1306 OLED output, and MicroPython
scripting -- all from a standard PowerShell session.

**Version**: 0.3.2  |  **PowerShell**: 5.1+  |  **Platforms**: Windows, Linux, macOS

---

## Documentation

| Page | Contents |
|------|----------|
| [Getting Started](docs/wiki/Getting-Started.md) | Prerequisites, installation, first device connection |
| [Function Reference](docs/wiki/Function-Reference.md) | Every exported function with parameters and examples |
| [Configuration](docs/wiki/Configuration.md) | User config file, keys, and defaults |
| [Workflow Reference](examples/psgadget_workflow.md) | Device-by-device workflows: FT232H, FT232R, SSD1306 |
| [Config Detail](docs/about_PsGadgetConfig.md) | Full `config.json` key reference |

---

## Supported Hardware

| Device | GPIO pins | Mechanism | Notes |
|--------|-----------|-----------|-------|
| FT232H | ACBUS0-7 (8 pins) | MPSSE | SPI / I2C / JTAG also available |
| FT232R / FT232RNL | CBUS0-3 (4 pins) | CBUS bit-bang | One-time EEPROM setup required |
| SSD1306 OLED | via FT232H I2C | PsGadgetSsd1306 | 128x64, 8 pages, font rendering |
| MicroPython boards | via serial REPL | mpremote | Pico, ESP32, any MicroPython device |

---

## Quick Start

```powershell
# 1. Import the module
Import-Module ./PSGadget.psd1

# 2. List connected FTDI devices
List-PsGadgetFtdi | Format-Table

# 3a. FT232H - GPIO immediately available on ACBUS0-7
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0, 1) -State HIGH

# 3b. FT232R - program EEPROM once (then replug), then use GPIO
Set-PsGadgetFt232rCbusMode -Index 0          # one-time per device
# (replug USB cable, then:)
Set-PsGadgetGpio -DeviceIndex 0 -Pins @(0) -State HIGH

# 4. SSD1306 OLED over FT232H I2C
$ftdi    = Connect-PsGadgetFtdi -Index 0
$display = Connect-PsGadgetSsd1306 -FtdiDevice $ftdi
Write-PsGadgetSsd1306 -Display $display -Text "Hello World" -Page 0
$ftdi.Close()

# 5. MicroPython REPL
$mpy = Connect-PsGadgetMpy -SerialPort "/dev/ttyUSB0"
$mpy.Invoke("print('hello from MicroPython')")
```

---

## OOP Interface (recommended for scripts)

`New-PsGadgetFtdi` returns a `PsGadgetFtdi` object whose methods own the
connection lifecycle. This is the cleanest pattern for multi-step scripts.

```powershell
$dev = New-PsGadgetFtdi -SerialNumber "BG01X3GX"
$dev.Connect()

$dev.SetPin(0, "HIGH")           # CBUS0 / ACBUS0 HIGH
$dev.SetPins(@(0, 1), "HIGH")    # multiple pins at once
$dev.PulsePin(0, "HIGH", 500)    # pulse HIGH for 500 ms

$dev.Close()
```

---

## Exported Functions

| Function | Description |
|----------|-------------|
| `New-PsGadgetFtdi` | Create a `PsGadgetFtdi` object (-SerialNumber / -Index / -LocationId) |
| `List-PsGadgetFtdi` | Enumerate all connected FTDI devices |
| `Connect-PsGadgetFtdi` | Open a raw device connection |
| `Get-PsGadgetFtdiEeprom` | Read EEPROM contents (FT232R CBUS inspection) |
| `Set-PsGadgetFt232rCbusMode` | Program FT232R CBUS pins to GPIO mode |
| `Set-PsGadgetFtdiMode` | Set raw FTDI bit-bang or MPSSE mode |
| `Set-PsGadgetGpio` | Set GPIO pin HIGH or LOW (-DeviceIndex / -SerialNumber / -Connection) |
| `Connect-PsGadgetSsd1306` | Initialize SSD1306 OLED over FTDI I2C |
| `Clear-PsGadgetSsd1306` | Clear full display or single page |
| `Write-PsGadgetSsd1306` | Write text with alignment and font size options |
| `Set-PsGadgetSsd1306Cursor` | Set raw column/page cursor position |
| `List-PsGadgetMpy` | Enumerate available MicroPython serial ports |
| `Connect-PsGadgetMpy` | Open a MicroPython REPL connection |
| `Get-PsGadgetConfig` | Read current user configuration |
| `Set-PsGadgetConfig` | Update and persist a configuration value |

See [Function Reference](docs/wiki/Function-Reference.md) for full parameter tables.

---

## Configuration

User preferences live in `~/.psgadget/config.json`, created automatically on
first import. Change settings with `Set-PsGadgetConfig`:

```powershell
Set-PsGadgetConfig -Key ftdi.highDriveIOs  -Value $true   # 8 mA drive strength
Set-PsGadgetConfig -Key logging.level      -Value DEBUG
Set-PsGadgetConfig -Key logging.retainDays -Value 7

Get-PsGadgetConfig          # view full config
Get-PsGadgetConfig -Section ftdi
```

See [Configuration](docs/wiki/Configuration.md) for all keys and their effects.

---

## Architecture

```
PSGadget/
|-- PSGadget.psd1              # Module manifest (version, exports)
|-- PSGadget.psm1              # Module loader (strict load order)
|-- Public/                    # Exported functions (one per file)
|-- Private/                   # Internal backends (platform-specific)
|-- Classes/                   # PsGadgetFtdi, PsGadgetMpy, PsGadgetSsd1306, PsGadgetLogger
|-- docs/                      # Reference documentation
|-- examples/                  # Multi-persona walkthrough guides
|-- Tests/                     # Pester tests
|-- lib/                       # FTD2XX_NET.dll (net48 and netstandard20)
```

**Load order** (enforced by PSGadget.psm1):
1. Classes in dependency order: Logger -> Ftdi -> Mpy -> Ssd1306
2. All Private functions
3. All Public functions
4. FTDI assembly initialization (`lib/`)
5. Environment setup (`~/.psgadget/`)

---

## Development

```bash
# Load for development
pwsh -c "Import-Module ./PSGadget.psd1 -Force"

# Run Pester test suite
pwsh -c "Import-Module Pester; Invoke-Pester ./Tests/PsGadget.Tests.ps1 -Output Detailed"

# Smoke test
pwsh -c "Import-Module ./PSGadget.psd1; List-PsGadgetFtdi | Format-Table"
```

The module runs in **stub mode** on Linux/macOS (no FTDI D2XX assembly). All
functions are importable and testable; hardware calls return stub data or throw
`NotImplementedException`.

---

## Requirements

- PowerShell 5.1 or 7+
- Windows: FTDI CDM driver package (VCP + D2XX)
- Linux/macOS: stub mode only (no D2XX driver)
- MicroPython functions: `mpremote` on PATH (`pip install mpremote`)

---

## Contributing

See [.github/copilot-instructions.md](.github/copilot-instructions.md) for AI
agent guidelines and development patterns.