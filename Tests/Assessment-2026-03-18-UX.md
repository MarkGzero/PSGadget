# PSGadget UX Assessment — 2026-03-18

Simulated user: Jordan, senior PowerShell scripter, no hardware background.
Assessment method: test-as-user skill (SKILL.md), walking realistic first-day workflow.

---

## Table of Contents

- [Persona](#persona)
- [Workflow Summary](#workflow-summary)
- [Critical -- Flow Blockers](#critical----flow-blockers)
- [High -- Dead Ends](#high----dead-ends)
- [Medium -- Friction](#medium----friction)
- [Low -- Polish](#low----polish)
- [What Works Well](#what-works-well)
- [Fix Plan (Reference)](#fix-plan-reference)

---

## Persona

Jordan, senior PowerShell scripter at a university research lab. Writes automation
daily; knows modules, pipelines, objects. Has never touched GPIO, I2C, or USB
hardware buses. Received an FTDI kit. Monday morning goal: blink an LED, then drive
an OLED display. Opened PSGadget from a GitHub link.

---

## Workflow Summary

Jordan follows README -> Getting-Started -> beginner example -> Function-Reference.
The first-time device discovery and GPIO path on FT232H is smooth once the module
is loaded. The afternoon SSD1306 session hits a complete dead end when following
the Function-Reference.

---

## Critical -- Flow Blockers

### [Critical] Beginner install command references a non-existent PSGallery package

- **Workflow step**: `examples/beginner/Example-BlinkLed.md` -- "What You Need / Software"
- **Observed behavior**: `Install-Module PSGadget -Scope CurrentUser` fails. PSGadget is
  not on PSGallery; installation requires `git clone` then `Import-Module ./PSGadget.psd1`.
  Getting-Started documents the correct path but a beginner starting from the example
  file never reads it.
- **User impact**: Complete stop at step 1 with a package-manager error and no recovery
  path inside the document.
- **Suggested fix**: Replace the `Install-Module` line with:
  "PSGadget installed -- see [Getting Started](../../docs/wiki/Getting-Started.md) for
  clone and import instructions."

---

## High -- Dead Ends

### [High] Four SSD1306 cmdlets in Function-Reference do not exist

- **Workflow step**: `docs/wiki/Function-Reference.md` -- reading
  "Connection > Connect-PsGadgetSsd1306" and "SSD1306 Display", then calling any of
  the four names.
- **Observed behavior**: `Connect-PsGadgetSsd1306`, `Write-PsGadgetSsd1306`,
  `Clear-PsGadgetSsd1306`, and `Set-PsGadgetSsd1306Cursor` are all documented with
  full parameter tables and code examples. None have a corresponding file in `Public/`.
  None appear in `PSGadget.psd1` `FunctionsToExport`. All four produce
  "is not recognized as a cmdlet" at runtime. The working API is
  `$dev.GetDisplay()` -> `.ShowSplash()` / `.WriteText()` / `.FlushAll()`, or
  `Invoke-PsGadgetI2C -I2CModule SSD1306`.
- **User impact**: Any user treating Function-Reference as the primary guide (the
  normal expectation) is completely blocked on SSD1306. The phantom entries also appear
  in the Function-Reference TOC, engineer examples (`examples/engineer/Example-I2CScan.md`),
  Architecture, and Classes docs -- multiplying the confusion.
- **Suggested fix**: Either (a) create the four functions in `Public/` and export them,
  wrapping the existing class methods, or (b) remove the four entries from
  Function-Reference and replace with the actual working interface. Option (b) is a
  docs-only fix.

### [High] `Get-PsGadgetLog` is exported but has no Function-Reference entry

- **Workflow step**: After a hardware error, Jordan wants to inspect module logs.
- **Observed behavior**: `Get-PsGadgetLog` is in `FunctionsToExport`, has a documented
  `Public/Get-PsGadgetLog.ps1` with `-Tail`, `-List`, `-Follow` parameters, and appears
  in `Get-Command -Module PSGadget`. The Diagnostics section of Function-Reference only
  documents `Test-PsGadgetEnvironment`.
- **User impact**: Logs are the primary debugging tool. Users have no documented path to
  them; discovery requires scanning `Get-Command` output, which most beginners and
  scripters will not think to do.
- **Suggested fix**: Add a `Get-PsGadgetLog` section to Function-Reference under
  Diagnostics with its three switches and a usage example.

---

## Medium -- Friction

### [Medium] `Test-PsGadgetEnvironment` Status value described differently in three docs

- **Workflow step**: Writing a scriptable health-check guard from Getting-Started or
  Function-Reference.
- **Observed behavior**:
  - Console prints `Status    : READY` (via Write-Host, using internal `$statusLabel`)
  - Return object property `.Status` is `'OK'` or `'Fail'`
  - Getting-Started says "Look for `Status : READY`... If it says `Fail`" -- mixing
    the console label with the object property
  - Function-Reference says the property is `'OK' or 'NOT READY'` -- `'NOT READY'` is
    never set by the code
  - Only `docs/REFERENCE/Cmdlets.md` correctly states `'OK'` or `'Fail'`
- **User impact**: A scripter writing `if ($result.Status -ne 'READY')` based on
  Getting-Started has a guard that never fires on failure. The Function-Reference typo
  (`'NOT READY'`) misleads anyone who hard-codes equality tests.
- **Suggested fix**:
  - In Getting-Started: change "Look for `Status : READY`" to "The console prints
    `Status    : READY`. To check programmatically, test `$result.Status -ne 'OK'`."
  - In Function-Reference: fix the table entry to `'OK' or 'Fail'`.

### [Medium] Troubleshooting link in beginner example leads to a dead redirect stub

- **Workflow step**: Hitting a module-import error in `examples/beginner/Example-BlinkLed.md`
  and clicking the troubleshooting link.
- **Observed behavior**: The link resolves to `docs/TROUBLESHOOTING.md`, which says only
  "Moved to wiki" with a plain-text list of filenames -- not clickable links from that
  relative path.
- **User impact**: A beginner at their most frustrated moment is sent into another dead end.
- **Suggested fix**: Change the link in `Example-BlinkLed.md` to point to
  `../../docs/wiki/Troubleshooting.md`.

### [Medium] Stepper "What You Need" section mis-states FT232H pin group

- **Workflow step**: Reading the prerequisites in `examples/Example-StepperMotor.md`
  before wiring.
- **Observed behavior**: The paragraph reads "For FT232H (or any MPSSE device) use
  CBUS0-3 instead." The immediately following wiring table correctly shows ADBUS D4-D7.
  The text contradicts the table.
- **User impact**: An engineer scanning the "What You Need" summary for wiring points
  may wire CBUS pins and get no output before discovering the table.
- **Suggested fix**: Change the sentence to "For FT232H (or any MPSSE device), use
  **ADBUS D4-D7**; no EEPROM programming is required."

---

## Low -- Polish

### [Low] README Quick Start and all other docs use different names for the same command

- **Workflow step**: Running first commands after import.
- **Observed behavior**: README uses `Get-FtdiDevice` (the primary export name). Every
  other document -- Getting-Started, workflow, examples, Function-Reference -- uses
  `Get-FtdiDevice` (the alias). Both work; the inconsistency causes momentary
  confusion about whether the two commands differ.
- **Suggested fix**: Standardize the README Quick Start on `Get-FtdiDevice`, or add
  a note: "`Get-FtdiDevice` (alias: `Get-FtdiDevice`)".

---

## What Works Well

The core GPIO path (clone -> import -> `Test-PsGadgetEnvironment` -> `Get-FtdiDevice`
-> `New-PsGadgetFtdi` -> `SetPin`) is clean and well-guided end-to-end. The FT232R
EEPROM workflow (5-step format with WhatIf, dual-driver explanation, CBUS4 footnote) is
thorough and correct. The multi-persona callout pattern in examples genuinely serves all
four user types. The `PsGadgetFtdi` OOP method surface (`SetPin`, `PulsePin`, `Close`)
is idiomatic and discoverable in the REPL.

---

## Fix Plan (Reference)

### Decisions

- SSD1306 documentation issue fixed as docs-only: remove phantom cmdlets from the reference and document the real API.
- Get-FtdiDevice remains the primary function name. Get-FtdiDevice is documented as an alias.

### Phase 1 (Critical + High)

1. Update `examples/beginner/Example-BlinkLed.md`
  - Replace Install-Module PSGadget instruction with a Getting Started clone/import link.
  - Fix troubleshooting link from docs/TROUBLESHOOTING.md to docs/wiki/Troubleshooting.md.
  - Clarify status wording: console label READY vs object property values OK/Fail.

2. Update `docs/wiki/Function-Reference.md`
  - Remove phantom SSD1306 cmdlets from TOC and body:
    Connect-PsGadgetSsd1306, Write-PsGadgetSsd1306, Clear-PsGadgetSsd1306, Set-PsGadgetSsd1306Cursor.
  - Replace SSD1306 section with real supported usage:
    PsGadgetFtdi.GetDisplay methods and Invoke-PsGadgetI2C -I2CModule SSD1306.
  - Add Get-PsGadgetLog to Diagnostics TOC and section content.
  - Fix Status property text from OK/NOT READY to OK/Fail.
  - Add alias note clarifying Get-FtdiDevice and Get-FtdiDevice.

### Phase 2 (Medium)

3. Update `examples/Example-StepperMotor.md`
  - Correct FT232H wiring text from CBUS0-3 to ADBUS D4-D7.

### Verification

1. Confirm no references remain to phantom SSD1306 cmdlets in Function-Reference.
2. Confirm Get-PsGadgetLog appears in Diagnostics TOC and section.
3. Confirm beginner troubleshooting link opens wiki Troubleshooting page.
4. Confirm beginner install text points to clone/import workflow.
5. Confirm stepper FT232H text says ADBUS D4-D7.
6. Confirm status guidance consistently uses OK/Fail for object property checks.
