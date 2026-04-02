# Test-As-User Results

This file records UX simulation findings produced by the `/test-as-user` skill.
Each run targets a specific persona and feature area. Findings that have been
resolved are marked **FIXED** with the fix location.

---

## Run 2 — 2026-03-30 — SPI and UART (v0.4.2)

### Persona

Jordan, automation scripter at a hardware test lab. Comfortable with PowerShell,
understands serial protocols at a conceptual level. Just upgraded to PSGadget
v0.4.2, wants to read a SPI ADC periodically and poll a UART sensor. Has an
FT232H on the bench.

### What Works Well

- `Get-Help Invoke-PsGadgetSpi -Full` and `Get-Help Invoke-PsGadgetUart -Full` are
  thorough: 5-6 examples each, wire guide in NOTES, clear MPSSE-only SPI constraint.
- Auto-close behavior (`-PsGadget` reuse vs. auto open/close) is well-designed.
- SPI mode table (CPOL/CPHA) in cmdlet help is clear and correct.
- UART's separate `-LineTimeout` vs `-ReadTimeout` parameters prevent a common
  "wrong timeout" mistake.
- Unified log file eliminates per-device log confusion from older versions.

### Findings

#### High — Dead Ends

**[High] SPI and UART had no workflow section in `psgadget_workflow.md`** — FIXED
- Workflow step: Arrival — Jordan opens the primary reference to find the new protocol commands
- Observed: No SPI or UART (generic) section in the workflow file
- Fix: Added "SPI Workflow (FT232H via MPSSE)" and "UART Workflow (FT232H and FT232R)"
  sections to [examples/psgadget_workflow.md](psgadget_workflow.md)

**[High] `Start-PsGadgetTrace` "must be called first" constraint was undocumented** — FIXED
- Workflow step: Debugging — Jordan calls `Start-PsGadgetTrace` after a command, sees no
  PROTO output, concludes tracing is broken
- Fix: Added a callout box in [docs/wiki/Logging.md](../docs/wiki/Logging.md) under
  "Protocol tracing": "Call `Start-PsGadgetTrace` before connecting or running any protocol
  commands. Enabling tracing mid-session does not retroactively capture past operations."

#### Medium — Friction

**[Medium] `Invoke-PsGadgetUart -ReadLine` returned `""` on timeout** — FIXED
- Workflow step: Action — Jordan could not distinguish a 2-second timeout from a device that
  sent an empty line
- Fix: `Invoke-FtdiUartReadLine` in [Private/Ftdi.Uart.ps1](../Private/Ftdi.Uart.ps1) now
  tracks a `$gotNewline` flag. Returns `$null` on timeout; returns `""` only when a bare `\n`
  was actually received. Return type on `PsGadgetUart.ReadLine()` changed from `[string]` to
  `[object]` to allow `$null` through PS5.1 type coercion.

**[Medium] Logging.md color table was missing SPI and UART subsystems** — FIXED
- Workflow step: Debugging — Jordan sees `SPI.WRITE` in the trace window but can't confirm
  the color is intentional
- Fix: Added `SPI.INIT`, `SPI.WRITE`, `SPI.READ`, `SPI.XFER` (Blue) and `UART.TX`,
  `UART.RX`, `UART.FLUSH` (DarkYellow) to the subsystem color table in
  [docs/wiki/Logging.md](../docs/wiki/Logging.md)

**[Medium] No polling loop example for SPI or UART** — FIXED
- Workflow step: Action — Jordan opens/closes device each iteration, adding latency and log noise
- Fix: Added a `while ($true)` + `-PsGadget` reuse example to both
  [Public/Invoke-PsGadgetSpi.ps1](../Public/Invoke-PsGadgetSpi.ps1) and
  [Public/Invoke-PsGadgetUart.ps1](../Public/Invoke-PsGadgetUart.ps1)

**[Medium] `Invoke-PsGadgetSpi` write-only return type flip (`bool` vs `byte[]`)** — DOCUMENTED
- Workflow step: Action — Jordan pipes write-only result expecting bytes, gets `$true` cast to 1
- Fix: Updated `.OUTPUTS` section in [Public/Invoke-PsGadgetSpi.ps1](../Public/Invoke-PsGadgetSpi.ps1)
  with explicit note: "To suppress the bool from the pipeline use `[void]`: `[void](Invoke-PsGadgetSpi ...)`"
  Also noted in the SPI workflow section in psgadget_workflow.md.

#### Low — Polish

**[Low] Device Capability Comparison table didn't link SPI to its cmdlet** — FIXED
- Fix: Updated the "SPI / I2C / JTAG" row in the table to include cmdlet names
  (`Invoke-PsGadgetSpi`, `Invoke-PsGadgetI2C`) in [examples/psgadget_workflow.md](psgadget_workflow.md)

**[Low] UART and SPI wire guides only existed in cmdlet `.NOTES`** — FIXED
- Fix: Both new workflow sections in [examples/psgadget_workflow.md](psgadget_workflow.md)
  include a Hardware Wiring table with pin-to-signal mapping

**[Low] `Invoke-PsGadgetSpi` and `Invoke-PsGadgetUart` missing from Quick Reference table** — FIXED
- Fix: Both cmdlets added to the Public Function Quick Reference table in
  [examples/psgadget_workflow.md](psgadget_workflow.md)

---

## Run 1 — 2026-03-29 — GPIO and I2C (v0.4.0)

### Persona

Jordan, automation scripter at a hardware test lab. Today's task: detect connected
FTDI devices, verify environment health, run one GPIO action, and confirm SSD1306 output.

### What Works Well

- Core daily path is achievable with existing commands and docs.
- FT232R one-time EEPROM configuration is documented more clearly than typical FTDI toolchains.
- Troubleshooting content is substantial and practical.

### Findings

**[High] No single daily health command pattern** — PARTIALLY ADDRESSED
- Suggested fix: Add a "Daily Sanity Check" block to Getting-Started.md

**[High] Discovery path relies on prior FTDI driver model knowledge**
- Suggested fix: Add a "Use this row" rule under the first Get-FtdiDevice example

**[Medium] Arrival friction from documentation split and redirects**
- Suggested fix: Add a prominent "start here" pointer near the top of README.md

**[Medium] Troubleshooting is comprehensive but not prioritized**
- Suggested fix: Add a "Top 5 first checks" section at the top of Troubleshooting.md

**[Low] Re-entry workflow lacks a concise "yesterday to today" checklist**
- Suggested fix: Add a "Returning user 60-second check" in Getting-Started.md
