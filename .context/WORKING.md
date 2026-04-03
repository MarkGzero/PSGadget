# Session Context — 2026-04-03T00:00:00Z

## Current Focus

macOS EEPROM read path for FT232R — partially working, word offset bug still unresolved.

## Current State

### Completed this session (commits on `main`):

- **`c5ec52a`** — `feat(eeprom)`: Added `Get-FtdiNativeFt232rEeprom` in `Ftdi.PInvoke.ps1`.
  Wired native P/Invoke path into `Get-FtdiFt232rEeprom` (macOS/Linux uses `FT_ReadEE` when
  `$script:FtdiNativeAvailable`). Added `Write-Warning` to `Get-FtdiFt232hEeprom` (no native
  path for FT232H). Fixed `.NOTES` in `Set-PsGadgetFt232rCbusMode.ps1` (write path is
  cross-platform when libftd2xx loaded). `_NativeRead=$true` marker on native reads.

- **`1a2752c`** — `fix(eeprom)`: Corrected FT232R CBUS EEPROM word offsets.
  Old constants `EE_WORD_CBUS01=7`, `EE_WORD_CBUS23=8` were wrong (those are config/string-pointer
  words). FT_Prog hex dump confirmed all CBUS0-3 live in a **single word at offset 0x0A (10)**,
  CBUS4 at 0x0B (11). Also fixed VID/PID offsets (word 1=VID, word 2=PID, NOT word 0).
  Fixed `Set-FtdiNativeCbusEeprom` and `Get-FtdiNativeCbusEepromInfo` with same layout.
  Also fixed non-ASCII chars (em-dashes, box-drawing) in `Install-MacOSD2XXDrivers.ps1`
  and `Ftdi.Unix.ps1` that caused `ParseException` on PS5.1.

- **`c9d08fa`** — `fix(enumeration)`: `Get-FtdiDevice` on PS5.1 crashed with
  `AccessViolationException` in `ReadFT232REEPROM`. Root cause: D2XX `GetDeviceList` leaves
  kernel handles open; subsequent `OpenByIndex` in EEPROM enrichment gets conflicted handle;
  uncatchable AVE kills process. Fix: gate EEPROM enrichment on `PSVersion.Major >= 6`.
  PS5.1 shows static CapabilityNote; directs user to `Get-FtdiEeprom -Index N`.

### Still broken / unresolved:

- **macOS EEPROM read returns wrong CBUS values.** After the offset fix, macOS still returns
  wrong values. Example: expected `Cbus0=FT_CBUS_TXLED` (word 0x0A = `0x1023`), got
  `FT_CBUS_TXDEN` x3 + `FT_CBUS_TXRXLED`. Symptom suggests macOS `FT_ReadEE` at offset 10
  is returning `0x4000` (= word 0 from dump) — as if the offset is being ignored or the
  device handle is already closed before the read. **Diagnostic needed: raw word dump.**

## Recent Decisions

### FT232R EEPROM word layout (verified from FT_Prog hex dump, device BG01X3AK)
```
Word  0 (0x00): 0x4000 — device type/config (NOT VendorID)
Word  1 (0x01): 0x0403 — VendorID (FTDI)
Word  2 (0x02): 0x6001 — ProductID (FT232R)
Word 10 (0x0A): bits[3:0]=CBUS0, bits[7:4]=CBUS1, bits[11:8]=CBUS2, bits[15:12]=CBUS3
Word 11 (0x0B): bits[3:0]=CBUS4
```
Factory default: word 0x0A = `0x1023` → CBUS0=TXLED(3), CBUS1=RXLED(2), CBUS2=TXDEN(0), CBUS3=PWREN(1)
After `Set-PsGadgetFt232rCbusMode`: CBUS0-3 all = IOMODE(10) → word 0x0A = `0xAAAA`

### EEPROM enrichment in Get-FtdiDeviceList
- PS6+: reads EEPROM live, stamps CBUS readiness into CapabilityNote
- PS5.1: skipped (AVE crash risk); static note only; `Get-FtdiEeprom` works standalone on PS5.1

### FT_ReadEE offset issue on macOS (unresolved)
- macOS `Get-FtdiEeprom -Index 0` returns wrong CBUS values despite correct offsets in code
- Hypothesis: `FT_ReadEE` on libftd2xx.dylib may have a different parameter type or
  the handle from `Invoke-FtdiNativeOpen` is already closed/invalid before reads
- **Next diagnostic: raw word dump** — run `FT_ReadEE` for words 0-15 and compare to FT_Prog hex

### EEPROM write path (Set-FtdiNativeCbusEeprom) — NOT YET TESTED on real hardware
- Do not use until read path is confirmed correct
- EEPROM writes are non-volatile; wrong offsets would corrupt device

### macOS test device
- MBP001 (Natalie-MBP / AdminMark), SSH accessible, PS 7.6.0 / .NET 10.0.5
- FT232R BG01X3AK — factory EEPROM (TXLED/RXLED/TXDEN/PWREN/SLEEP on CBUS0-4)
  Note: a prior Windows session had programmed CBUS0-3=IOMODE; device may have been
  reprogrammed back to factory. Confirm current state via `Get-FtdiEeprom -Index 0` on Windows.
