# PSGadget Troubleshooting

Start here: run `Test-PsGadgetEnvironment -Verbose` and read the `Status`,
`Reason`, and `NextStep` fields. The command covers the most common problems
automatically.

---

## Table of Contents

- [Quick diagnostics](#quick-diagnostics)
- [Symptom index](#symptom-index)
- [No devices found](#no-devices-found)
- [Device shows as VCP only (Linux)](#device-shows-as-vcp-only-linux)
- [Stub backend](#stub-backend)
- [Missing native library (Linux/macOS)](#missing-native-library-linuxmacos)
- [Linux: snap-confined pwsh and glibc mismatch](#linux-snap-confined-pwsh-and-glibc-mismatch)
- [Linux: NativeLibOk reports True but backend stays in stub mode](#linux-nativelibOk-reports-true-but-backend-stays-in-stub-mode)
- [Access denied or device busy](#access-denied-or-device-busy)
- [FT232R CBUS pins do not respond](#ft232r-cbus-pins-do-not-respond)
  - [Step 1: program the EEPROM](#step-1-program-the-eeprom-all-platforms)
  - [Step 2: install libftd2xx.so (Linux/macOS)](#step-2-linuxmacos-only----install-libftd2xxso)
  - [Step 3: verify native connection](#step-3-verify-the-connection-is-native-not-stub)
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
- [Device listed only under List-PsGadgetFtdi -ShowVCP on Linux](#device-shows-as-vcp-only-linux)
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
     See [Getting-Started](Getting-Started.md) for Windows installation steps.
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

## Device shows as VCP only (Linux)

**Symptom**: `List-PsGadgetFtdi` returns nothing, but `List-PsGadgetFtdi -ShowVCP`
shows the device with `Driver: ftdi_sio (VCP)` and `LocationId: /dev/ttyUSBx`.

**Cause**: The `ftdi_sio` kernel module has claimed the device as a virtual COM
port. D2XX and `ftdi_sio` cannot share the same device -- whichever driver binds
first wins. `ftdi_sio` loads automatically on plug-in unless it is blacklisted.

---

**Fix** -- unload the VCP module so D2XX can claim the device:

```bash
sudo rmmod ftdi_sio
```

Then reimport:

```powershell
Import-Module PSGadget -Force
List-PsGadgetFtdi
```

To confirm `ftdi_sio` is the culprit before unloading:

```bash
lsmod | grep ftdi_sio
```

---

**Perm** -- blacklist the module so it never auto-loads across reboots:

```bash
echo 'blacklist ftdi_sio' | sudo tee /etc/modprobe.d/ftdi-d2xx.conf
sudo update-initramfs -u     # Debian/Ubuntu
# On RHEL/Fedora: sudo dracut --force
```

---

**Restore** -- re-enable VCP mode at any time (if you need `/dev/ttyUSBx` back):

```bash
sudo modprobe ftdi_sio
# or remove the blacklist file and reboot:
sudo rm /etc/modprobe.d/ftdi-d2xx.conf && sudo reboot
```

---

> **Note**: `libftd2xx.so` must also be installed for D2XX to work. If the device
> claims correctly after `rmmod` but `List-PsGadgetFtdi` still returns nothing,
> see [Missing native library (Linux/macOS)](#missing-native-library-linuxmacos).

---

## Stub backend

**Symptom**: `Test-PsGadgetEnvironment` reports
`Backend: Stub (no hardware access)` and `BackendReady: False`.

This means the managed .NET DLLs loaded but the native hardware library was
not found, OR the DLLs themselves failed to load.

**Fix on Windows**: reinstall the FTDI D2XX driver.
See [Getting-Started](Getting-Started.md) for Windows installation instructions.

**Fix on Linux/macOS**: install `libftd2xx.so` / `libftd2xx.dylib`.
See [Getting-Started](Getting-Started.md) for Linux or macOS installation instructions.

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
# Step 1: download and extract (adjust version/arch as needed)
cd /tmp
wget https://ftdichip.com/wp-content/uploads/2025/11/libftd2xx-linux-x86_64-1.4.34.tgz
tar xzf libftd2xx-linux-x86_64-1.4.34.tgz
# The tarball extracts to linux-x86_64/ (NOT release/)

# Step 2: capture the versioned .so path before using sudo
# (glob expansion does not work inside sudo)
versioned=$(find /tmp -maxdepth 3 -name 'libftd2xx.so.*' -not -path '*/usr/*' | head -1)
sudo cp "$versioned" /usr/local/lib/
sudo rm -f /usr/local/lib/libftd2xx.so
sudo ln -sf "$versioned" /usr/local/lib/libftd2xx.so
sudo ldconfig

# Step 3: copy into lib/net8/ so snap-confined pwsh can load it
# (snap AppArmor blocks open() on /usr/local/lib but allows reads from
# the module directory, so a local copy is required for snap pwsh)
cp "$versioned" ~/psgadget/lib/net8/libftd2xx.so
```

3. Verify:

```bash
ls -la /usr/local/lib/libftd2xx*
ls -lh ~/psgadget/lib/net8/libftd2xx.so
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

## Linux: snap-confined pwsh and glibc mismatch

**Symptom**: module import prints:

```
WARNING: NativeLibrary.Load failed for .../libftd2xx.so
  GLIBC_2.38 not found (required by .../libftd2xx.so)
```

or `IotBackend: False` after installing `libftd2xx.so.1.4.34`.

**Cause**: The version of `pwsh` installed via snap uses the `core22` base snap
(Ubuntu 22.04 userland, glibc 2.35). `libftd2xx.so.1.4.34` was compiled on
Ubuntu 24.04 and requires glibc 2.38. The host glibc (2.39 on Ubuntu 24.04)
is compatible, but snap-confined processes use the snap's bundled glibc, not
the host version.

**Confirm whether your pwsh is snap or native**:

```bash
readlink -f $(which pwsh)
# /usr/bin/snap  -> snap-confined (the culprit)
# /usr/bin/pwsh  -> native apt package (no issue)
```

**Fix A (recommended) -- install native pwsh via apt**:

```bash
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update && sudo apt-get install -y powershell
# Launch with:
/usr/bin/pwsh
```

The apt-installed pwsh links against the host glibc and loads
`libftd2xx.so.1.4.34` without issue.

**Fix B -- downgrade to an older FTDI library (glibc <= 2.35)**:

If you must use snap pwsh, use a library version compiled against an older
glibc. Check the requirement first:

```bash
objdump -p /tmp/linux-x86_64/libftd2xx.so.1.4.30 | grep GLIBC
```

Then install it the same way as the newer version (see
[Missing native library](#missing-native-library-linuxmacos)).

---

## Linux: NativeLibOk reports True but backend stays in stub mode

**Symptom**: `Test-PsGadgetEnvironment` shows `NativeLibOk: True` with a path
under `/usr/local/lib/`, but `IotBackend: False` and
`Backend: Stub (no hardware access)`. Trying to copy the file manually with
`cp /usr/local/lib/libftd2xx.so ...` fails with "No such file or directory".

**Cause**: snap-confined `pwsh` overrides the PowerShell `Test-Path` provider
with an AppArmor-aware virtual filesystem view. `Test-Path` can return `$true`
for paths outside the snap tree even when the file is not accessible to
.NET P/Invoke or the bash shell. The module now uses `[System.IO.FileInfo]::Exists`
to detect library files, but older versions used `Test-Path` and were vulnerable
to this false positive.

**Diagnosis**:

```bash
# From bash (not pwsh) -- this tells the truth:
ls /usr/local/lib/libftd2xx* 2>/dev/null || echo "File not found by bash"
```

If bash says "not found" but `Test-PsGadgetEnvironment` reports `[OK]`, you
have the snap false-positive bug. Upgrade to the latest dev1 branch.

**Fix**: see [Missing native library](#missing-native-library-linuxmacos) --
install the library from bash, then copy the versioned `.so` into `lib/net8/`:

```bash
# Run from bash, not pwsh
cp /usr/local/lib/libftd2xx.so.1.4.34 ~/psgadget/lib/net8/libftd2xx.so
```

The module checks `lib/net8/libftd2xx.so` first in the native library search
order. A file placed there persists across module reimports -- the module skips
the copy step if a valid (non-zero-byte) file already exists at that path.

---

## Access denied or device busy

**Symptom**: `Connect-PsGadgetFtdi` throws an access or "device not found"
error even though the device is listed.

**On Linux**:

Your user account needs to be in the `plugdev` group:

```bash
sudo usermod -aG plugdev $USER
# log out and back in for the group change to take effect
```

You also need a udev rule that grants the `plugdev` group write access to
FTDI USB nodes:

```bash
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", MODE="0664", GROUP="plugdev"' \
  | sudo tee /etc/udev/rules.d/99-ftdi-d2xx.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Then unplug and replug the device (or, on WSL, detach and reattach via
usbipd). The udev rule fires automatically on plug events.

> **WSL-specific**: `udevadm trigger` does not retroactively apply
> `MODE`/`GROUP` to a device that was attached before the rule was written.
> Fix permissions for the current session without replugging:
>
> ```bash
> # Find your device: lsusb shows Bus NNN Device MMM
> sudo chown root:plugdev /dev/bus/usb/001/002
> sudo chmod 0664 /dev/bus/usb/001/002
> ```
>
> Detach and reattach via `usbipd detach` / `usbipd attach --wsl` to have
> the rule apply automatically going forward.

**On Windows**:

Another application (PuTTY, Arduino IDE, another PSGadget session) may have
the device open. Close it and retry. If the problem persists, use Device
Manager to update the driver to the D2XX driver (not the VCP driver).

---

## FT232R CBUS pins do not respond

**Symptom**: `Set-PsGadgetGpio` runs without error but pins stay LOW or do
not do anything.

FT232R CBUS GPIO has a **two-step** requirement on every platform:

1. **EEPROM programming** (one-time per device)
2. **libftd2xx.so installed** (Linux/macOS) or D2XX driver installed (Windows)

---

### Step 1: program the EEPROM (all platforms)

The FT232R ships with CBUS pins set to LED / clock functions, not GPIO.
You must program the EEPROM once to set them to `FT_CBUS_IOMODE`:

```powershell
# Configure CBUS0-3 as GPIO on device at index 0 (only needed once per device)
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0, 1, 2, 3)
```

After this command, **unplug and replug the USB cable**. The EEPROM change
does not take effect until the device re-enumerates.

To confirm the EEPROM was written correctly:

```powershell
# Windows only (uses FTD2XX_NET)
Get-PsGadgetFtdiEeprom -Index 0

# Linux/macOS (uses native P/Invoke)
& (Get-Module PSGadget) { Get-FtdiNativeCbusEepromInfo -Index 0 }
```

Expected output shows `Cbus0 : FT_CBUS_IOMODE` (and Cbus1-3 if programmed).
If any pin shows a different value (e.g. `FT_CBUS_TXLED`), run
`Set-PsGadgetFt232rCbusMode` again and replug.

---

### Step 2: Linux/macOS only -- install libftd2xx.so

FT232R CBUS uses the native D2XX library (`libftd2xx.so`) via P/Invoke on
Linux. The IoT backend (used for MPSSE chips like FT232H) does not implement
CBUS bit-bang. Check the module loaded the native path:

```powershell
Import-Module PSGadget -Verbose
# Look for:
#   VERBOSE:   NativeLibrary.Load: OK (/path/to/libftd2xx.so)
#   VERBOSE:   FtdiNative P/Invoke: registered
```

If either line is missing, install `libftd2xx.so` first:
See [Missing native library](#missing-native-library-linuxmacos).

Also ensure USB permissions are set -- D2XX needs write access to the
`/dev/bus/usb/BUS/DEV` node. See [Access denied or device busy](#access-denied-or-device-busy).

---

### Step 3: verify the connection is native (not stub)

```powershell
$dev = Connect-PsGadgetFtdi -Index 0
$dev | Select-Object Platform, GpioMethod, NativeHandle
```

Expected:

```
Platform    GpioMethod NativeHandle
--------    ---------- ------------
Unix        CBUS       135635811853744   # non-zero IntPtr
```

If `Platform` shows `Unix (STUB)` or `NativeHandle` is `0`, the device
opened in stub mode -- either `libftd2xx.so` was not loaded, USB permissions
are wrong, or `ftdi_sio` still holds the device. Check verbose import output
and run `sudo rmmod ftdi_sio` if needed.

---

### Still not working after all steps?

Run the full diagnostic:

```powershell
Test-PsGadgetEnvironment -Verbose | Format-List
```

Key fields to check: `NativeLibOk`, `IotBackend`, `FtdiNativePInvoke`,
`Backend`, `DeviceCount`.

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
