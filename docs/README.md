# PSGadget Documentation

---

## Getting Started

| File | Purpose |
|------|---------|
| [wiki/Getting-Started.md](wiki/Getting-Started.md) | Installation and first steps on Windows, Linux, and macOS |
| [wiki/Hardware-Kit.md](wiki/Hardware-Kit.md) | Component list, sourcing guide, and chip capability quick reference |

---

## Reference

| File | Purpose |
|------|---------|
| [wiki/Function-Reference.md](wiki/Function-Reference.md) | All public cmdlets with parameters and examples |
| [wiki/Classes.md](wiki/Classes.md) | PsGadgetFtdi, PsGadgetSsd1306, PsGadgetMpy class API |
| [wiki/Configuration.md](wiki/Configuration.md) | `~/.psgadget/config.json` settings reference |
| [wiki/Logging.md](wiki/Logging.md) | Log file location, levels, and protocol trace guide |
| [REFERENCE/MPSSE_Reference.md](REFERENCE/MPSSE_Reference.md) | FTDI MPSSE command byte reference (AN_108 / DS_FT232H) |

---

## Architecture

| File | Purpose |
|------|---------|
| [wiki/Architecture.md](wiki/Architecture.md) | Four-layer design, backend selection, module load order, file map |
| [about_adafruit_ft232h.md](about_adafruit_ft232h.md) | FT232H hardware reference — pins, MPSSE engine, GPIO, EEPROM |

---

## Troubleshooting

| File | Purpose |
|------|---------|
| [wiki/Troubleshooting.md](wiki/Troubleshooting.md) | Full guide — VCP/D2XX driver, Linux ftdi_sio, FT232R CBUS, SSD1306, MicroPython |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Quick link to GitHub-hosted troubleshooting guide |

---

## Advanced / Internal

| File | Purpose |
|------|---------|
| [wiki/Daemon.md](wiki/Daemon.md) | Background device daemon design (planned feature, not yet implemented) |
| [about_PsGadgetConfig.md](about_PsGadgetConfig.md) | PowerShell help file — `Get-Help about_PsGadgetConfig` |
| [about_PsGadgetDaemon.md](about_PsGadgetDaemon.md) | PowerShell help file — daemon subsystem design reference |
