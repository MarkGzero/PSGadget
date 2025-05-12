
## PSGadget Display

### Import module

```powershell
Import-Module \\path\to\PsGadget.psm1
```

### Scan for FTDI Devices

```powershell
[FtdiSharp.FtdiDevices]::Scan()

# Example output:
Index        : 0
IsOpen       : True
IsHighSpeed  : True
Type         : 232H
ID           : 67330068
LocationID   : 5939
SerialNumber : FT9ZLJ51
Description  : USB <-> Serial Converter
```

### Assign FTDI Device

#### Option1: Select First Device
```powershell
# select first 1
$ftboard = [FtdiSharp.FtdiDevices]::scan() | Select-Object -First 1
```

#### Option2: Select by SeriaNumber
```powershell
# select by serial number
$ftboard = [FtdiSharp.FtdiDevices]::scan() | Where-Object SerialNumber -eq "FT9ZLJ51"
```

### Create New FTDI I2C object

```powershell
$psgadget_ds = [FtdiSharp.Protocols.I2C]::new($ftboard)
```

#### Scan for I2C devices

*(Note: SSD1306 i2c device common address: 0x3C)*

```powershell
$psgadget_ds.scan() | ForEach-Object { 
    "Found device at 0x{0:X2}" -f $_ 
    }

# example output:
Found device at 0x3C
```

## Initialize the display

```PowerShell
Open-PsGadgetDisplay -i2c $psgadget_ds
Set-PsGadgetDisplayCursor -i2c $psgadget_ds -col 0 -page 0
Clear-PsGadgetDisplay -i2c $psgadget_ds
```

## Demonstration

### Write bytes individually

```powershell
$str = "=== PsGadget! 1234567890 !@#$%% ==="   
$arrChar = $str.ToCharArray()
Clear-PsGadgetDisplay $psgadget_ds

$arrChar | ForEach-Object {
    $char = $_
    $glyph = $script:glyphs["$char"]
    if ($glyph) {
        Send-PsGadgetDisplayData -i2c $psgadget_ds -data $glyph
    }
}
```
### Use buffer to send write as single write job

```powershell
$str = "=== PsGadget! 1234567890 !@#$%% ===" 
$arrChar = $str.ToCharArray()
[System.Collections.Generic.List[byte]]$buffer = @()

foreach ($char in $arrChar) {
    $glyph = $script:glyphs["$char"]
    if ($glyph) {
        foreach ($b in $glyph) {
            $buffer.Add([byte]$b)
        }
    }
}

if ($buffer.Count -gt 0) {
    Clear-PsGadgetDisplay $psgadget_ds
    $fullPayload = $buffer.ToArray()
    Send-PsGadgetDisplayData -i2c $psgadget_ds -data $fullPayload
}

```

## Full Script

```powershell
cd "C:\path\to\git\psgadget\"
import-module .\PsGadget.psm1
$ftdi = [FtdiSharp.FtdiDevices]::scan() | Select-Object -First 1
$psgadget_ds = [FtdiSharp.Protocols.I2C]::new($ftdi)
$psgadget_ds.scan() | ForEach-Object { 
    "Found device at 0x{0:X2}" -f $_ 
    }

Open-PsGadgetDisplay -i2c $psgadget_ds
Set-PsGadgetDisplayCursor -i2c $psgadget_ds -col 0 -page 0
Clear-PsGadgetDisplay -i2c $psgadget_ds

$str = "===> Hello <===" 
$arrChar = $str.ToCharArray()
[System.Collections.Generic.List[byte]]$buffer = @()

foreach ($char in $arrChar) {
    $glyph = $script:glyphs["$char"]
    if ($glyph) {
        foreach ($b in $glyph) {
            $buffer.Add([byte]$b)
        }
    }
}

if ($buffer.Count -gt 0) {
    $fullPayload = $buffer.ToArray()
    @(0..7) | % {
        Send-PsGadgetDisplayData -i2c $psgadget_ds -data $fullPayload -page $_ -align 'center'
    }
}

```
