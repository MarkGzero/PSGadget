#Requires -Version 5.1

function Test-PsGadgetPca9685Ft232h {
    <#
    .SYNOPSIS
    Runs a manual FT232H -> PCA9685 -> servo validation sequence.

    .DESCRIPTION
    Imports the PSGadget module, verifies FT232H detection, scans the I2C bus,
    connects to a PCA9685 controller, and sweeps one servo channel through a
    configurable set of angles. This script is intended for hands-on hardware
    validation on Windows with a real FT232H board and external servo power.

    .PARAMETER Index
    FTDI device index from List-PsGadgetFtdi. Default is 0.

    .PARAMETER Address
    PCA9685 I2C address. Default is 0x40.

    .PARAMETER Channel
    Servo channel on the PCA9685. Default is 0.

    .PARAMETER Frequency
    PWM frequency in Hz. Default is 50 for RC servos.

    .PARAMETER Degrees
    Sweep positions to test in order. Default is 0, 90, 180, 90.

    .PARAMETER HoldMilliseconds
    Delay after each move. Default is 1000 ms.

    .PARAMETER ScanOnly
    Only verify FT232H detection and I2C presence, without moving the servo.

    .EXAMPLE
    Test-PsGadgetPca9685Ft232h

    .EXAMPLE
    Test-PsGadgetPca9685Ft232h -Channel 1 -Degrees @(45, 90, 135, 90) -HoldMilliseconds 750

    .EXAMPLE
    Test-PsGadgetPca9685Ft232h -Address 0x41 -ScanOnly
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 127)]
        [int]$Index = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0x40, 0x47)]
        [byte]$Address = 0x40,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 15)]
        [int]$Channel = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(23, 1526)]
        [int]$Frequency = 50,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [int[]]$Degrees = @(0, 90, 180, 90),

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 10000)]
        [int]$HoldMilliseconds = 1000,

        [Parameter(Mandatory = $false)]
        [switch]$ScanOnly
    )

    Write-Host '=== PsGadget PCA9685 FT232H Test ===' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Hardware checklist:' -ForegroundColor Yellow
    Write-Host '  1. FT232H D0 -> PCA9685 SCL' -ForegroundColor Gray
    Write-Host '  2. FT232H D1 -> PCA9685 SDA' -ForegroundColor Gray
    Write-Host '  3. FT232H GND -> PCA9685 GND -> servo supply GND' -ForegroundColor Gray
    Write-Host '  4. PCA9685 powered from external 5V logic rail' -ForegroundColor Gray
    Write-Host '  5. Servo powered from external 5V supply, not USB 5V' -ForegroundColor Gray
    Write-Host ''

    $modulePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'PSGadget.psd1'
    $ftdi = $null
    $pca = $null

    try {
        if (-not (Get-Module PSGadget)) {
            Import-Module $modulePath -Force
            Write-Host 'Module imported' -ForegroundColor Green
        } else {
            Write-Host 'Module already loaded' -ForegroundColor Green
        }

        $devices = @(List-PsGadgetFtdi)
        if ($devices.Count -eq 0) {
            throw 'No FTDI devices detected'
        }

        Write-Host ''
        Write-Host 'Detected FTDI devices:' -ForegroundColor Yellow
        $devices | Format-Table Index, Type, SerialNumber, GpioMethod -AutoSize

        $target = $devices | Where-Object { $_.Index -eq $Index } | Select-Object -First 1
        if (-not $target) {
            throw "FTDI device index $Index was not found"
        }

        if ($target.GpioMethod -notin @('MPSSE', 'MpsseI2c', 'IoT')) {
            throw "FTDI device index $Index does not expose an I2C-capable backend (GpioMethod=$($target.GpioMethod))"
        }

        $ftdi = New-PsGadgetFtdi -Index $Index
        if (-not $ftdi -or -not $ftdi.IsOpen) {
            throw "Failed to open FTDI device at index $Index"
        }

        Set-PsGadgetFtdiMode -PsGadget $ftdi -Mode MpsseI2c | Out-Null

        Write-Host ''
        Write-Host 'Scanning I2C bus...' -ForegroundColor Yellow
        $scan = @(Invoke-PsGadgetI2CScan -PsGadget $ftdi)
        if ($scan.Count -eq 0) {
            throw 'No I2C devices acknowledged on the bus'
        }

        $scan | Format-Table Address, Hex -AutoSize

        $expectedHex = '0x{0:X2}' -f $Address
        $hit = $scan | Where-Object { $_.Address -eq $Address -or $_.Hex -eq $expectedHex } | Select-Object -First 1
        if (-not $hit) {
            throw "PCA9685 address $expectedHex was not found on the I2C bus"
        }

        if ($ScanOnly) {
            Write-Host ''
            Write-Host "Scan complete. PCA9685 detected at $expectedHex." -ForegroundColor Green
            return
        }

        Write-Host ''
        Write-Host ("Connecting to PCA9685 at {0}, frequency {1} Hz..." -f $expectedHex, $Frequency) -ForegroundColor Yellow
        $pca = Connect-PsGadgetPca9685 -Connection $ftdi -Address $Address -Frequency $Frequency
        if (-not $pca) {
            throw 'Connect-PsGadgetPca9685 returned null'
        }

        Write-Host ("Testing servo channel {0}" -f $Channel) -ForegroundColor Yellow
        foreach ($degree in $Degrees) {
            Write-Host ("  -> Move to {0} degrees" -f $degree) -ForegroundColor Gray
            $ok = Invoke-PsGadgetPca9685SetChannel -PsGadget $pca -Channel $Channel -Degrees $degree
            if (-not $ok) {
                throw "Servo move failed for channel $Channel at $degree degrees"
            }

            $cached = Get-PsGadgetPca9685Channel -PsGadget $pca -Channel $Channel
            Write-Host ("     Cached position: {0} degrees" -f $cached) -ForegroundColor DarkGray
            Start-Sleep -Milliseconds $HoldMilliseconds
        }

        Write-Host ''
        Write-Host 'Servo sweep completed successfully.' -ForegroundColor Green
        Write-Host 'If motion was wrong, re-check power, shared ground, and servo orientation.' -ForegroundColor Yellow
    } catch {
        Write-Host ''
        Write-Host ("[FAIL] {0}" -f $_) -ForegroundColor Red
        throw
    } finally {
        if ($ftdi -and $ftdi.PSObject.Methods.Name -contains 'Close') {
            try {
                $ftdi.Close()
            } catch {
            }
        }
    }
}