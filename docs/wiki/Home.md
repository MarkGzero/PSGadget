# PSGadget Wiki

Welcome to the PSGadget reference wiki. These pages cover everything you need to
install the module, connect hardware, and use every exported function.

---

## Pages

### Setup and Orientation

| Page | Description |
|------|-------------|
| [Getting Started](Getting-Started.md) | Install prerequisites, load the module, verify your first device |
| [Configuration](Configuration.md) | `~/.psgadget/config.json` -- all keys, defaults, and effects |

### Reference

| Page | Description |
|------|-------------|
| [Function Reference](Function-Reference.md) | Every exported function: parameters, return types, examples |
| [Config Key Reference](Configuration.md) | Deep reference for every config key |
| [Daemon Reference](Daemon.md) | Background device daemons: named pipe IPC, file drop, systemd integration |

### Device Workflows

| Page | Description |
|------|-------------|
| [Workflow Reference](../../examples/psgadget_workflow.md) | End-to-end device workflows: FT232H, FT232R, SSD1306 OLED |
| [Example: Bicolor LED](../../examples/Example-BicolorLed.md) | FT232H bicolor LED wiring and control |
| [Example: FT232R Motor](../../examples/Example-Ft232rMotor.md) | FT232R CBUS driving a DC motor via transistor |
| [Example: SSD1306 Display](../../examples/Example-Ssd1306.md) | SSD1306 OLED text rendering, alignment, live clock |

---

## Supported Devices at a Glance

| Device | GPIO | Protocol | Notes |
|--------|------|----------|-------|
| FT232H | ACBUS0-7 (8 pins) | MPSSE | SPI, I2C, JTAG also available |
| FT232R / FT232RNL | CBUS0-3 (4 pins) | CBUS bit-bang | One-time EEPROM setup |
| SSD1306 OLED | via FT232H I2C | PsGadgetSsd1306 | 128x64, 8 pages |
| MicroPython boards | serial REPL | mpremote | Pico, ESP32, any MicroPython device |

---

## Navigation Tips

- **New to PSGadget?** Start at [Getting Started](Getting-Started.md).
- **Know what you want to call?** Go straight to the [Function Reference](Function-Reference.md).
- **Wiring a specific device?** The [Workflow Reference](../../examples/psgadget_workflow.md) has pin maps and step-by-step commands.
- **Adjusting behavior for your rig?** See [Configuration](Configuration.md).
