# PSGadget Persona Guide

PSGadget documentation is written for four types of readers. This page
explains who each persona is and where to find the content most useful to them.

---

## The four personas

### Nikola -- Beginner

**Background**: new to hardware, new to low-level programming. Has used
PowerShell to do basic scripting. Does not know what USB drivers are,
what GPIO means, or what I2C is.

**What Nikola needs**: every concept explained, every command justified,
plain language, no assumptions.

**Where to start**:
1. [INSTALL.md -- Beginner section](INSTALL.md#beginner-nikola)
2. [QUICKSTART.md -- Nikola walkthrough](QUICKSTART.md#nikola-new-to-everything)
3. [examples/beginner/](../examples/beginner/)

**Key concepts to understand first**:
- An FTDI chip is a small USB board that lets PowerShell talk to electronics.
  Pin 0 is a wire you can set HIGH (3.3 V) or LOW (0 V) from a script.
- The module runs without any hardware (stub mode) so you can explore before
  buying anything.
- `Test-PsGadgetEnvironment` tells you if everything is set up correctly and
  what to fix if it is not.

---

### Jordan -- Scripter

**Background**: comfortable with PowerShell -- knows modules, pipelines, objects,
`$ErrorActionPreference`, etc. Limited hardware knowledge. Does not know what
GPIO, I2C, or FTDI drivers are.

**What Jordan needs**: clear explanation of hardware concepts, no explanation
of PowerShell syntax. Output formats, pipeline behaviour, error handling.

**Where to start**:
1. [INSTALL.md -- Scripter section](INSTALL.md#scripter-jordan)
2. [QUICKSTART.md -- Jordan walkthrough](QUICKSTART.md#jordan-powershell-scripter)
3. [examples/scripter/](../examples/scripter/)
4. [docs/wiki/Function-Reference.md](wiki/Function-Reference.md)

**Key concepts to understand first**:
- FTDI devices are USB adapters (~$10) with GPIO pins. D2XX is the Windows
  driver that lets PSGadget talk to them directly (not through a COM port).
- `New-PsGadgetFtdi` returns a `PsGadgetFtdi` object. The OOP interface
  (`$dev.SetPin(0, 'HIGH')`) is cleaner than individual cmdlets for scripts.
- `Test-PsGadgetEnvironment` returns a `PSCustomObject` with `Status`,
  `Reason`, and `NextStep` -- scriptable, not just for humans.
- Pin 0 = ACBUS0 on FT232H, CBUS0 on FT232R. Voltage is 3.3 V.

---

### Izzy -- Engineer

**Background**: understands electronics -- GPIO, I2C, SPI, voltage levels,
pull-up resistors, datasheets. Familiar with microcontrollers. Less
familiar with Windows/Linux driver stacks, PowerShell module system,
or the D2XX API.

**What Izzy needs**: protocol detail, register maps, timing, pin-level
accuracy. Explanation of how the software layers interact with the hardware.

**Where to start**:
1. [ARCHITECTURE.md](ARCHITECTURE.md) -- layer breakdown, file map, design rules
2. [INSTALL.md -- Engineer section](INSTALL.md#engineer-izzy)
3. [QUICKSTART.md -- Izzy walkthrough](QUICKSTART.md#izzy-hardware-engineer)
4. [examples/engineer/](../examples/engineer/)
5. [PLATFORMS.md](PLATFORMS.md) -- D2XX vs IoT backend, native library details

**Key concepts to understand first**:
- PSGadget has four layers: Transport (USB open/close), Protocol (MPSSE byte
  sequences, I2C/GPIO), Device (chip logic, SSD1306 register maps), API (cmdlets).
- MPSSE clock: 60 MHz base (divide-by-5 disabled). Standard I2C 100 kHz uses
  divisor `0x14B`. Fast mode 400 kHz uses `0x4A`.
- GPIO uses read-modify-write: `Set-FtdiGpioPins` reads the current direction
  and value bytes before writing, preserving unrelated pins.
- I2C ACK is validated after every byte. NACK throws a terminating error.

---

### Scott -- Pro

**Background**: experienced with both PowerShell and hardware/electronics.
Reads tables and reference docs. Does not need step-by-step instructions.

**Where to start**:
1. [INSTALL.md -- Pro quick reference](INSTALL.md#pro-scott)
2. [QUICKSTART.md -- Scott quick reference](QUICKSTART.md#scott-quick-reference)
3. [examples/pro/](../examples/pro/)
4. [docs/wiki/Function-Reference.md](wiki/Function-Reference.md)
5. [ARCHITECTURE.md -- File map](ARCHITECTURE.md#file-map)

---

## Persona-tagged content

All example files in `examples/` include sections tagged for each persona:

```
> **Beginner (Nikola)**: ...
> **Scripter (Jordan)**: ...
> **Engineer (Izzy)**: ...
> **Pro (Scott)**: ...
```

Persona-specific example folders:

| Folder | Audience |
|--------|---------|
| [examples/beginner/](../examples/beginner/) | Nikola -- step by step, every concept explained |
| [examples/scripter/](../examples/scripter/) | Jordan -- PowerShell-first, hardware explained |
| [examples/engineer/](../examples/engineer/) | Izzy -- protocol detail, register-level |
| [examples/pro/](../examples/pro/) | Scott -- reference format, minimal prose |
