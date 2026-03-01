# PSGadget Installation Guide

Control FTDI USB adapters and MicroPython boards from PowerShell 5.1 or 7+
on Windows, Linux, and macOS.

---

## Pick your path

**By operating system**
- [Windows](#windows)
- [Linux](#linux)
- [macOS](#macos)

**By persona**
- [Beginner (Nikola) - step by step, no assumptions](#beginner-nikola)
- [Scripter (Jordan) - PowerShell-focused, quick setup](#scripter-jordan)
- [Engineer (Izzy) - what loads and why](#engineer-izzy)
- [Pro (Scott) - reference table](#pro-scott)

**By depth**
- [Just get it working (high-level)](#just-get-it-working)
- [What is actually loaded (low-level)](#what-is-actually-loaded)

**Need to buy parts first?**
- [Hardware Kit and Shopping List](HARDWARE_KIT.md)

---

## Just get it working

Three steps on any platform:

1. Install PSGadget (see your OS section below).
2. Run `Test-PsGadgetEnvironment` to confirm the environment is ready.
3. Run `List-PsGadgetFtdi` to see connected devices.

If hardware is not connected yet, the module runs in stub mode and returns
simulated data. That is normal and useful for exploring the API before you
have a device.

---

## Windows

### Step 1 - Install PSGadget

**Option A: PowerShell Gallery (recommended)**

```powershell
Install-Module PSGadget -Scope CurrentUser
```

If you are on a managed machine that blocks the Gallery, use Option B.

**Option B: ZIP from GitHub**

1. Download the latest release ZIP from:
   https://github.com/MarkGzero/PSGadget/releases
2. Extract to a folder, for example `C:\PSGadget`.
3. Import directly:

```powershell
Import-Module C:\PSGadget\PSGadget.psd1
```

> **Beginner (Nikola)**: Open the Start menu, type "PowerShell", right-click
> "Windows PowerShell" and choose "Run as administrator" for the driver step
> below. For everyday use you do not need admin.

> **Scripter (Jordan)**: `Install-Module` writes to
> `$env:USERPROFILE\Documents\PowerShell\Modules` when using `-Scope CurrentUser`.
> No admin rights required. Confirm with `Get-Module PSGadget -ListAvailable`.

### Step 2 - Install the FTDI D2XX driver (Windows only)

PSGadget uses the FTDI D2XX driver to talk to your USB adapter. Most Windows
machines already have it if you have ever plugged in an FTDI device, but if
`Test-PsGadgetEnvironment` reports the backend as "Stub", install it:

1. Go to https://ftdichip.com/drivers/d2xx-drivers/
2. Download the Windows setup executable.
3. Run the installer (requires admin).
4. Replug your FTDI device.

> **Engineer (Izzy)**: D2XX is FTDI's proprietary direct-access driver. It
> installs as a Windows kernel driver and exposes a user-mode DLL
> (`FTD2XX.DLL`). PSGadget loads the managed wrapper `FTD2XX_NET.dll` from
> its own `lib/` folder; the native `FTD2XX.DLL` must already be present in
> `system32` or the PATH -- that is what the FTDI installer puts there.
> On PS 7.4+ / .NET 8+, PSGadget prefers `Iot.Device.Bindings` from
> `lib/net8/` and loads `FTD2XX_NET.dll` only as a fallback for FT232R CBUS.

### Step 3 - Verify

```powershell
Import-Module PSGadget
Test-PsGadgetEnvironment -Verbose
```

Expected output on healthy Windows with a device connected:

```
PsGadget Setup Check
----------------------------------------------------
Platform  : Windows / PS 7.5 / .NET 9.0
Backend   : D2XX (FTD2XX_NET.dll)
Devices   : 1 device(s) found
Config    : [OK] C:\Users\you\.psgadget\config.json
----------------------------------------------------
  [0] FT232H     SN=BG01X3GX     GPIO=MPSSE
Status    : READY
```

If `Status` shows `Fail`, the `Reason` and `NextStep` fields tell you exactly
what is missing.

---

## Linux

### Step 1 - Install PSGadget

**Option A: PowerShell Gallery**

```powershell
Install-Module PSGadget -Scope CurrentUser
```

**Option B: Clone or download**

```bash
git clone https://github.com/MarkGzero/PSGadget.git
```

```powershell
Import-Module ./PSGadget/PSGadget.psd1
```

### Step 2 - Install the native FTDI D2XX library

The managed .NET DLLs included in PSGadget need the native `libftd2xx.so`
at runtime. This is not installed by default on Linux.

1. Download the ARM or x86 tarball from:
   https://ftdichip.com/drivers/d2xx-drivers/
   (choose "Linux" -> pick your architecture)

2. Extract and install:

```bash
tar xzf libftd2xx-linux-x86_64-*.tar.gz
sudo cp release/build/libftd2xx.so.* /usr/local/lib/
sudo ln -sf /usr/local/lib/libftd2xx.so.* /usr/local/lib/libftd2xx.so
sudo ldconfig
```

3. The `ftdi_sio` kernel module claims VCP-mode FTDI devices and blocks D2XX
   access. Unload it (temporary, resets on reboot):

```bash
sudo rmmod ftdi_sio
```

   To make this permanent:

```bash
echo "blacklist ftdi_sio" | sudo tee /etc/modprobe.d/ftdi-psgadget.conf
sudo update-initramfs -u
```

4. Add your user to the `plugdev` group so you can access USB devices
   without root:

```bash
sudo usermod -aG plugdev $USER
# log out and back in for this to take effect
```

> **Beginner (Nikola)**: The commands above that start with `sudo` require
> your password and need administrator-equivalent access. Open a terminal
> (Ctrl+Alt+T on most Ubuntu/Debian systems) and paste each line one at a
> time. After the `usermod` command, log out of your desktop session and log
> back in before continuing.

> **Engineer (Izzy)**: FTDI releases an ARM hard-float build
> (`libftd2xx-arm-v7-hf`) for Raspberry Pi and similar boards. If you are on
> an aarch64 machine (Pi 4/5, Jetson) use the `aarch64` build instead. The
> managed .NET IoT layer invokes the native library via P/Invoke; the `.so`
> must be resolvable by `ldconfig` (checked at `dlopen` time, not load time).

### Step 3 - Verify

```powershell
Import-Module ./PSGadget.psd1
Test-PsGadgetEnvironment -Verbose
```

Expected output on healthy Linux with a device connected:

```
PsGadget Setup Check
----------------------------------------------------
Platform  : Linux/Unix / PS 7.5 / .NET 9.0
Backend   : IoT (Iot.Device.Bindings / .NET 8+)
Native lib: [OK] /usr/local/lib/libftd2xx.so
Devices   : 1 device(s) found
Config    : [OK] /home/you/.psgadget/config.json
----------------------------------------------------
  [0] FT232H     SN=BG01X3GX     GPIO=MPSSE
Status    : READY
```

---

## macOS

### Step 1 - Install PSGadget

Same as Linux - use PowerShell Gallery or clone from GitHub.

### Step 2 - Install the native FTDI D2XX library

1. Download the macOS `.dmg` or tarball from:
   https://ftdichip.com/drivers/d2xx-drivers/

2. Follow the FTDI readme inside the package to copy `libftd2xx.dylib` to
   `/usr/local/lib/`.

3. macOS ships with its own `FTDIUSBSerialDriver.kext`. Unload it to allow
   D2XX access:

```bash
sudo kextunload -bundle-id com.apple.driver.AppleUSBFTDI
sudo kextunload -bundle-id com.FTDI.driver.FTDIUSBSerialDriver
```

   To make this apply at every boot, use `kextstat` to confirm the kext name
   and add a launchd rule, or disable SIP-protected kexts as appropriate for
   your macOS version.

4. Gatekeeper will likely block the `.dylib` on first use. Run:

```bash
sudo xattr -rd com.apple.quarantine /usr/local/lib/libftd2xx.dylib
```

> **Beginner (Nikola)**: macOS makes hardware driver setup more involved than
> Windows. If you just want to explore the module without hardware, skip this
> step entirely -- PSGadget runs in stub mode and you can try all the cmdlets
> with simulated data. Come back to this section when your adapter arrives.

> **Engineer (Izzy)**: On Apple Silicon (M1/M2/M3) you need the ARM64 build
> of libftd2xx. FTDI's macOS driver page lists both x86_64 and arm64 builds
> starting from D2XX 1.4.27. Confirm architecture with `file libftd2xx.dylib`
> before copying. Rosetta will not bridge native P/Invoke calls for this.

### Step 3 - Verify

Same `Test-PsGadgetEnvironment -Verbose` as the Linux section above.

---

## What is actually loaded

This section is for platform details. Casual users can skip it.

PSGadget ships its own managed .NET assemblies in `lib/`. The selection logic
in `Private/Initialize-FtdiAssembly.ps1` runs at module import:

| Runtime | DLL loaded | Notes |
|---------|-----------|-------|
| PS 5.1 / .NET Framework 4.8 | `lib/net48/FTD2XX_NET.dll` | Windows only |
| PS 7.0-7.3 / .NET 6-7 | `lib/netstandard20/FTD2XX_NET.dll` | All platforms |
| PS 7.4+ / .NET 8+ | `lib/net8/Iot.Device.Bindings.dll` (primary) + `lib/netstandard20/FTD2XX_NET.dll` (FT232R CBUS fallback, Windows only) | All platforms |

On Linux and macOS, `libftd2xx.so` / `libftd2xx.dylib` must be installed
separately (see above). The managed DLLs are bundled; the native library is
NOT bundled because it is platform-architecture-specific.

`$script:IotBackendAvailable`, `$script:D2xxLoaded`, and
`$script:FtdiSharpAvailable` are the module-scope flags set after loading.
`Test-PsGadgetEnvironment` reads these flags to report backend status.

---

## Persona guides

### Beginner (Nikola)

You do not need to understand USB drivers, GPIO, or I2C to get started.

1. Install PowerShell 7 (free, from https://aka.ms/powershell).
2. Follow the Windows or Linux steps above to install PSGadget.
3. Plug in your FTDI adapter (small USB board with labeled pins).
4. Open PowerShell and type:

```powershell
Import-Module PSGadget
Test-PsGadgetEnvironment
```

5. If `Status` says `READY`, try:

```powershell
List-PsGadgetFtdi | Format-Table
```

You will see your device listed with its serial number and type.

6. If anything says `Fail`, read the `NextStep` output -- it tells you exactly
   what command to run next.

You cannot break anything by importing the module or running `List-PsGadgetFtdi`.
The worst that happens is no device is found and the module runs in stub mode.

---

### Scripter (Jordan)

You know PowerShell. Here is the direct path:

```powershell
# Install
Install-Module PSGadget -Scope CurrentUser

# Verify
Import-Module PSGadget
$env = Test-PsGadgetEnvironment
if ($env.Status -ne 'OK') { Write-Warning $env.NextStep }

# Enumerate and connect
$devices = List-PsGadgetFtdi
$dev = New-PsGadgetFtdi -SerialNumber $devices[0].SerialNumber

# Use
$dev.SetPin(0, 'HIGH')
$dev.Close()
```

The return value of `Test-PsGadgetEnvironment` has `Status`, `Reason`,
`NextStep`, `Backend`, `Devices`, and `IsReady` -- pipe it or check it
in scripts without parsing console output.

---

### Engineer (Izzy)

PSGadget uses a layered architecture:

- **Transport layer**: D2XX or .NET IoT opens the USB device and sends raw
  bytes (`lib/net48/`, `lib/netstandard20/`, `lib/net8/`).
- **Protocol layer**: `Private/Ftdi.Mpsse.ps1` builds MPSSE command sequences
  for I2C/SPI/JTAG and manages GPIO direction and state.
- **Device layer**: `Classes/PsGadgetSsd1306.ps1` knows SSD1306 register maps;
  `Classes/PsGadgetFtdi.ps1` wraps the transport with connect/close/mode logic.
- **API layer**: `Public/*.ps1` exposes simple cmdlets that call into the classes.

MPSSE clock divider: `Set-FtdiMpsseClockDivisor` uses the 60 MHz base clock
after disabling the divide-by-5. Standard 100 kHz I2C uses divisor 0x14B.

GPIO state is managed with read-modify-write via `Get-FtdiGpioPins` before
each `Set-FtdiGpioPins` so unrelated pins are not clobbered.

---

### Pro (Scott)

Quick reference -- everything in one place.

| Task | Command |
|------|---------|
| Install from Gallery | `Install-Module PSGadget -Scope CurrentUser` |
| Install from local path | `Import-Module ./PSGadget.psd1` |
| Verify environment | `Test-PsGadgetEnvironment [-Verbose]` |
| List devices | `List-PsGadgetFtdi` |
| Connect by SN | `New-PsGadgetFtdi -SerialNumber 'BG01X3GX'` |
| Connect by index | `New-PsGadgetFtdi -Index 0` |
| GPIO single pin | `$dev.SetPin(0, 'HIGH')` |
| GPIO multi pin | `$dev.SetPins(@(0,1), 'HIGH')` |
| Pulse pin | `$dev.PulsePin(0, 'HIGH', 500)` |
| SSD1306 display | `Connect-PsGadgetSsd1306 -FtdiDevice $ftdi` |
| Write to OLED | `Write-PsGadgetSsd1306 -Display $d -Text 'Hi' -Page 0` |
| MicroPython REPL | `Connect-PsGadgetMpy -SerialPort '/dev/ttyUSB0'` |
| Get config | `Get-PsGadgetConfig` |
| Set config | `Set-PsGadgetConfig -Key LogLevel -Value Debug` |

Platform native library locations expected by PSGadget:

| OS | Path |
|----|------|
| Windows | `C:\Windows\System32\FTD2XX.DLL` (installed by FTDI setup EXE) |
| Linux x86-64 | `/usr/local/lib/libftd2xx.so` or `/usr/lib/x86_64-linux-gnu/libftd2xx.so` |
| Linux ARM64 | `/usr/lib/aarch64-linux-gnu/libftd2xx.so` |
| Linux ARM HF | `/usr/lib/arm-linux-gnueabihf/libftd2xx.so` |
| macOS | `/usr/local/lib/libftd2xx.dylib` |

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common errors and fixes.

Run `Test-PsGadgetEnvironment -Verbose` first -- it covers 90% of setup issues
and tells you exactly what command to run next.
