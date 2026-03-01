# PSGadget Troubleshooting

Start here: run `Test-PsGadgetEnvironment -Verbose` and read the `Status`,
`Reason`, and `NextStep` fields. The command covers the most common problems
automatically.

---

## Table of Contents

- [Quick diagnostics](#quick-diagnostics)
- [Symptom index](#symptom-index)
- [No devices found](#no-devices-found)
- [Stub backend](#stub-backend)
- [Missing native library (Linux/macOS)](#missing-native-library-linuxmacos)
- [Access denied or device busy](#access-denied-or-device-busy)
- [FT232R CBUS pins do not respond](#ft232r-cbus-pins-do-not-respond)
- [SSD1306 shows nothing](#ssd1306-shows-nothing)
- [MicroPython connection fails](#micropython-connection-fails)
- [Module fails to import](#module-fails-to-import)
- [Tests pass but hardware does not work](#tests-pass-but-hardware-does-not-work)
- [Wrong DLL path](#wrong-dll-path)
- [DLL version mismatch or CVE advisory](#dll-version-mismatch-or-cve-advisory)
  - [Check current state locally](#check-current-state-locally)
  - [Apply NuGet updates](#apply-nuget-updates)
  - [FTDI vendor DLLs (not on NuGet)](#ftdi-vendor-dlls-not-on-nuget)
  - [Common errors from the update script](#common-errors-from-the-update-script)
- [Still stuck?](#still-stuck)

---

## Quick diagnostics

```powershell
Import-Module PSGadget
$result = Test-PsGadgetEnvironment -Verbose
$result | Select-Object Status, Reason, NextStep, Backend, DeviceCount
```

If `Status` is `Fail`, `NextStep` tells you exactly what command to run.

---

## Symptom index

- [Module imports but no devices are found](#no-devices-found)
- [Backend shows "Stub (no hardware access)"](#stub-backend)
- [Status is Fail: native library not found (Linux/macOS)](#missing-native-library-linux-macos)
- [Device found but Connect-PsGadgetFtdi throws an access error](#access-denied-or-device-busy)
- [FT232R CBUS pins do not respond](#ft232r-cbus-pins-do-not-respond)
- [SSD1306 display shows nothing](#ssd1306-shows-nothing)
- [MicroPython board not listed or connection fails](#micropython-connection-fails)
- [Module fails to import (syntax or type errors)](#module-fails-to-import)
- [Tests pass but hardware does not work](#tests-pass-but-hardware-does-not-work)
- [Verbose output shows wrong DLL path](#wrong-dll-path)
- [DLL version mismatch or CVE advisory](#dll-version-mismatch-or-cve-advisory)

---

## No devices found

**Symptom**: `List-PsGadgetFtdi` returns nothing, or `DeviceCount` is 0.

**Check list**:

1. Is the USB cable plugged in? Try a different port or cable. Data cables
   only -- charge-only cables have no data lines.

2. On Windows, does Device Manager show the device?
   - If it shows with a yellow warning icon, the D2XX driver is not installed.
     See [INSTALL.md -- Windows Step 2](INSTALL.md#step-2---install-the-ftdi-d2xx-driver-windows-only).
   - If it shows as "USB Serial Port (COMx)" the device is in VCP mode, not
     D2XX mode. The installed driver is the wrong one; install D2XX.

3. On Linux, does `lsusb` show the FTDI device (vendor ID 0403)?

```bash
lsusb | grep -i ftdi
# expected: Bus 001 Device 003: ID 0403:6014 Future Technology Devices International, Ltd FT232H Single HS USB-UART/FIFO IC
```

4. On Linux, is `ftdi_sio` loaded? It claims the device before D2XX can:

```bash
lsmod | grep ftdi_sio
# if shown:
sudo rmmod ftdi_sio
```

---

## Stub backend

**Symptom**: `Test-PsGadgetEnvironment` reports
`Backend: Stub (no hardware access)` and `BackendReady: False`.

This means the managed .NET DLLs loaded but the native hardware library was
not found, OR the DLLs themselves failed to load.

**Fix on Windows**: reinstall the FTDI D2XX driver.
See [INSTALL.md -- Windows](INSTALL.md#windows).

**Fix on Linux/macOS**: install `libftd2xx.so` / `libftd2xx.dylib`.
See [INSTALL.md -- Linux](INSTALL.md#linux) or [INSTALL.md -- macOS](INSTALL.md#macos).

**To see exactly what was tried**, reimport with `-Verbose`:

```powershell
Remove-Module PSGadget -ErrorAction SilentlyContinue
Import-Module PSGadget -Verbose
```

The verbose output shows every DLL path attempted and the result.

---

## Missing native library (Linux/macOS)

**Symptom**: `Test-PsGadgetEnvironment` reports
`Native lib: [MISSING] libftd2xx.so not found`.

**Fix**:

1. Download from https://ftdichip.com/drivers/d2xx-drivers/
2. Install:

```bash
sudo cp libftd2xx.so.* /usr/local/lib/
sudo ln -sf /usr/local/lib/libftd2xx.so.* /usr/local/lib/libftd2xx.so
sudo ldconfig
```

3. Verify:

```bash
ldconfig -p | grep ftd2xx
```

4. Reimport the module:

```powershell
Remove-Module PSGadget
Import-Module PSGadget
Test-PsGadgetEnvironment
```

**Wrong architecture**: if the library loads but hardware calls crash with
P/Invoke or EntryPointNotFound errors, you have the wrong architecture build.
Check with `file libftd2xx.so` and compare to `uname -m`.

---

## Access denied or device busy

**Symptom**: `Connect-PsGadgetFtdi` throws an access or "device not found"
error even though the device is listed.

**On Linux**:

Your user account needs to be in the `plugdev` group:

```bash
sudo usermod -aG plugdev $USER
# log out and back in
```

You may also need a udev rule:

```bash
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev"' \
  | sudo tee /etc/udev/rules.d/99-ftdi.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Then unplug and replug the device.

**On Windows**:

Another application (PuTTY, Arduino IDE, another PSGadget session) may have
the device open. Close it and retry. If the problem persists, use Device
Manager to update the driver to the D2XX driver (not the VCP driver).

---

## FT232R CBUS pins do not respond

**Symptom**: `Set-PsGadgetGpio` runs without error but pins stay LOW or do
not do anything.

The FT232R requires a one-time EEPROM programming step to enable CBUS
bit-bang mode. This is not needed for FT232H.

```powershell
# Program the EEPROM on device at index 0 (only needed once per device)
Set-PsGadgetFt232rCbusMode -Index 0
```

After this command, **unplug and replug the USB cable**. The EEPROM change
does not take effect until the device re-enumerates.

If the device was already programmed but pins still do not respond, read the
EEPROM to confirm the mode was saved:

```powershell
Get-PsGadgetFtdiEeprom -Index 0
```

---

## SSD1306 shows nothing

**Check list**:

1. Wiring: FT232H ACBUS0 = SCL, ACBUS1 = SDA. Display VCC to 3.3 V, GND to GND.
   A 4.7 kohm pull-up resistor on SDA and SCL to 3.3 V is required for I2C.

2. Confirm the display responds on the I2C bus:

```powershell
$ftdi = Connect-PsGadgetFtdi -Index 0
$ftdi.Scan()    # should include 0x3C or 0x3D in the list
```

   If the I2C scan returns nothing, the wiring or pull-ups are wrong.

3. The default I2C address is `0x3C`. If your display has the address pin
   (SA0) pulled HIGH, the address is `0x3D`. Pass `-Address 0x3D` to
   `Connect-PsGadgetSsd1306`.

4. Power: some generic SSD1306 modules run on 5 V but the I2C lines are
   5 V tolerant only if the display board has level shifters. If you see
   ACK errors, try powering the display from 3.3 V instead of 5 V.

---

## MicroPython connection fails

**Symptom**: `Connect-PsGadgetMpy` throws, or `Invoke` returns nothing.

1. Confirm the port name:

```powershell
List-PsGadgetMpy | Format-Table
```

   On Linux the port is usually `/dev/ttyUSB0` or `/dev/ttyACM0`.
   On Windows it is `COM3`, `COM4`, etc.

2. Confirm `mpremote` is installed:

```bash
mpremote --version
```

   Install with: `pip install mpremote`

3. On Linux, your user needs to be in the `dialout` group:

```bash
sudo usermod -aG dialout $USER
# log out and back in
```

4. Confirm the board is in REPL mode. A board in a tight `while True` loop
   may not respond. Press Ctrl+C in a serial terminal (e.g. `screen`) to
   interrupt it, then retry.

---

## Module fails to import

**Symptom**: `Import-Module PSGadget` throws errors like
"Try statement is missing its Catch or Finally block" or
"Unexpected token".

This is almost always caused by Unicode characters in a file that was edited
on a system where an editor silently inserted them (smart quotes, em dashes,
non-breaking spaces). PSGadget prohibits all Unicode in code files.

Check for non-ASCII characters:

```bash
grep -Prn "[^\x00-\x7F]" /path/to/PSGadget/*.ps1 /path/to/PSGadget/**/*.ps1
```

Replace any found characters with their ASCII equivalents.

If you are on a saved version from git, reset the file:

```bash
git checkout -- Private/Ftdi.Mpsse.ps1
```

---

## Tests pass but hardware does not work

The Pester test suite runs entirely in stub mode (no hardware required). Passing
tests confirm the API surface and module structure are correct, but do not
exercise real D2XX calls.

To run the hardware validation suite on Windows with a connected device:

```powershell
. ./Tests/Test-PsGadgetWindows.ps1
```

This requires a physical FTDI device and the D2XX driver installed.

---

## Wrong DLL path

**Symptom**: verbose import shows `DLL not found` for a path that looks wrong.

PSGadget looks for DLLs relative to `$PSScriptRoot` inside `Initialize-FtdiAssembly`.
If you moved the module folder after installing, `$PSScriptRoot` changes and the
relative paths break.

Fix: ensure the module folder structure is intact:

```
PSGadget/
  PSGadget.psd1
  PSGadget.psm1
  lib/net48/FTD2XX_NET.dll
  lib/netstandard20/FTD2XX_NET.dll
  lib/net8/Iot.Device.Bindings.dll
  ...
```

If importing from a custom path, always import `PSGadget.psd1` directly
rather than a `.psm1` file, so `$PSScriptRoot` resolves to the module root.

---

## DLL version mismatch or CVE advisory

**Symptom**: GitHub Actions `lib-audit` workflow fails, or `dotnet list package --vulnerable`
reports a CVE, or the weekly audit email flags an outdated package.

### Check current state locally

```powershell
# Requires dotnet SDK 8+ on PATH
pwsh ./Tools/Update-PsGadgetLibs.ps1 -Audit
```

This reports:
- Any packages with known CVEs (fails CI if found)
- Any packages with newer versions available

### Apply NuGet updates

1. Open `lib/nuget-deps.csproj` and bump the `Version` attribute for the
   affected package(s).
2. Run:

```powershell
# Dry run -- shows what would change
pwsh ./Tools/Update-PsGadgetLibs.ps1

# Apply -- downloads from NuGet and replaces DLLs
pwsh ./Tools/Update-PsGadgetLibs.ps1 -Apply
```

3. Confirm clean:

```powershell
pwsh ./Tools/Update-PsGadgetLibs.ps1 -Audit
# Expected: no vulnerable packages, no updates available
```

4. Update version strings in `lib/README.md` to match.
5. Bump `ModuleVersion` in `PSGadget.psd1`.

### FTDI vendor DLLs (not on NuGet)

`lib/native/FTD2XX.dll`, `lib/net48/FTD2XX_NET.dll`, and
`lib/netstandard20/FTD2XX_NET.dll` are not tracked by NuGet.
Monitor https://ftdichip.com/drivers/d2xx-drivers/ manually for updates.
Download the CDM package, extract the matching DLLs, and replace the
bundled copies. Update the version note in `lib/README.md`.

### Common errors from the update script

| Error | Fix |
|-------|-----|
| `dotnet SDK not found on PATH` | Install from https://dotnet.microsoft.com/download |
| `Package cache not found for X` | Check package ID in `lib/nuget-deps.csproj`; run `dotnet restore lib/nuget-deps.csproj` manually |
| `DLL not found in package cache` | Package layout changed upstream; inspect the restored package dir under `/tmp/psgadget-lib-update/packages/` and update the `$LibMap` entry in `Tools/Update-PsGadgetLibs.ps1` |
| `NU1701` warning on FtdiSharp | Expected and harmless -- FtdiSharp targets net4x; it is loaded via `LoadFrom()` at runtime |

---

## Still stuck?

Run this and include the output when asking for help:

```powershell
$result = Test-PsGadgetEnvironment -Verbose
$result | Format-List

$PSVersionTable
[System.Environment]::OSVersion
[System.Environment]::Version
```
