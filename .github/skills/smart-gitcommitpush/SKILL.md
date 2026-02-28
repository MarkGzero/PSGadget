---
name: smart-gitcommitpush
description: Generate structured, risk-aware git commit messages optimized for PsGadgets and hardware-integrated PowerShell development, then push to origin.
---

## Objective

Generate commit messages that:

- Clearly explain what changed
- Explain why it changed
- Preserve architectural intent
- Surface risk when touching hardware, timing, or deterministic output
- Enable safe continuation in a new LLM session

Default to concise.

Expand automatically when changes affect:
- Hardware behavior
- Protocol logic
- Timing
- Pin mappings
- Deterministic output
- JSON/schema contracts
- Public interfaces

---

# Adaptive Modes

## Mode 1 — Standard Change (Default)

Use when change does NOT affect:
- Electrical behavior
- Protocol framing
- Timing
- Schema/output structure
- Public interface contracts

### Format

<type>(<scope>): <concise summary>

Intent:
Short explanation of purpose.

Changes:
- Specific modification 1
- Specific modification 2

Risks:
Low | Medium | High (brief justification)

Keep concise.

---

## Mode 2 — Contract / Hardware / Deterministic Impact (Expanded)

Use when change affects:
- GPIO direction or state
- Baud rate or clock speed
- Pin mappings
- Timing/delay logic
- JSON schema
- Output ordering
- External interfaces
- Configuration defaults
- EEPROM/preconfiguration assumptions

### Format

<type>(<scope>): <concise summary>

Intent:
Why this change was required.

Changes:
- Concrete modification 1
- Concrete modification 2
- Concrete modification 3

Behavioral Contracts:
- External interface changed? (Yes/No)
- Hardware behavior changed? (Yes/No)
- Deterministic output preserved? (Yes/No)
- Backward compatible? (Yes/No)

Compatibility:
- PS5.1 status
- FTDI / device impact (if relevant)

Migration:
- Requires configuration update? (Yes/No)
- Requires firmware update? (Yes/No)
- Requires data regeneration? (Yes/No)

Risks:
Explicit statement of breakage surface.

---

# Commit Type Rules

Allowed types only:

- feat
- fix
- refactor
- perf
- docs
- test
- chore
- schema
- breaking
- security

Use `breaking` only for incompatible changes.

---

# Writing Rules

1. No vague language:
   - update
   - improve
   - cleanup
   - misc changes

2. Always explain why.

3. If touching hardware or protocol logic, explicitly state whether:
   - Electrical behavior changed
   - Timing changed
   - Interface changed

4. If touching JSON or structured output:
   - State whether field names changed
   - State whether ordering changed
   - State whether deterministic guarantees remain intact

5. No conversational tone.
6. No emojis.
7. Output commit message only.

---

# Heuristic

If unsure whether impact is structural → expand.

Under-documentation is more dangerous than minor verbosity.

---

# Example — Standard Mode

refactor(buffer-logic): isolate write validation

Intent:
Prevent repeated bounds checking across command handlers.

Changes:
- Extract validation into internal helper
- Remove duplicate inline checks

Risks:
Low. No external behavior change.

---

# Example — Expanded Mode

feat(uart-config): change default baud rate

Intent:
Reduce latency during ESP32 communication.

Changes:
- Updated default baud constant
- Adjusted retry logic
- Updated initialization sequence

Behavioral Contracts:
- External interface changed? No
- Hardware behavior changed? Yes
- Deterministic output preserved? Yes
- Backward compatible? No (device must match baud)

Compatibility:
- PS5.1 compatible
- FT232H tested

Migration:
- Firmware update required? Yes
- Config update required? Yes
- Data regeneration required? No

Risks:
Incorrect baud configuration will prevent communication.

---

# Output Rules

When invoked:
- Output only the commit message
- No markdown fences
- No explanation
- Automatically choose concise or expanded mode