- Local dev clone at /Users/AdminMark/psgadget

### Naming convention
- `Verb-Ftdi*` = no live connection required (discovery, EEPROM by index)
- `Verb-PsGadget*` = requires live `[PsGadgetFtdi]` object

## Active Files

| File | Status |
|------|--------|
| `Private/Ftdi.PInvoke.ps1` | Contains `Get-FtdiNativeFt232rEeprom`, `Get-FtdiNativeCbusEepromInfo`, `Set-FtdiNativeCbusEeprom` — read path has offset bug |
| `Private/Ftdi.Cbus.ps1` | `Get-FtdiFt232rEeprom` dispatches to native path on macOS |
| `Private/Ftdi.Backend.ps1` | EEPROM enrichment gated on PS6+ |

Working tree is clean (`git status` clean after `c9d08fa`).

## Key Constraints

- PowerShell 5.1+; no PS7-only operators (`?:`, `?.`, `??`); ASCII only in PS code/strings
- `Start-PsGadgetTrace` on Windows must use `Start-Process powershell` (not `pwsh`)
- Module load order in `PSGadget.psm1` is fixed (see copilot-instructions.md)
- Branch: `main` only
- Module version: `0.4.2` (PSGadget.psd1)
- FTD2XX_NET.dll is Windows-only; native P/Invoke path (libftd2xx) used on macOS/Linux
- `AccessViolationException` is uncatchable on .NET Framework (PS5.1) — never call EEPROM
  functions in the same D2XX session that called GetDeviceList

## Known Issues

### Critical
- **macOS `FT_ReadEE` returns wrong word data** — `Get-FtdiEeprom -Index 0` on macOS
  returns wrong CBUS values. Likely `FT_ReadEE` ignores the offset param or handle is invalid.
  Diagnostic command ready (see Next Actions).

### Pre-existing (carry-over)
- `Tests/PsGadget.Tests.ps1` version check still expects `0.4.0`; needs bump to `0.4.2`
- No SPI stub tests (`Context 'SPI'` block missing)
- No UART stub tests (`Context 'UART'` block missing)
- `.github/copilot-instructions.md` references deleted `docs/PERSONAS.md`
- `examples/psgadget_workflow.md` lists deprecated `Send-PsGadgetI2CWrite`

## Next Actions

### 1. IMMEDIATE — Diagnose macOS FT_ReadEE offset bug

Run this on MBP001 (SSH to AdminMark@MBP001, then `pwsh`, then `cd ~/psgadget`):

```powershell
Import-Module ./PSGadget.psm1 -Force

$handle = [IntPtr]::Zero
$s = [FtdiNative]::FT_Open(0, [ref]$handle)
"FT_Open: status=$s  handle=0x$($handle.ToString('X'))"

0..15 | ForEach-Object {
    [ushort]$w = 0
    $s = [FtdiNative]::FT_ReadEE($handle, [uint32]$_, [ref]$w)
    "Word {0:D2} (0x{0:X2}):  status={1}  value=0x{2:X4}" -f $_, $s, $w
}

[FtdiNative]::FT_Close($handle) | Out-Null
```

Compare output against FT_Prog hex dump:
- Row `0x0000`: `4000 0403 6001 0000 2DA0 0008 0000 0A98`
- Row `0x0008`: `20A2 12C2 1023 0005 030A 0046 0054 0044`
- Word 0x0A (index 10) should be `0x1023` (factory) or `0xAAAA` (if IOMODE was programmed)

If all words return `0x4000` (word 0 value), `FT_ReadEE` is not advancing offset →
the `[uint32]` WordOffset type may be wrong for libftd2xx.dylib on macOS (try `[uint]` or `[int]`).

### 2. Fix FT_ReadEE parameter type in C# DllImport if needed

In `Ftdi.PInvoke.ps1` C# class — current declaration:
```csharp
[DllImport("...", EntryPoint = "FT_ReadEE")]
public static extern int FT_ReadEE(IntPtr ftHandle, uint dwWordOffset, out ushort lpwValue);
```
If offset is being ignored, try `UInt32` vs `int` vs `DWORD` alias issues on macOS ABI.

### 3. After read path confirmed — test write path on Mac

```powershell
# Verify read first, then:
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0,1,2) -WhatIf  # preview
Set-PsGadgetFt232rCbusMode -Index 0 -Pins @(0,1,2)           # write IOMODE
# Replug device, then:
Get-FtdiEeprom -Index 0 | Select-Object Cbus0, Cbus1, Cbus2  # verify
```

### 4. After macOS EEPROM is working — pre-existing cleanup

- Fix `Tests/PsGadget.Tests.ps1`: `0.4.0` → `0.4.2`
- Add `Context 'SPI'` and `Context 'UART'` stub test blocks
- Fix `copilot-instructions.md` PERSONAS.md ref
- Remove `Send-PsGadgetI2CWrite` from `examples/psgadget_workflow.md`
