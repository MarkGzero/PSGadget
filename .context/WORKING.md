# Session Context — 2026-04-03T20:00:00Z

## Current Focus

All EEPROM work complete. Considering git history cleanup (250 commits → squashed milestones).

## Current State

### Completed this session (commits on `main`):

| Commit | Description |
|--------|-------------|
| `587ba42` | Full `FT_PROGRAM_DATA` struct (Version 5) for macOS `FT_EE_Program`; blank-EEPROM write fix for PS5.1 |
| `941f31c` | Restore EEPROM CapabilityNote on Windows PS5.1 via GC.Collect() before enrichment |

### Verified working:
- **macOS BG01B1EI** — `Set-PsGadgetFt232rCbusMode` succeeded via `FT_EE_Program`; `Get-FtdiEeprom` shows Cbus0-3 = `FT_CBUS_IOMODE`
- **Windows PS5.1 BG01B7VJ** — programmed from Windows (blank EEPROM path); `Get-FtdiEeprom` shows Cbus0-3 = `FT_CBUS_IOMODE`
- **Windows PS5.1 `Get-FtdiDevice`** — CapabilityNote correctly shows `CBUS0-3 all configured as I/O MODE -- ready for GPIO.`

### Devices:
- **BG01X3AK** — Windows FT232R, already programmed, IOMODE confirmed
- **BG01B7VJ** — Mac FT232R (serial `BG01B7VJ` after programming from Windows), IOMODE confirmed
- **BG01B1EI** — Mac FT232R (separate device on Mac, programmed via macOS FT_EE_Program)
- **FT9ZLJ51** — Windows FT232H, MPSSE, CapabilityNote `ACBUS0-7 all MPSSE-controllable.`

## Recent Decisions

### FtProgramData struct (Ftdi.PInvoke.ps1)
Full `FT_PROGRAM_DATA` through Version 5 (all 72 missing fields for FT2232H/FT4232H/FT232H).
`Version = [uint32]5` in `Set-FtdiNativeCbusEeprom` — required so libftd2xx knows struct is complete.
Per AN_428: FT232R uses Version=2 logically but the struct must be allocated through Version 5
for ABI safety (libftd2xx writes beyond declared-version fields regardless).

### Blank EEPROM detection (Ftdi.Cbus.ps1)
`ReadFT232REEPROM` (FTD2XX_NET) AVE-crashes on blank-EEPROM devices (empty serial number).
AVE is uncatchable on .NET Framework. Fix: skip read when `SerialNumber == ''`, use
factory defaults (`VID=0x0403, PID=0x6001, MaxPower=90, SerNumEnable=true`).

### PS5.1 GC fix (Ftdi.Backend.ps1)
`GetDeviceList` (FTD2XX_NET) leaves D2XX handles open until GC collects the FTDI object.
`FTDI.Close()` is insufficient on .NET Framework. Fix: `[System.GC]::Collect() +
WaitForPendingFinalizers()` after `Invoke-FtdiWindowsEnumerate` returns, before enrichment loop.
Re-enabled enrichment on PS5.1 for devices with non-empty serial (valid EEPROM).

### SSH / deploy
- SSH key: `C:\Users\mark\.ssh\mbp001_id` → MBP001 (`AdminMark@192.168.25.100`)
- Deploy: `pwsh -File ./Tools/Deploy-ToMac.ps1 [-Reload] [-File <rel-path>]`
- Mac pwsh: `/usr/local/bin/pwsh` (must use full path in SSH commands)
- Mac module: `/Users/AdminMark/psgadget/PSGadget.psm1`

### Git history
Repo has ~250 commits. User asked about squashing to logical milestones (~20-30 commits).
Safe approach: `git checkout -b history/full` to preserve full history, then
`git rebase -i <root>` or soft-reset approach on `main`. **Not yet done — needs user confirmation.**

## Active Files

All changes committed. No uncommitted working changes.

| File | Last change |
|------|-------------|
| `Private/Ftdi.PInvoke.ps1` | Full FtProgramData struct (Version 5); `Set-FtdiNativeCbusEeprom` Version=5 |
| `Private/Ftdi.Cbus.ps1` | Blank-EEPROM skip for `ReadFT232REEPROM` on PS5.1 |
| `Private/Ftdi.Backend.ps1` | GC.Collect() before enrichment on PS5.1; re-enabled enrichment; verbose catch |
| `Public/Set-PsGadgetFt232rCbusMode.ps1` | PS5.1 preview guard; CyclePort Windows-only |
| `PSGadget.psm1` | Fix FtdiInitialized overwrite bug |
| `Tools/Deploy-ToMac.ps1` | New; uses `/usr/local/bin/pwsh` for SSH reload |

## Key Constraints

- PS 5.1+; no PS7-only operators (`?:`, `?.`, `??`); ASCII only in PS code/strings
- `FTD2XX_NET.dll` Windows-only; native P/Invoke (libftd2xx) for macOS/Linux
- `FT_CyclePort` Windows-only
- `FT_EraseEE` must never be called on FT232R (internal EEPROM, cannot be erased)
- `AccessViolationException` uncatchable on .NET Framework (PS5.1)
- Module load order in `PSGadget.psm1` is fixed
- Only D2XX (libftd2xx / FTD2XX_NET) or dotnet IoT (`Iot.Device.*`) — no other libraries

## Known Issues

None critical. Pre-existing cleanup items remain:

1. `Tests/PsGadget.Tests.ps1` version check expects `0.4.0` → needs bump to `0.4.2`
2. No SPI/UART stub tests
3. `.github/copilot-instructions.md` references deleted `docs/PERSONAS.md`
4. `examples/psgadget_workflow.md` lists deprecated `Send-PsGadgetI2CWrite`
5. Module version still `0.4.2` — consider bumping to `0.4.3` after cleanup
6. `.context/WORKING.md` excluded by `.gitignore` — cannot be committed without `-f`

## Next Actions

Option A — Git history squash (user expressed interest, needs confirmation):
1. `git checkout -b history/full` — preserve full history
2. Draft rebase plan grouping ~250 commits into ~20-30 logical milestones
3. Execute `git rebase -i --root` or squash strategy on `main`

Option B — Pre-existing cleanup (in priority order):
1. **Fix test version check** — `Tests/PsGadget.Tests.ps1`: `0.4.0` → `0.4.2`
2. **Add stub tests** — `Context 'SPI'` and `Context 'UART'` blocks
3. **Fix PERSONAS.md ref** — `.github/copilot-instructions.md`
4. **Remove deprecated API** — `examples/psgadget_workflow.md`
5. **Bump module version** — `0.4.2` → `0.4.3`
