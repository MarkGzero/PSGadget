# Session Context — 2026-04-02T00:00:00Z

## Current Focus

All docs cleanup complete and pushed to main. No active feature work.

## Current State

- **Completed and pushed** (`0889717` on `main`):
  - Deleted 11 stale docs/ files (stubs, duplicates, orphan images ~3.7MB)
  - Created `docs/README.md` categorized index
  - Fixed 2 dead links in `docs/REFERENCE/MPSSE_Reference.md`
  - Added macOS D2XX v1.4.30 install section to `docs/wiki/Troubleshooting.md`
  - Split Linux/macOS troubleshooting into separate sections
- **Previous push** (`113ad97` on `main`):
  - `Get-FtdiEeprom` (no-connection, ByIndex/BySerial) split from `Get-PsGadgetFtdiEeprom` (live PsGadget object)
  - `New-PsGadgetFtdi` auto-drives FT232R CBUS IOMODE pins LOW on connect
  - VCP count fixed: cross-checks `HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM` (real-time) vs FTDIBUS registry (historical)
  - OpenByIndex D2XX retry demoted from `Write-Verbose` to `Write-Debug`
  - `Get-FtdiDevice` Zadig warning replaced with CDM driver URL + troubleshooting link
- **Working tree is clean**; no uncommitted changes

## Recent Decisions

### Naming convention: Ftdi* vs PsGadget*
- `Verb-Ftdi*` = no live connection required (discovery, EEPROM read by index)
- `Verb-PsGadget*` = requires live `[PsGadgetFtdi]` object

### FT232R CBUS auto-LOW (New-PsGadgetFtdi)
- EEPROM read happens BEFORE `$dev.Connect()` to avoid "device already open" conflict
- After Connect(), all IOMODE pins driven LOW via `$dev.SetPins()`
- Verbose message explains the 200k ohm pull-up and safety rationale (ASCII only)

### VCP count fix
- `HKLM:\SYSTEM\CurrentControlSet\Enum\FTDIBUS` retains ALL historical entries — useless for current count
- `HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM` is real-time (only active COM ports) — use this to cross-check

### docs/ cleanup
- Deleted: ARCHITECTURE.md, HARDWARE_KIT.md, INSTALL.md, PERSONAS.md, PLATFORMS.md,
  QUICKSTART.md, REFERENCE/Classes.md, REFERENCE/Cmdlets.md, image*.png
- Kept: TROUBLESHOOTING.md (GitHub redirect), REFERENCE/MPSSE_Reference.md (unique),
  about_PsGadgetConfig.md (Get-Help target), about_PsGadgetDaemon.md, about_adafruit_ft232h.md

### copilot-instructions.md needs updating
- Still references deleted files (INSTALL.md, QUICKSTART.md, ARCHITECTURE.md, etc.)
- "Docs to Link" section must be updated to point to current files

## Active Files

No files actively under development. Working tree is clean.

## Key Constraints

- PowerShell 5.1+; no PS7-only operators (`?:`, `?.`, `??`); ASCII only in PS code/strings
- `Open-PsGadgetTrace` / `Start-PsGadgetTrace` must use `Start-Process powershell` (not `pwsh`)
- Module load order in `PSGadget.psm1`:
  1. `PsGadgetLogger.ps1`
  2. `PsGadgetI2CDevice.ps1`
  3. `PsGadgetSsd1306.ps1`
  4. `PsGadgetSpi.ps1`     <- must precede PsGadgetFtdi
  5. `PsGadgetUart.ps1`    <- must precede PsGadgetFtdi
  6. `PsGadgetFtdi.ps1`
  7. `PsGadgetMpy.ps1`
  8. `PsGadgetPca9685.ps1`
- Branch: `main` (dev1 was merged)
- IDE static analysis false positives for cross-file class refs are expected

## Known Issues

- `Tests/PsGadget.Tests.ps1` — version check still expects `0.4.0`; needs bump to `0.4.2`
  and new test contexts for SPI and UART stub mode (carried over from prior session)
- `.github/copilot-instructions.md` "Docs to Link" section references deleted files —
  needs update (INSTALL.md, QUICKSTART.md, PLATFORMS.md, ARCHITECTURE.md,
  REFERENCE/Cmdlets.md, REFERENCE/Classes.md, PERSONAS.md, HARDWARE_KIT.md all deleted)

## Next Actions

1. **Fix copilot-instructions.md** — update "Docs to Link Instead of Duplicating" section:
   - Remove refs to deleted files
   - Add `docs/README.md` as top-level entry point
   - Update architecture ref to `docs/wiki/Architecture.md` only
   - Update function ref to `docs/wiki/Function-Reference.md` only
   - Update classes ref to `docs/wiki/Classes.md` only
   - Keep `docs/TROUBLESHOOTING.md`, `docs/about_adafruit_ft232h.md`, workflow ref
2. **Fix version in tests** — `Tests/PsGadget.Tests.ps1`: change `0.4.0` -> `0.4.2`
3. **Add SPI stub tests** — new `Context 'SPI'` block:
   - `Invoke-PsGadgetSpi` is exported; write-only returns `$true`; read-only returns `[byte[]]`
4. **Add UART stub tests** — new `Context 'UART'` block:
   - `Invoke-PsGadgetUart` is exported; `-ReadLine` returns `$null` (stub); `-ReadCount 4` returns `[byte[]]`
5. Commit and push above changes
