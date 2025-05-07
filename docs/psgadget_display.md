
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
Start-Ssd1306Initialize -i2c $psgadget_ds
Set-Ssd1306Cursor -i2c $psgadget_ds -col 0 -page 0
Clear-Ssd1306 -i2c $psgadget_ds
```

## Demonstration

### Write bytes individually

```powershell
$str = "=== PsGadget! 1234567890 !@#$%% ==="   
$arrChar = $str.ToCharArray()
Clear-ssd1306 $psgadget_ds

$arrChar | ForEach-Object {
    $char = $_
    $glyph = $script:glyphs["$char"]
    if ($glyph) {
        Send-Ssd1306Data -i2c $psgadget_ds -data $glyph
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
    Clear-ssd1306 $psgadget_ds
    $fullPayload = $buffer.ToArray()
    Send-Ssd1306Data -i2c $psgadget_ds -data $fullPayload
}

```