## PSGadget and MPU6050 sensor


### create a new FTDI I2C object

```powershell
class Mpu6050Sensor {
    [FtdiSharp.Protocols.I2C]$I2C
    [byte]$Addr = 0x68
    [double]$AccelScale = 9.80665 / 16384
    [double]$GyroScale = 1.0 / 131.0

    Mpu6050Sensor([FtdiSharp.Protocols.I2C]$i2c, [byte]$address = 0x68) {
        $this.I2C = $i2c
        $this.Addr = $address
    }

    [void]Initialize() {
        $this.I2C.Write($this.Addr, @(0x6B, 0x80))  # Reset
        Start-Sleep -Milliseconds 100
        $this.I2C.Write($this.Addr, @(0x6B, 0x01))  # Clock: X gyro
        $this.I2C.Write($this.Addr, @(0x6C, 0x00))  # All axes on
        $this.I2C.Write($this.Addr, @(0x1A, 0x03))  # DLPF
        $this.I2C.Write($this.Addr, @(0x1B, 0x00))  # Gyro ±250 dps
        $this.I2C.Write($this.Addr, @(0x1C, 0x00))  # Accel ±2g
        $this.I2C.Write($this.Addr, @(0x19, 0x07))  # Sample rate
        Start-Sleep -Milliseconds 100
    }

    [hashtable]Read() {
        $buf = $this.I2C.WriteThenRead($this.Addr, 0x3B, 14)
        $to16 = {
            param($hi, $lo)
            $val = ($hi -shl 8) -bor $lo
            if ($val -gt 32767) { $val - 65536 } else { $val }
        }

        $ax = &$to16 $buf[0] $buf[1]
        $ay = &$to16 $buf[2] $buf[3]
        $az = &$to16 $buf[4] $buf[5]
        $t  = &$to16 $buf[6] $buf[7]
        $gx = &$to16 $buf[8] $buf[9]
        $gy = &$to16 $buf[10] $buf[11]
        $gz = &$to16 $buf[12] $buf[13]

        return @{
            Acceleration = @(
                [math]::Round($ax * $this.AccelScale, 3),
                [math]::Round($ay * $this.AccelScale, 3),
                [math]::Round($az * $this.AccelScale, 3)
            )
            Gyro = @(
                [math]::Round(($gx * $this.GyroScale) * [math]::PI / 180, 4),
                [math]::Round(($gy * $this.GyroScale) * [math]::PI / 180, 4),
                [math]::Round(($gz * $this.GyroScale) * [math]::PI / 180, 4)
            )
            Temperature = [math]::Round($t / 340.0 + 36.53, 2)
        }
    }
}
```

### Initialize the FTDI I2C object

```powershell
$mpu = [Mpu6050Sensor]::new($psgadget_ds)
$mpu.Initialize()
```

### Read data from the MPU6050

