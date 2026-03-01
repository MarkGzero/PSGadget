# Install-PsGadgetMpyScript.ps1
#Requires -Version 5.1

function Install-PsGadgetMpyScript {
    <#
    .SYNOPSIS
        Deploy a bundled PsGadget MicroPython script to an ESP32 device.

    .DESCRIPTION
        Pushes the bundled espnow_receiver.py or espnow_transmitter.py to an
        ESP32 device as main.py using mpremote, along with an optional
        config.json for pin and timing overrides.

        After push the device is reset so main.py starts immediately.

        Requires mpremote on PATH: pip install mpremote

    .PARAMETER SerialPort
        Serial port the ESP32 is connected to (e.g. COM4, /dev/ttyUSB0).

    .PARAMETER Role
        Script role to deploy: Receiver or Transmitter.
        - Receiver:    wired to FT232H via UART; forwards ESP-NOW traffic to host.
        - Transmitter: wireless node; sends telemetry to the receiver.

    .PARAMETER ConfigPath
        Optional path to a custom config.json to deploy alongside main.py.
        If omitted, the bundled mpy/scripts/config.json is used.
        Pass '-ConfigPath $null' to skip deploying any config file.

    .PARAMETER Force
        Skip confirmation prompt.

    .EXAMPLE
        Install-PsGadgetMpyScript -SerialPort "COM4" -Role Receiver

    .EXAMPLE
        Install-PsGadgetMpyScript -SerialPort "/dev/ttyUSB0" -Role Transmitter -Force

    .EXAMPLE
        Install-PsGadgetMpyScript -SerialPort "COM4" -Role Receiver -ConfigPath "./lab_pins.json"

    .OUTPUTS
        [PSCustomObject] with fields: Role, SerialPort, ScriptDeployed, ConfigDeployed, Success, Message
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialPort,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Receiver', 'Transmitter')]
        [string]$Role,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $result = [PSCustomObject]@{
        Role           = $Role
        SerialPort     = $SerialPort
        ScriptDeployed = $false
        ConfigDeployed = $false
        Success        = $false
        Message        = ''
    }

    # -- locate bundled scripts directory -----------------------------------
    $scriptsDir = Join-Path $PSScriptRoot ".." "mpy" "scripts"
    $scriptsDir = [System.IO.Path]::GetFullPath($scriptsDir)

    $sourceScript = Join-Path $scriptsDir ("espnow_{0}.py" -f $Role.ToLower())

    if (-not (Test-Path -Path $sourceScript)) {
        $result.Message = "Bundled script not found: $sourceScript"
        Write-Error $result.Message
        return $result
    }

    # -- resolve config file ------------------------------------------------
    $configToDeploy = $null
    if ($PSBoundParameters.ContainsKey('ConfigPath')) {
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            if (-not (Test-Path -Path $ConfigPath)) {
                $result.Message = "ConfigPath not found: $ConfigPath"
                Write-Error $result.Message
                return $result
            }
            $configToDeploy = $ConfigPath
        }
        # else: explicitly passed $null -- skip config deploy
    } else {
        # use bundled default
        $bundledConfig = Join-Path $scriptsDir "config.json"
        if (Test-Path -Path $bundledConfig) {
            $configToDeploy = $bundledConfig
        }
    }

    # -- check mpremote available -------------------------------------------
    if (-not (Test-NativeCommand 'mpremote')) {
        $result.Message = "mpremote not found on PATH. Install with: pip install mpremote"
        Write-Error $result.Message
        return $result
    }

    # -- confirm ---------------------------------------------------------------
    if (-not $Force) {
        $prompt = "Deploy PsGadget-{0} to {1}? This will overwrite main.py on the device." -f $Role, $SerialPort
        if (-not $PSCmdlet.ShouldProcess($SerialPort, $prompt)) {
            $result.Message = "Cancelled by user."
            return $result
        }
    }

    Write-Verbose ("Deploying {0} script to {1}" -f $Role, $SerialPort)

    # -- push main.py -------------------------------------------------------
    $pushScript = Invoke-NativeProcess -FilePath 'mpremote' `
        -ArgumentList @('connect', $SerialPort, 'cp', $sourceScript, ':main.py') `
        -TimeoutSeconds 30

    if (-not $pushScript.Success) {
        $result.Message = ("Failed to push main.py: {0}" -f $pushScript.StandardError)
        Write-Error $result.Message
        return $result
    }

    $result.ScriptDeployed = $true
    Write-Verbose ("main.py deployed from: {0}" -f $sourceScript)

    # -- push config.json ---------------------------------------------------
    if ($null -ne $configToDeploy) {
        $pushConfig = Invoke-NativeProcess -FilePath 'mpremote' `
            -ArgumentList @('connect', $SerialPort, 'cp', $configToDeploy, ':config.json') `
            -TimeoutSeconds 15

        if ($pushConfig.Success) {
            $result.ConfigDeployed = $true
            Write-Verbose ("config.json deployed from: {0}" -f $configToDeploy)
        } else {
            Write-Warning ("config.json push failed (non-fatal): {0}" -f $pushConfig.StandardError)
        }
    }

    # -- reset device -------------------------------------------------------
    Write-Verbose ("Resetting device on {0}" -f $SerialPort)
    $reset = Invoke-NativeProcess -FilePath 'mpremote' `
        -ArgumentList @('connect', $SerialPort, 'reset') `
        -TimeoutSeconds 10

    if (-not $reset.Success) {
        Write-Warning ("Device reset failed (non-fatal): {0}" -f $reset.StandardError)
    }

    $result.Success = $true
    $result.Message = ("PsGadget-{0} deployed to {1}. Device reset." -f $Role, $SerialPort)
    Write-Verbose $result.Message
    return $result
}
