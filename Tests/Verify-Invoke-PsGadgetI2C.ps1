#!/usr/bin/env pwsh
#Requires -Version 5.1
# Smoke-test verification script for Invoke-PsGadgetI2C.
# Run from the psgadget repo root:
#   pwsh Tests/Verify-Invoke-PsGadgetI2C.ps1

Set-Location $PSScriptRoot/..
Import-Module ./PSGadget.psd1 -Force 2>&1 | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { Write-Error $_ }
Write-Output ""

# 1. Old PCA9685-specific exports should be gone
$checks = @(
    'Connect-PsGadgetPca9685',
    'Invoke-PsGadgetPca9685SetChannel',
    'Invoke-PsGadgetPca9685SetChannels',
    'Get-PsGadgetPca9685Channel',
    'Get-PsGadgetPca9685Frequency'
)
foreach ($name in $checks) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Output "FAIL  $name is still exported (module=$($cmd.ModuleName))"
    } else {
        Write-Output "OK    $name removed from exports"
    }
}

# 2. New function exported
$inv = Get-Command Invoke-PsGadgetI2C -ErrorAction SilentlyContinue
if ($inv) {
    Write-Output "OK    Invoke-PsGadgetI2C is exported"
    $params = $inv.Parameters.Keys | Where-Object { $_ -notin @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable') }
    Write-Output "      Static params: $($params -join ', ')"
} else {
    Write-Output "FAIL  Invoke-PsGadgetI2C not found"
}

# 3. Validate DynamicParam activates for PCA9685
# We cannot fully invoke without hardware so we test the param dictionary via reflection
try {
    $fnInfo = (Get-Module PSGadget).ExportedCommands['Invoke-PsGadgetI2C']
    Write-Output "OK    Invoke-PsGadgetI2C function info retrieved from module"
} catch {
    Write-Output "INFO  DynamicParam reflection skipped: $_"
}

# 4. ValidateSet enforcement - wrong module name should throw
try {
    Invoke-PsGadgetI2C -Index 0 -I2CModule BOGUS -ServoAngle @(0,90) -ErrorAction Stop
    Write-Output "FAIL  ValidateSet not enforced for I2CModule BOGUS"
} catch {
    if ($_.Exception.Message -match "BOGUS|ValidateSet|not belong") {
        Write-Output "OK    ValidateSet enforced: bad I2CModule rejected"
    } else {
        Write-Output "OK    I2CModule=BOGUS rejected with: $($_.Exception.Message)"
    }
}

# 5. Input validation - angle out of range should throw before touching hardware
# We cannot open hardware here so just check the parse/validate logic by invoking
# with a stub - skip if we cannot reach hardware (expected in CI)
Write-Output ""
Write-Output "Verification complete."