```powershell
while ($true) {
    $d = $mpu.Read()
    "{0:N2} {1:N2} {2:N2} m/s² | {3:N2} rad/s | {4}°C" -f `
        $d.Acceleration[0], $d.Acceleration[1], $d.Acceleration[2],
        $d.Gyro[0], $d.Temperature
    Start-Sleep -Milliseconds 50
}
```

Example output:
```powershell
0.00 0.00 9.81 m/s² | 0.00 rad/s | 25.00°C
0.00 0.00 9.81 m/s² | 0.00 rad/s | 25.00°C
0.00 0.00 9.81 m/s² | 0.00 rad/s | 25.00°C
```


### GUI

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Create GUI ===
$form = New-Object Windows.Forms.Form
$form.Text = "MPU6050 Sensor Viewer"
$form.Size = '400,350'
$form.StartPosition = "CenterScreen"
$form.Topmost = $true

$labels = @{}
$fields = @(
    "Accel X (m/s²)", "Accel Y (m/s²)", "Accel Z (m/s²)",
    "Gyro X (rad/s)", "Gyro Y (rad/s)", "Gyro Z (rad/s)",
    "Temp (°C)"
)
$y = 20
foreach ($field in $fields) {
    $lblName = New-Object Windows.Forms.Label
    $lblName.Text = $field
    $lblName.Location = "20,$y"
    $lblName.Size = '120,20'
    $form.Controls.Add($lblName)

    $lblValue = New-Object Windows.Forms.Label
    $lblValue.Text = ""
    $lblValue.Location = "160,$y"
    $lblValue.Size = '200,20'
    $form.Controls.Add($lblValue)

    $labels[$field] = $lblValue
    $y += 30
}

# === Sensor setup ===
$ftdi = [FtdiSharp.FtdiDevices]::Scan() | ? serialnumber -eq 'DS8VYR6K'
$psgadget_ds = [FtdiSharp.Protocols.I2C]::new($ftdi)

if (-not ("Mpu6050Sensor" -as [type])) {
    class Mpu6050Sensor {
        [FtdiSharp.Protocols.I2C]$I2C
        [byte]$Addr = 0x68
        [double]$AccelScale = 9.80665 / 16384
        [double]$GyroScale = 1.0 / 131.0

        Mpu6050Sensor([FtdiSharp.Protocols.I2C]$i2c) {
            $this.I2C = $i2c
        }

        [void]Initialize() {
            $this.I2C.Write($this.Addr, @(0x6B, 0x80))
            Start-Sleep -Milliseconds 100
            $this.I2C.Write($this.Addr, @(0x6B, 0x01))
            $this.I2C.Write($this.Addr, @(0x6C, 0x00))
            $this.I2C.Write($this.Addr, @(0x1A, 0x03))
            $this.I2C.Write($this.Addr, @(0x1B, 0x00))
            $this.I2C.Write($this.Addr, @(0x1C, 0x00))
            $this.I2C.Write($this.Addr, @(0x19, 0x07))
            Start-Sleep -Milliseconds 100
        }

        [hashtable]Read() {
            $b = $this.I2C.WriteThenRead($this.Addr, 0x3B, 14)
            $to16 = {
                param($hi, $lo)
                $v = ($hi -shl 8) -bor $lo
                if ($v -gt 32767) { $v - 65536 } else { $v }
            }
            $ax = &$to16 $b[0] $b[1]; $ay = &$to16 $b[2] $b[3]; $az = &$to16 $b[4] $b[5]
            $t  = &$to16 $b[6] $b[7]
            $gx = &$to16 $b[8] $b[9]; $gy = &$to16 $b[10] $b[11]; $gz = &$to16 $b[12] $b[13]
            return @{
                Accel = @(
                    [math]::Round($ax * $this.AccelScale, 2),
                    [math]::Round($ay * $this.AccelScale, 2),
                    [math]::Round($az * $this.AccelScale, 2)
                )
                Gyro = @(
                    [math]::Round(($gx * $this.GyroScale) * [math]::PI / 180, 3),
                    [math]::Round(($gy * $this.GyroScale) * [math]::PI / 180, 3),
                    [math]::Round(($gz * $this.GyroScale) * [math]::PI / 180, 3)
                )
                Temp = [math]::Round($t / 340.0 + 36.53, 2)
            }
        }
    }
}

$mpu = [Mpu6050Sensor]::new($psgadget_ds)
$mpu.Initialize()

# === Timer to refresh GUI ===
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 100

$timer.Add_Tick({
    try {
        $d = $mpu.Read()
        function GetArrow($val, $axis, $threshold = 0.5) {
            if ([math]::Abs($val) -lt $threshold) {
                return " "  # too small, don't show arrow
            }
        
            switch ($axis) {
                "X" {
                    if ($val -gt 0) { return "→" }
                    elseif ($val -lt 0) { return "←" }
                    else { return " " }
                }
                "Y" {
                    if ($val -gt 0) { return "↑" }
                    elseif ($val -lt 0) { return "↓" }
                    else { return " " }
                }
                "Z" {
                    if ($val -gt 0) { return "⬆" }
                    elseif ($val -lt 0) { return "⬇" }
                    else { return " " }
                }
                default { return " " }
            }
        }

        function GetColor($val) {
            $abs = [math]::Abs($val)
            switch ($true) {
                { $abs -lt 1 }  { return 'Green' }
                { $abs -lt 3 }  { return 'Goldenrod' }
                default         { return 'Red' }
            }
        }

        # Accel
        $labels["Accel X (m/s²)"].Text = "{0:N2} {1}" -f $d.Accel[0], (GetArrow $d.Accel[0] 'X')
        $labels["Accel X (m/s²)"].ForeColor = GetColor $d.Accel[0]

        $labels["Accel Y (m/s²)"].Text = "{0:N2} {1}" -f $d.Accel[1], (GetArrow $d.Accel[1] 'Y')
        $labels["Accel Y (m/s²)"].ForeColor = GetColor $d.Accel[1]

        $labels["Accel Z (m/s²)"].Text = "{0:N2} {1}" -f $d.Accel[2], (GetArrow $d.Accel[2] 'Z')
        $labels["Accel Z (m/s²)"].ForeColor = GetColor $d.Accel[2]

        # Gyro
        $labels["Gyro X (rad/s)"].Text = "{0:N2} {1}" -f $d.Gyro[0], (GetArrow $d.Gyro[0] 'X')
        $labels["Gyro X (rad/s)"].ForeColor = GetColor $d.Gyro[0]

        $labels["Gyro Y (rad/s)"].Text = "{0:N2} {1}" -f $d.Gyro[1], (GetArrow $d.Gyro[1] 'Y')
        $labels["Gyro Y (rad/s)"].ForeColor = GetColor $d.Gyro[1]

        $labels["Gyro Z (rad/s)"].Text = "{0:N2} {1}" -f $d.Gyro[2], (GetArrow $d.Gyro[2] 'Z')
        $labels["Gyro Z (rad/s)"].ForeColor = GetColor $d.Gyro[2]

        $labels["Temp (°C)"].Text = $d.Temp
        $labels["Temp (°C)"].ForeColor = 'Black'

    } catch {
        foreach ($lbl in $labels.Values) { $lbl.Text = "ERR"; $lbl.ForeColor = 'DarkRed' }
    }
})

$timer.Start()
$form.Add_FormClosing({ $timer.Stop() })

# === Show GUI ===
[void]$form.ShowDialog()
```