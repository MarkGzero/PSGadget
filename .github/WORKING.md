# Session Context - 2026-03-13T00:00:00Z

## Current Session Overview
- **Main Task/Feature**: ARCHITECTURE.md performance tier documentation + MPSSE byte command reference
- **Session Duration**: Single session, multiple iterations
- **Current Status**: Performance tiers section fully written and corrected in ARCHITECTURE.md. About to create MPSSE byte command reference doc using FTDI PDF notes in docs/ftdi_pdf2text_notes/.

## Recent Activity (Last 30-60 minutes)
- **What We Just Did**:
  - Added `## Performance tiers` section to docs/ARCHITECTURE.md with 8 tiers (0-7)
  - Corrected tier ordering (0=fastest/hardware, 7=slowest/full-open-close)
  - Added `Accessible from` column to tier table (Tiers 3,4 are module-source-only, not user-accessible)
  - Added private-function blockquote warnings to Tier 3 and Tier 4 sections
  - Added missing `---` separator before `## Design rules`
  - Added Tier 0 example using `Set-PsGadgetFtdiMode -Mode MpsseI2c` + `Send-PsGadgetI2CWrite`
  - Fixed `$dev._connection.device` -> `$dev._connection.Device` (capital D) in Tier 1 and 2 examples
  - Fixed Tier 4 timing note: Get-FtdiGpioPins uses AcbusCachedState after first write, not always a live USB read
  - Fixed Tier 0 text: replaced private `Send-MpsseI2CWrite` reference with public `Send-PsGadgetI2CWrite`
  - Minor fix in Ftdi.Mpsse.ps1 (cosmetic)
- **Active Problems**: None blocking
- **Current Files**: docs/ARCHITECTURE.md (modified), Private/Ftdi.Mpsse.ps1 (minor)
- **Test Status**: No tests run; documentation-only changes

## Key Technical Decisions Made
- **Tier numbering**: 0=fastest (MPSSE chip silicon), 7=slowest (full open/close per call); lower = fewer layers
- **Private function visibility**: Tiers 3 and 4 use private functions (Set-FtdiGpioPins, Send-MpsseAcbusCommand); explicitly marked as contributor-only in the docs
- **Raw .NET access path**: User scripts access Tiers 1 and 2 via `$dev._connection.Device` (FTD2XX_NET.FTDI)
- **AcbusCachedState**: Get-FtdiGpioPins returns cached value after any Send-MpsseAcbusCommand write; only first-ever read is a live USB round-trip
- **Tier 0 example**: PCA9685 servo board over I2C is the canonical example (PS sends register write, chip handles PWM)

## Code Context
- **Modified Files**:
  - `docs/ARCHITECTURE.md` -- +204 lines, Performance tiers section
  - `Private/Ftdi.Mpsse.ps1` -- minor cosmetic fix
- **New Patterns**: None
- **Dependencies**: None added
- **Configuration Changes**: None

## Current Implementation State
- **Completed**: Performance tiers section in ARCHITECTURE.md
- **In Progress**: MPSSE byte command reference (next task)
- **Blocked**: Nothing
- **Next Steps**:
  1. Read docs/ftdi_pdf2text_notes/AN_108_Command_Processor_for_MPSSE_and_MCU_Host_Bus_Emulation_Modes.txt
  2. Read docs/ftdi_pdf2text_notes/DS_FT232H.txt for pin maps
  3. Create docs/REFERENCE/MPSSE_Command_Reference.md -- print-friendly, all byte commands used in this module plus full opcode table from AN_108
  4. Cross-reference every opcode used in Private/Ftdi.Mpsse.ps1 with the new reference doc

## Important Context for Handoff
- **Environment**: Linux (WSL Ubuntu 24.04), PowerShell available. Repo at /home/botmanager/psgadget, branch dev1.
- **Running/Testing**: `pwsh -c "Import-Module ./PSGadget.psd1 -Force; Test-PsGadgetEnvironment"` and `Invoke-Pester ./Tests/PsGadget.Tests.ps1`
- **Known Issues**: None introduced this session
- **External Dependencies**: docs/ftdi_pdf2text_notes/ contains OCR-processed FTDI application notes (AN_108, DS_FT232H, etc.) -- PRIMARY SOURCE for MPSSE command reference

## Conversation Thread
- **Original Goal**: Understand the abstraction layers between PowerShell and FTDI hardware
- **Evolution**: Grew from layer explanation -> performance tier table -> byte command reference
- **Lessons Learned**:
  - Private functions are invisible outside the module; tier documentation must clearly mark this
  - AcbusCachedState eliminates USB read-modify-write overhead after first write
  - Windows USB frame = 1 ms floor; software PWM max ~500 Hz from PS
  - Batched MPSSE buffer (Tier 2) is the right approach for stepper/servo sequences
- **Alternatives Considered**: Separate performance doc vs. inline in ARCHITECTURE.md -- chose inline

## MPSSE Opcodes Already Used in Private/Ftdi.Mpsse.ps1
| Opcode | Usage in code |
|--------|--------------|
| 0x80   | Set ADBUS low byte (SCL/SDA I2C pins, value + direction) |
| 0x81   | Read ADBUS low byte (capture ACK bit, bit 1 = SDA) |
| 0x82   | Set ACBUS high byte (GPIO value + direction) |
| 0x83   | Read ACBUS high byte (read GPIO state) |
| 0x85   | Disable loopback |
| 0x86   | Set clock divisor (2 bytes: low, high) |
| 0x87   | Send Immediate (flush MPSSE buffer to host) |
| 0x8A   | Disable clock divide-by-5 (use 60 MHz base) |
| 0x8D   | Disable 3-phase data clocking |
| 0x97   | Disable adaptive clocking |
| 0x1B   | Clock bytes out on falling edge, MSB first (data-shifting) |
