# PSGadget Configuration

PSGadget reads a JSON configuration file at module import to apply user preferences
for FTDI hardware behavior, logging, and other module-wide defaults.

The file is created automatically with safe defaults on the first import.

---

## Config File Location

```
~/.psgadget/config.json
```

On Windows: `C:\Users\<YourName>\.psgadget\config.json`

---

## Reading the Configuration

```powershell
# Full config as an object
Get-PsGadgetConfig

# Readable list format
Get-PsGadgetConfig | Format-List

# FTDI section only
Get-PsGadgetConfig -Section ftdi

# Single value
(Get-PsGadgetConfig).ftdi.highDriveIOs
(Get-PsGadgetConfig).logging.level
```

---

## Changing Settings

```powershell
Set-PsGadgetConfig -Key <section>.<name> -Value <value>
```

The change takes effect immediately in the current session and is persisted to
`config.json` for all future sessions. No module reload needed.

```powershell
Set-PsGadgetConfig -Key ftdi.highDriveIOs  -Value $true
Set-PsGadgetConfig -Key ftdi.rIsD2XX       -Value $true
Set-PsGadgetConfig -Key logging.level      -Value DEBUG
Set-PsGadgetConfig -Key logging.retainDays -Value 7
```

---

## Default Config File

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

## Settings Reference

### Section: `ftdi`

These settings feed into `Set-PsGadgetFt232rCbusMode` as defaults when writing
the FT232R EEPROM. They don't retroactively change a device that was already
programmed. If you change one of these, run `Set-PsGadgetFt232rCbusMode` again
to push the new value to the device.

You can always override a config default for a single call by supplying the
matching parameter explicitly on the command line.

---

#### `ftdi.highDriveIOs`

| Type | Default |
|------|---------|
| bool | `false` |

Doubles CBUS (and all other I/O) pin drive strength from 4 mA to 8 mA.

**Enable when:**
- Driving LEDs directly from CBUS pins without a series transistor
- Driving long traces or capacitive loads where 4 mA slew rate is too slow
- 1k series resistors make the LED too dim at 3.3V

**Leave disabled when:**
- Using the recommended transistor driver circuit (4 mA is plenty for a base)
- In power-constrained setups, or applications sensitive to EMI

**Verify current device value:**
```powershell
(Get-PsGadgetFtdiEeprom -Index 0).HighDriveIOs
```

---

#### `ftdi.pullDownEnable`

| Type | Default |
|------|---------|
| bool | `false` |

Adds weak pull-down resistors on all UART and CBUS I/O pins during USB suspend.

**Enable when:**
- You need GPIO pins to go LOW deterministically when the host suspends USB
  (e.g., turn off LEDs or release a relay when the PC sleeps)
- Floating pins during host sleep could trigger unintended behavior on hardware

**Leave disabled when:**
- Pins should hold their last driven state during suspend
- An external circuit drives a pin HIGH during host sleep (pull-down would fight it)

---

#### `ftdi.rIsD2XX`

| Type | Default |
|------|---------|
| bool | `false` |

Sets the device's power-on default to D2XX-only, eliminating the duplicate VCP
(COM port) enumeration entry.

**Enable when:**
- You only use PSGadget (D2XX) and never need the COM port
- The duplicate VCP entry in `Get-FTDevice` is confusing or causing conflicts
- CI/automation scenarios where COM port enumeration is undesirable

**Leave disabled when:**
- You also use the FT232R as a serial port with tools like PuTTY or Arduino IDE

**Effect on `Get-FTDevice`:**
With `false` (default), one physical device appears twice: once as `ftd2xx.dll`
(D2XX) and once as `ftdibus.sys (VCP)` with a COM port. With `true`, it appears
only once, as D2XX, with no COM port entry.

---

### Section: `logging`

Controls log files written to `~/.psgadget/logs/`.

---

#### `logging.level`

| Type | Default | Valid values |
|------|---------|--------------|
| string | `"INFO"` | `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE` |

Minimum severity that is written to log files. Messages below this level are
discarded silently.

| Level | What is logged |
|-------|----------------|
| ERROR | Hard failures and unhandled exceptions only |
| WARN | Warnings plus errors |
| INFO | Normal operations: connect, disconnect, EEPROM write, GPIO set |
| DEBUG | Parameter values and internal state at key decisions |
| TRACE | Full flow including every method entry and byte-level operations |

Use `INFO` for normal operation. Switch to `DEBUG` when diagnosing a problem.
`TRACE` fills logs quickly -- use only for hardware-level investigation.

---

#### `logging.maxFileSizeMb`

| Type | Default |
|------|---------|
| int | `10` |

Maximum size in MB of a single log file before rotation. When reached, the file
is renamed with a timestamp suffix and a new file starts.

---

#### `logging.retainDays`

| Type | Default |
|------|---------|
| int | `30` |

Number of days to keep rotated log files. Files older than this are deleted
automatically on the next module import. Set to `0` to disable automatic cleanup.

---

## Config Values vs. Explicit Parameters

Config settings are **defaults**. Supplying a parameter explicitly on a cmdlet
call overrides the config for that call only -- the config file is unchanged.

```powershell
# Config has ftdi.highDriveIOs = false
# Override for one device only, without touching config:
Set-PsGadgetFt232rCbusMode -Index 2 -HighDriveIOs $true   # 8 mA this call
Set-PsGadgetFt232rCbusMode -Index 0                        # still 4 mA (config default)
```

---

## Resetting to Defaults

```powershell
Remove-Item "$([Environment]::GetFolderPath('UserProfile'))\.psgadget\config.json"
Import-Module PSGadget -Force
```

The next import recreates `config.json` with all defaults.

---

## See Also

- [Function Reference: Get-PsGadgetConfig](Function-Reference.md#get-psgadgetconfig)
- [Function Reference: Set-PsGadgetConfig](Function-Reference.md#set-psgadgetconfig)
- Full key details are included above in this page. (Original about_PsGadgetConfig.md has been archived.)
