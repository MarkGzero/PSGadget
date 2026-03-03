# PSGadget Platform Guide

This document covers platform-specific requirements, differences, and known
limitations for Windows, Linux, and macOS.

---

## Table of Contents

- [Pick your platform](#pick-your-platform)
- [Windows](#windows)
  - [Supported configurations](#supported-configurations)
  - [Required components](#required-components)
  - [Notes](#notes)
- [Linux](#linux)
  - [Supported configurations](#supported-configurations-1)
  - [Required components](#required-components-1)
  - [Architecture builds](#architecture-builds)
  - [Kernel module conflict](#kernel-module-conflict)
  - [USB permissions](#usb-permissions)
  - [MicroPython serial ports](#micropython-serial-ports)
  - [WSL (Windows Subsystem for Linux)](#wsl-windows-subsystem-for-linux)
  - [Notes](#notes-1)
- [macOS](#macos)
  - [Supported configurations](#supported-configurations-2)
  - [Required components](#required-components-2)
  - [Kernel extension conflict](#kernel-extension-conflict)
  - [Gatekeeper quarantine](#gatekeeper-quarantine)
  - [Apple Silicon (M1/M2/M3)](#apple-silicon-m1m2m3)
  - [Notes](#notes-2)
- [Platform comparison](#platform-comparison)
- [Detecting the platform in scripts](#detecting-the-platform-in-scripts)

---

## Pick your platform

- [Windows](#windows)
- [Linux](#linux)
- [macOS](#macos)
- [Platform comparison table](#platform-comparison)

---

## Windows

### Supported configurations

| PowerShell | .NET | Backend | Status |
|-----------|------|---------|--------|
| 5.1 | 4.8 (Framework) | FTD2XX_NET net48 | Supported |
| 7.0-7.3 | 6 or 7 | FTD2XX_NET netstandard20 | Supported |
| 7.4+ | 8+ | Iot.Device.Bindings (primary) + FTD2XX_NET (FT232R fallback) | Supported |

### Required components

- **FTDI D2XX driver**: installs `FTD2XX.DLL` to `System32`.
  Download from https://ftdichip.com/drivers/d2xx-drivers/
  This is installed by the FTDI CDM Windows setup executable.
- **Managed wrapper**: `lib/net48/FTD2XX_NET.dll` or `lib/netstandard20/FTD2XX_NET.dll`
  bundled with PSGadget -- no separate install needed.
- **IoT DLLs** (PS 7.4+): `lib/net8/` bundled with PSGadget.

### Notes

- No USB permissions or group membership needed; Windows handles this through
  the driver.
- VCP (virtual COM port) driver and D2XX driver cannot be active at the same
  time for the same device. If the device appears as `COMx`, the VCP driver is
  loaded. Use Device Manager to reinstall with the D2XX driver.
- FT232R CBUS requires a one-time EEPROM programming step regardless of platform.
  See [QUICKSTART.md -- FT232R](QUICKSTART.md#ft232r).

---

## Linux

### Supported configurations

| PowerShell | .NET | Backend | Status |
|-----------|------|---------|--------|
| 7.0-7.3 | 6 or 7 | FTD2XX_NET netstandard20 | Supported |
| 7.4+ | 8+ | Iot.Device.Bindings + native libftd2xx.so | Supported |
| 5.1 | -- | Not available on Linux | Not supported |

### Required components

- **libftd2xx.so**: native FTDI D2XX shared library. Must be installed to
  a path that `ldconfig` resolves (e.g. `/usr/local/lib/`).
  Download from https://ftdichip.com/drivers/d2xx-drivers/
- **Managed wrapper**: bundled with PSGadget.

### Architecture builds

| Architecture | File to download | Install path |
|-------------|-----------------|-------------|
| x86-64 (PC/server) | `libftd2xx-linux-x86_64-*.tar.gz` | `/usr/local/lib/` |
| ARM64 (Pi 4/5, Jetson) | `libftd2xx-linux-aarch64-*.tar.gz` | `/usr/local/lib/` |
| ARM hard-float (Pi 2/3) | `libftd2xx-linux-arm-v7-hf-*.tar.gz` | `/usr/local/lib/` |

### Kernel module conflict

The `ftdi_sio` kernel module provides VCP access to FTDI devices. D2XX and
`ftdi_sio` cannot both own the device. Unload `ftdi_sio` before using D2XX:

```bash
sudo rmmod ftdi_sio
```

To disable permanently:

```bash
echo "blacklist ftdi_sio" | sudo tee /etc/modprobe.d/ftdi-psgadget.conf
sudo update-initramfs -u
```

### USB permissions

```bash
# Add user to plugdev group (log out and back in after this)
sudo usermod -aG plugdev $USER

# Add udev rule for FTDI devices (0403 = FTDI vendor ID)
# MODE="0664" gives owner+group read/write; plugdev group owns the node.
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", MODE="0664", GROUP="plugdev"' \
  | sudo tee /etc/udev/rules.d/99-ftdi-d2xx.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
# Replug (or usbipd detach+attach on WSL) to apply to the current device.
```

Log out and back in after `usermod` for the group change to take effect.

> **WSL note**: `udevadm trigger` does not retroactively fix permissions on
> devices already attached via usbipd. Run `sudo chown root:plugdev` and
> `sudo chmod 0664` on the `/dev/bus/usb/BUS/DEV` node for the current
> session. Future attach events will pick up the udev rule automatically.

### MicroPython serial ports

MicroPython boards appear as `/dev/ttyUSB0` (CP210x/FTDI) or `/dev/ttyACM0`
(CDC ACM / Pi Pico). Add your user to the `dialout` group:

```bash
sudo usermod -aG dialout $USER
```

### WSL (Windows Subsystem for Linux)

WSL requires an extra step when attaching a USB device. Use
[usbipd-win](https://github.com/dorssel/usbipd-win) to bind and attach the
device:

```powershell
# In Windows PowerShell (not WSL)
usbipd list
usbipd bind --busid <busid>        # one-time
usbipd attach --wsl --busid <busid>
```

After attaching, `udevadm trigger` inside WSL does not retroactively apply
`MODE`/`GROUP` udev rules to already-attached devices. Fix permissions for
the current session:

```bash
sudo chown root:plugdev /dev/bus/usb/001/<devnum>
sudo chmod 0664 /dev/bus/usb/001/<devnum>
```

The udev rule in the USB permissions section above covers future plug events
automatically. Detach/reattach via usbipd will also trigger the rule.

### Notes

- PS 5.1 is not available on Linux. Minimum is PS 7.0.
- FT232R CBUS GPIO on Linux is fully supported when `libftd2xx.so` is
  installed. GPIO is driven via native P/Invoke (`FT_Open` / `FT_SetBitMode`)
  using the P/Invoke declarations in `Private/Ftdi.PInvoke.ps1`.
  EEPROM programming (`Set-PsGadgetFt232rCbusMode`) is also supported on
  Linux via the same native path.
- FT232R CBUS requires a one-time EEPROM setup step on every platform.
  See [QUICKSTART.md](QUICKSTART.md) and the CBUS section below.

---

## macOS

### Supported configurations

| PowerShell | .NET | Backend | Status |
|-----------|------|---------|--------|
| 7.0-7.3 | 6 or 7 | FTD2XX_NET netstandard20 | Supported |
| 7.4+ | 8+ | Iot.Device.Bindings + native libftd2xx.dylib | Supported |

### Required components

- **libftd2xx.dylib**: native FTDI D2XX shared library.
  Download from https://ftdichip.com/drivers/d2xx-drivers/

### Kernel extension conflict

macOS ships two kexts that claim FTDI devices. Both must be unloaded:

```bash
sudo kextunload -bundle-id com.apple.driver.AppleUSBFTDI
sudo kextunload -bundle-id com.FTDI.driver.FTDIUSBSerialDriver
```

These unloads do not persist across reboots. To make them permanent, add a
launchd daemon that runs the unload commands at startup, or configure macOS
System Extensions depending on your macOS version (Monterey+).

### Gatekeeper quarantine

The downloaded `.dylib` will be quarantined by Gatekeeper:

```bash
sudo xattr -rd com.apple.quarantine /usr/local/lib/libftd2xx.dylib
```

### Apple Silicon (M1/M2/M3)

Use the `arm64` build of libftd2xx. Rosetta does not bridge native P/Invoke
calls. Confirm the architecture with `file /usr/local/lib/libftd2xx.dylib`.

### Notes

- PS 5.1 is not available on macOS. Minimum is PS 7.0.
- FT232R CBUS on macOS: requires `libftd2xx.dylib` installed and the kexts
  unloaded. Once the native library is loaded, the same P/Invoke path used
  on Linux applies. Testing on macOS is ongoing -- report issues on GitHub.

---

## Platform comparison

| Feature | Windows 5.1 | Windows 7+ | Linux 7+ | macOS 7+ |
|---------|------------|-----------|---------|---------|
| FT232H GPIO (MPSSE) | Yes | Yes | Yes | Yes |
| FT232H I2C scan | Yes | Yes | Yes | Yes |
| FT232H SSD1306 | Yes | Yes | Yes | Yes |
| FT232R CBUS GPIO | Yes | Yes | Yes [1] | Yes [1] |
| FT232R EEPROM programming | Yes | Yes | Yes [1] | Yes [1] |
| MicroPython REPL | Yes | Yes | Yes | Yes |
| Stub mode (no hardware) | Yes | Yes | Yes | Yes |
| Install-Module from Gallery | Yes | Yes | Yes | Yes |
| Native library bundled | Yes (DLL) | Yes (DLL) | No (.so required) | No (.dylib required) |

[1] Requires `libftd2xx.so` / `libftd2xx.dylib` installed and `ftdi_sio`
unloaded. Uses native P/Invoke (`FT_Open` / `FT_SetBitMode` / `FT_WriteEE`)
via `Private/Ftdi.PInvoke.ps1`. Stub mode is returned automatically if the
native library is not found.

---

## Detecting the platform in scripts

PSGadget uses this pattern internally and you can use it in your own scripts:

```powershell
$isWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
$psVersion = $PSVersionTable.PSVersion.Major

if ($isWindows) {
    # Windows path
} else {
    # Linux / macOS path
}
```

Do not use `$IsWindows` -- it is PS 7 only and PSGadget must work on PS 5.1.
