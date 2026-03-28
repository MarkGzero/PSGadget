# PSGadget Configuration Reference

## about_PsGadgetConfig

### TOPIC
PSGadget user configuration -- `~/.psgadget/config.json`

---

## Table of Contents

- [Short Description](#short-description)
- [Config File Location](#config-file-location)
- [Reading and Writing Settings](#reading-and-writing-settings)
- [Full Default Config File](#full-default-config-file)
- [Settings Reference](#settings-reference)
  - [Section: ftdi](#section-ftdi)
  - [Section: logging](#section-logging)
- [How Settings Interact with Explicit Parameters](#how-settings-interact-with-explicit-parameters)
- [Examples](#examples)
- [Config File Reset](#config-file-reset)
- [See Also](#see-also)

---

## SHORT DESCRIPTION

PSGadget reads a JSON configuration file at module import to apply user preferences
for FTDI device behavior, logging output, and other module-wide defaults.

The file is created automatically with default values on the first import. Edit it
with any text editor, or use `Set-PsGadgetConfig` from a PowerShell session.

---

## CONFIG FILE LOCATION

```
~/.psgadget/config.json
```

On Windows this resolves to `C:\Users\<YourName>\.psgadget\config.json`.

---

## READING AND WRITING SETTINGS

**View the current configuration:**

```powershell
Get-PsGadgetConfig
Get-PsGadgetConfig -Section ftdi
(Get-PsGadgetConfig).ftdi.highDriveIOs
```

**Change a setting:**

```powershell
Set-PsGadgetConfig -Key ftdi.highDriveIOs -Value $true
Set-PsGadgetConfig -Key logging.level     -Value DEBUG
```

The change takes effect immediately in the current session and is saved to
`config.json` for all future sessions.

---

## FULL DEFAULT CONFIG FILE

```json
{
  "ftdi": {
    "highDriveIOs": false,
    "pullDownEnable": false,
    "rIsD2XX": false
  },
  "logging": {
    "level": "INFO",
    "maxFileSizeMb": 10,
    "retainDays": 30
  }
}
```

---

## SETTINGS REFERENCE

### Section: `ftdi`

These settings apply as **defaults** when writing the FT232R EEPROM via
`Set-PsGadgetFt232rCbusMode`. They do not retroactively change the EEPROM of a
device that was already programmed. Run `Set-PsGadgetFt232rCbusMode` again after
changing an `ftdi.*` config value to propagate the change to the device.

You can always override a config default for a single call by supplying the
corresponding parameter explicitly on the command line.

---

#### `ftdi.highDriveIOs`

| Key | Type | Default |
|---|---|---|
| `ftdi.highDriveIOs` | boolean | `false` |

Doubles the CBUS (and all other) I/O pin drive strength from 4 mA to 8 mA.

**When to enable:**
- Driving LEDs directly from CBUS pins without a series transistor at full brightness
- Driving long traces or capacitive loads where the default 4 mA slew rate is too slow
- When 1k series resistors cause the LED to be too dim at 3.3V VCCIO

**When to leave disabled:**
- Power-constrained USB setups
- Applications sensitive to EMI (higher drive creates stronger switching transients)
- When using the recommended transistor driver circuit (4 mA is plenty to drive a base)

**How it is applied:**
Setting this to `true` causes `Set-PsGadgetFt232rCbusMode` to also write the
`HighDriveIOs` bit in the FT232R EEPROM. A USB replug or port cycle is required
for the change to take effect, same as a normal EEPROM write.

**Verify the current device setting:**

```powershell
(Get-PsGadgetFtdiEeprom -Index 0).HighDriveIOs
```

**Apply to a device:**

```powershell
Set-PsGadgetConfig -Key ftdi.highDriveIOs -Value $true
Set-PsGadgetFt232rCbusMode -Index 0          # picks up config value automatically
```

**Override for one call only (without changing config):**

```powershell
Set-PsGadgetFt232rCbusMode -Index 0 -HighDriveIOs $true   # explicit override
```

---

#### `ftdi.pullDownEnable`

| Key | Type | Default |
|---|---|---|
| `ftdi.pullDownEnable` | boolean | `false` |

Adds weak pull-down resistors on all UART and CBUS I/O pins during USB suspend.

**When to enable:**
- You want all GPIO pins (including CBUS) to go deterministically LOW when the host
  suspends the USB bus (e.g., to turn off LEDs or release a held motor or relay)
- Applications where floating pins during host sleep could trigger unintended behavior
  on attached hardware

**When to leave disabled:**
- When you need pins to hold their last driven state during suspend
- When the pull-down would fight against an external circuit that drives a pin HIGH
  while the host is asleep

**How it is applied:** same EEPROM write flow as `ftdi.highDriveIOs`.

---

#### `ftdi.rIsD2XX`

| Key | Type | Default |
|---|---|---|
| `ftdi.rIsD2XX` | boolean | `false` |

Sets the device's poweron default driver mode to D2XX instead of VCP (COM port).

**When to enable:**
- You only ever use PSGadget (D2XX) and never need the virtual COM port
- The duplicate COM port entry in `Get-FtdiDevice` is confusing or interfering
- CI/automation scenarios where COM port enumeration causes conflicts

**When to leave disabled:**
- You also use the FT232R as a serial port (Arduino flashing, terminal etc.)
- You need the VCP driver for other tools

**Effect on enumeration:**
With `rIsD2XX = false` (default), one physical device appears twice in
`Get-FtdiDevice`: once with driver `ftd2xx.dll` (D2XX, for PSGadget) and once
with driver `ftdibus.sys (VCP)` (with a COM port). With `rIsD2XX = true`, the device
enumerates only once, as a D2XX device, with no COM port.

**How it is applied:** same EEPROM write flow as `ftdi.highDriveIOs`.

---

### Section: `logging`

These settings control the PSGadget log files written to `~/.psgadget/logs/`.

---

#### `logging.level`

| Key | Type | Default | Valid values |
|---|---|---|---|
| `logging.level` | string | `"INFO"` | `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE` |

Minimum severity level that is written to log files. Messages below this level
are silently discarded. Levels in ascending verbosity order:

| Level | What is logged |
|---|---|
| `ERROR` | Unhandled exceptions and hard failures only |
| `WARN`  | Warnings plus errors |
| `INFO`  | Normal operations (connect, disconnect, EEPROM write, GPIO set) |
| `DEBUG` | Parameter values and internal state at key decision points |
| `TRACE` | Full flow tracing including every method entry and byte-level operations |

`INFO` is the recommended level for normal use. Use `DEBUG` when diagnosing a
problem. Use `TRACE` only when investigating bit-level hardware issues -- the
log files will grow quickly.

---

#### `logging.maxFileSizeMb`

| Key | Type | Default |
|---|---|---|
| `logging.maxFileSizeMb` | integer | `10` |

Maximum size in megabytes of a single log file before it is rotated. When a log
file reaches this size, it is renamed with a timestamp suffix and a new file is
started. Set lower for constrained disk environments; set higher if you need
longer continuous traces without interruption.

---

#### `logging.retainDays`

| Key | Type | Default |
|---|---|---|
| `logging.retainDays` | integer | `30` |

Number of days to retain rotated log files. Files older than this are deleted
automatically during the next module import. Set to `0` to disable automatic
cleanup. Set lower (e.g. `7`) on systems with limited storage.

---

## HOW SETTINGS INTERACT WITH EXPLICIT PARAMETERS

Config values are **defaults**. Any parameter you supply explicitly on a cmdlet
call overrides the config value for that call only -- the config file is not
changed.

Example: config has `ftdi.highDriveIOs = false`, but you want to test 8 mA on
one specific device without changing the default:

```powershell
Set-PsGadgetFt232rCbusMode -Index 2 -HighDriveIOs $true   # only this call
Set-PsGadgetFt232rCbusMode -Index 0                        # still uses config default (false)
```

---

## EXAMPLES

```powershell
# View all settings
Get-PsGadgetConfig | Format-List

# View only FTDI settings
Get-PsGadgetConfig -Section ftdi

# Enable high drive IOs for future EEPROM writes
Set-PsGadgetConfig -Key ftdi.highDriveIOs -Value $true

# Enable pull-downs on suspend
Set-PsGadgetConfig -Key ftdi.pullDownEnable -Value $true

# Remove duplicate COM port in Get-FtdiDevice
Set-PsGadgetConfig -Key ftdi.rIsD2XX -Value $true

# Then write EEPROM -- all three config settings are applied automatically
Set-PsGadgetFt232rCbusMode -Index 0

# Increase log detail for a debugging session
Set-PsGadgetConfig -Key logging.level -Value DEBUG

# Keep logs for one week only
Set-PsGadgetConfig -Key logging.retainDays -Value 7
```

---

## CONFIG FILE RESET

To reset all settings to defaults, delete the config file and reimport the module:

```powershell
Remove-Item "$([Environment]::GetFolderPath('UserProfile'))\.psgadget\config.json"
Import-Module PSGadget -Force
```

---

## SEE ALSO

- `Get-PsGadgetConfig`
- `Set-PsGadgetConfig`
- `Get-PsGadgetFtdiEeprom`
- `Set-PsGadgetFt232rCbusMode`
