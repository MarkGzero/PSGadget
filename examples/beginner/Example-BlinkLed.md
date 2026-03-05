# Beginner Example: Blink a LED with PSGadget

**Purpose**: Connect an LED to an FT232H GPIO pin and blink it from PowerShell.
No prior hardware experience assumed.

---

## What you need

**Hardware**
- FT232H USB breakout board (search "FT232H breakout" on Amazon or Adafruit #2264, ~$10-15)
- One LED (any color)
- One 330 ohm resistor (orange-orange-brown color bands)
- Three short jumper wires
- USB cable (data cable -- charge-only cables will not work)

**Software**
- PowerShell 7 (download free from https://aka.ms/powershell)
- PSGadget installed (run `Install-Module PSGadget -Scope CurrentUser`)
- FTDI D2XX driver installed (Windows -- see [Getting Started](../../docs/wiki/Getting-Started.md))

---

## What are these parts?

> **Beginner (Nikola)**: An FT232H is a small chip on a breakout board that
> plugs into your USB port. It has pins labeled ACBUS0 through ACBUS7. These
> pins can be switched between 3.3 V and 0 V (called HIGH and LOW) from a
> PowerShell script. That is all GPIO (General Purpose Input/Output) means --
> pins you can control in software.

> **Beginner (Nikola)**: The resistor protects the LED. Without it, too much
> current flows and the LED or the board can be damaged. Always use a resistor
> in series with an LED.

---

## Wiring

Connect the parts as follows:

1. FT232H pin **ACBUS0** -- through the 330 ohm resistor -- to the **long leg**
   (anode) of the LED.
2. LED **short leg** (cathode) -- to the FT232H **GND** pin.

That is the complete circuit. The USB cable powers the board.

If your board has a VCC pin and a 3V3 pin, use the 3V3 pin for any separate
power needs. Do not connect 5 V directly to the GPIO pins.

---

## Step by step

**Step 1**: Plug the FT232H into USB.

**Step 2**: Open PowerShell and import PSGadget:

```powershell
Import-Module PSGadget
```

You should see no error. If you see a red error message, see
[TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md).

**Step 3**: Check that PSGadget can see your board:

```powershell
Test-PsGadgetEnvironment
```

Look for `Status : READY`. If it says `Fail`, read the `NextStep` line and
run the command shown there.

**Step 4**: See your device listed:

```powershell
List-PsGadgetFtdi | Format-Table
```

You should see a row with `Type = FT232H` and a serial number. Write down the
serial number -- you will use it in the next step.

**Step 5**: Connect to the device (replace the serial number with yours):

```powershell
$dev = New-PsGadgetFtdi -SerialNumber 'BG01X3GX'
```

No error means the connection worked.

**Step 6**: Turn the LED on:

```powershell
$dev.SetPin(0, 'HIGH')
```

The LED should light up. Pin 0 = ACBUS0 = the pin you wired the LED to.

**Step 7**: Turn it off:

```powershell
$dev.SetPin(0, 'LOW')
```

**Step 8**: Blink it three times:

```powershell
for ($i = 0; $i -lt 3; $i++) {
    $dev.SetPin(0, 'HIGH')
    Start-Sleep -Milliseconds 500
    $dev.SetPin(0, 'LOW')
    Start-Sleep -Milliseconds 500
}
```

**Step 9**: Clean up:

```powershell
$dev.Close()
```

Always close the device when done. This releases the USB connection so other
programs can use it.

---

## Copy-paste script

Save this as `blink.ps1` and run it any time:

```powershell
#Requires -Version 5.1
Import-Module PSGadget

$result = Test-PsGadgetEnvironment
if ($result.Status -ne 'OK') {
    Write-Warning "Not ready: $($result.Reason)"
    Write-Warning "Fix: $($result.NextStep)"
    return
}

$dev = New-PsGadgetFtdi -Index 0

try {
    Write-Host 'Blinking LED on ACBUS0 three times...'
    for ($i = 0; $i -lt 3; $i++) {
        $dev.SetPin(0, 'HIGH')
        Start-Sleep -Milliseconds 500
        $dev.SetPin(0, 'LOW')
        Start-Sleep -Milliseconds 500
    }
    Write-Host 'Done.'
} finally {
    $dev.Close()
}
```

---

## Troubleshooting

**LED does not light up**
- Check the wiring. The long leg of the LED must connect to ACBUS0,
  not GND.
- Make sure the resistor is in series (in the path), not wired to a
  different pin.
- Run `Test-PsGadgetEnvironment` and check `Status`.

**Error: Device not found**
- Make sure the USB cable is plugged in.
- On Windows: open Device Manager and confirm the FTDI device appears
  without a yellow warning icon.
- Run `Test-PsGadgetEnvironment -Verbose` for detailed diagnostics.

**Error: Access denied**
- On Linux: run `sudo usermod -aG plugdev $USER` and log out/in.
- Close any other programs that may have the device open (PuTTY, Arduino IDE).
