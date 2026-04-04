# Session Context — 2026-04-04T12:00:00Z

## Current Focus

macOS IoT backend support — GPIO read (`readPins`) + Stepper motor (`IoT` GpioMethod path).
All three changes implemented and deployed to MBP001 but **not yet committed**.

## Current State

### Completed (deployed, uncommitted):
- `Private/Ftdi.IoT.ps1` — Added `Get-FtdiIotGpioPins` function (reads ACBUS pins via IoT GpioController)
- `Public/Get-PsGadgetGpio.ps1` — Added `'IoT'` case to GpioMethod switch
- `Private/Stepper.Backend.ps1` — Added `elseif ($gpioMethod -eq 'IoT')` branch (ACBUS0-3, IoT pins 8-11)

### Previously committed (this session):
- `cceadca` — Full EEPROM read for FT232R and FT232H on macOS via FT_EE_Read
- `941f31c` — Restore EEPROM CapabilityNote on Windows PS5.1
- `587ba42` — Full FT_PROGRAM_DATA struct for macOS; blank-EEPROM write fix on PS5.1

## Recent Decisions

### macOS IoT GPIO read — Get-FtdiIotGpioPins (Ftdi.IoT.ps1)
Added after `Set-FtdiIotGpioPins`. Reads all 8 ACBUS pins (IoT controller pins 8-15).
Opens unopen pins as Input before reading. Returns a byte where bit N = state of ACBUS pin N.
Logging via `$script:PsGadgetLogger.WriteProto('GPIO.READ', ...)`.

### Get-PsGadgetGpio IoT case
Third case in switch after CBUS and MPSSE. Guards on `$Connection.GpioController` presence.

### Stepper IoT path (Stepper.Backend.ps1)
Three-way dispatch: MPSSE → IoT → AsyncBitBang.
IoT path: opens ACBUS0-3 (IoT pins 8-11) as Output once, then tight Stopwatch spin-wait loop
mirroring the MPSSE path. De-energizes all 4 coil pins after move completes.
**macOS wiring requirement**: stepper coils must connect to ACBUS0-3 (C0-C3), NOT ADBUS
(ADBUS = MPSSE protocol bus on FT232H, IoT pins 0-7).

### SSD1306 and PCA9685 servo — no changes needed
Both already platform-agnostic via `PsGadgetI2CDevice.I2CWrite()` which has built-in
IoT/MPSSE branching. Hardware-verified working on macOS.

## Active Files

| File | Change | Status |
|------|--------|--------|
| `Private/Ftdi.IoT.ps1` | Add `Get-FtdiIotGpioPins` | Deployed, uncommitted |
| `Public/Get-PsGadgetGpio.ps1` | Add `'IoT'` case to switch | Deployed, uncommitted |
| `Private/Stepper.Backend.ps1` | Add IoT elseif branch | Deployed, uncommitted |

## Key Constraints

- PS 5.1+; no PS7-only operators (`?:`, `?.`, `??`); ASCII only in PS code/strings
- `FTD2XX_NET.dll` Windows-only; native P/Invoke (libftd2xx) for macOS/Linux
- `FT_CyclePort` Windows-only
- `FT_EraseEE` must never be called on FT232R (internal EEPROM, cannot be erased)
- `AccessViolationException` uncatchable on .NET Framework (PS5.1)
- Module load order in `PSGadget.psm1` is fixed
- Only D2XX (libftd2xx / FTD2XX_NET) or dotnet IoT (`Iot.Device.*`) — no other libraries
- IoT ACBUS pin mapping: ACBUS N → IoT GpioController pin N+8 (ACBUS0=pin8...ACBUS7=pin15)
- ADBUS (IoT pins 0-7) = MPSSE bus, not available for general GPIO

## Devices

- **BG01X3AK** — Windows FT232R, IOMODE confirmed
- **BG01B7VJ** — Mac FT232R, IOMODE confirmed
- **BG01B1EI** — Mac FT232R, IOMODE confirmed
- **FT9ZLJ51** — FT232H (Windows + Mac), MPSSE / IoT backend

## Known Issues

None critical. Pre-existing cleanup items:

1. `Tests/PsGadget.Tests.ps1` version check expects `0.4.0` — needs bump to `0.4.2`
2. No SPI/UART stub tests
3. `.github/copilot-instructions.md` references deleted `docs/PERSONAS.md`
4. `examples/psgadget_workflow.md` lists deprecated `Send-PsGadgetI2CWrite`
5. Module version still `0.4.2` — consider bumping to `0.4.3` after cleanup
6. `.context/WORKING.md` excluded by `.gitignore` — cannot be committed without `-f`

## Next Actions

**Immediate:**
1. `/smart-gitcommit` — commit the 3 changed files (IoT GPIO read + Stepper IoT path)
2. Verify on Mac: `$ft.setPins(@(2),1); $ft.readPins(@(0,1,2))` — expect `False, False, True`

**Cleanup (Option A, in priority order):**
1. Fix test version check — `Tests/PsGadget.Tests.ps1`: `0.4.0` → `0.4.2`
2. Add stub tests — `Context 'SPI'` and `Context 'UART'` blocks
3. Fix PERSONAS.md ref — `.github/copilot-instructions.md`
4. Remove deprecated API — `examples/psgadget_workflow.md`
5. Bump module version — `0.4.2` → `0.4.3`

**Option B:** Git history squash (user expressed interest, needs confirmation before starting)

**Option C:** Untracked files suggest upcoming Summit demo:
- `Tools/BitmapFontGlyphs.ps1`, `Tools/Start-BitmapVisualizer.ps1`, `examples/summit/`

## SSH / Deploy

- SSH key: `C:\Users\mark\.ssh\mbp001_id` → MBP001 (`AdminMark@192.168.25.100`)
- Deploy: `pwsh -File ./Tools/Deploy-ToMac.ps1 -Reload -File <rel-path>`
- Mac pwsh: `/usr/local/bin/pwsh`; Mac module: `/Users/AdminMark/psgadget/PSGadget.psm1`
