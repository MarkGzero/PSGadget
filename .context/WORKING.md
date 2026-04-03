# Session Context — 2026-04-02T15:55:00Z

## Current Focus

macOS FT232R GPIO support — completed and pushed. No active feature work.

## Current State

- **Completed this session** (`231c2a8` on `main`):
  - Fixed `SetPin`/`ReadPin` silently broken on macOS FT232R
  - Root cause: `Invoke-FtdiUnixOpen` re-enumerated via sysfs (no sysfs on macOS),
    got FT232H stub at index 0, assigned `GpioMethod='MPSSE'` to real FT232R device
  - Fix: pass `DeviceInfo` from IoT enumeration into `Invoke-FtdiUnixOpen` via new
    optional `-DeviceInfo` param; skip sysfs when provided
  - Added `FT_GetBitMode` P/Invoke + `Invoke-FtdiNativeGetBitMode` for native CBUS reads
  - `Get-FtdiCbusBits` now reads real pin state on macOS/Linux via native path
  - Committed `Public/Start-PsGadgetTrace.ps1` (was untracked; Mac lacked the file)
- **Previous session** (`10f4949`):
  - EEPROM functions guarded for macOS/Linux (return null, not throw)
- **Previous session** (`113ad97`):
  - Error cascade fix: `IsOpen` → fail-fast throw; removed `Write-Error+throw` in catches
  - `Install-MacOSD2XXDrivers` cmdlet (macOS D2XX install automation)
  - EEPROM API split, VCP detection fix, CBUS auto-LOW
- **Working tree is clean**; verified on real hardware (FT232R BG01X3AK, macOS 11.7.11)

## Recent Decisions

### macOS FT232R CBUS GPIO
- IoT enumeration correctly identifies FT232R as `GpioMethod=CBUS`; sysfs stubs must not override it
- `Invoke-FtdiUnixOpen -DeviceInfo` param is optional — Linux sysfs path is unchanged (backward compat)
- `FT_GetBitMode` in CBUS mode returns CBUS0-3 pin levels in bits 0-3
- AppDomain guard: if old `FtdiNative` type (without `FT_GetBitMode`) is registered, fall back to `0x00` stub
- `ReadPin` reflects physical pin state; 200k ohm internal pull-up means undriven inputs read HIGH; user's 2.2kOhm pull-downs required for LOW reads

### Error message convention
- Device-in-use message: "Device 'SN' is already open. Run Get-ConnectedPsGadget to find the open handle and call .Close() on it."

### Naming convention: Ftdi* vs PsGadget*
- `Verb-Ftdi*` = no live connection required (discovery, EEPROM read by index)
- `Verb-PsGadget*` = requires live `[PsGadgetFtdi]` object

### macOS test device
- MBP001 (Natalie-MBP / AdminMark), SSH accessible, PS 7.6.0 / .NET 10.0.5
- FT232R BG01X3AK with CBUS0-2 wired to RGB LED; 2.2kOhm pull-downs on CBUS0-2
- Local dev clone at /Users/AdminMark/psgadget

## Active Files

No files actively under development. Working tree is clean.

## Key Constraints

- PowerShell 5.1+; no PS7-only operators (`?:`, `?.`, `??`); ASCII only in PS code/strings
- `Start-PsGadgetTrace` on Windows must use `Start-Process powershell` (not `pwsh`)
- Module load order in `PSGadget.psm1` is fixed (see copilot-instructions.md)
- Branch: `main` only (dev1 deleted)
- Module version: `0.4.2` (PSGadget.psd1)
- IoT backend path (macOS/Linux): `Invoke-FtdiIotOpen` -> `Invoke-FtdiUnixOpen -DeviceInfo`
- FTD2XX_NET.dll is Windows-only; EEPROM ops on macOS return null silently

## Known Issues

- `Tests/PsGadget.Tests.ps1` version check still expects `0.4.0`; needs bump to `0.4.2`
- No SPI stub tests (Context 'SPI' block missing)
- No UART stub tests (Context 'UART' block missing)
- `.github/copilot-instructions.md` "Examples Conventions" still references `docs/PERSONAS.md` (deleted)
- `examples/psgadget_workflow.md` may be out of sync with current public API

## Next Actions

1. **Fix version in tests** — `Tests/PsGadget.Tests.ps1`: change `0.4.0` -> `0.4.2`
2. **Add SPI stub tests** — new `Context 'SPI'` block:
   - `Invoke-PsGadgetSpi` is exported; write-only returns `$true`; read-only returns `[byte[]]`
3. **Add UART stub tests** — new `Context 'UART'` block:
   - `Invoke-PsGadgetUart` is exported; `-ReadLine` returns `$null` (stub); `-ReadCount 4` returns `[byte[]]`
4. **Fix copilot-instructions.md** — "Examples Conventions" references `docs/PERSONAS.md` (deleted);
   update to point to current docs
5. Commit and push above changes
