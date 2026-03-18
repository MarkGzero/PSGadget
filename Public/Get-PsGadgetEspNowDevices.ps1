# Get-PsGadgetEspNowDevices.ps1
#Requires -Version 5.1

function Get-PsGadgetEspNowDevices {
    <#
    .SYNOPSIS
        Pull the known_devices.txt registry from a PsGadget-Receiver ESP32.

    .DESCRIPTION
        Copies known_devices.txt from the receiver's flash filesystem to the
        local machine using mpremote. The file records every transmitter MAC
        address the receiver has seen, with a last-seen timestamp.

        The file is saved to ~/.psgadget/known_devices.txt by default and
        parsed into objects for pipeline use.

        Requires mpremote on PATH: pip install mpremote
        The target device must have been deployed as a Receiver role and run
        long enough to receive at least one transmitter.

    .PARAMETER SerialPort
        Serial port the Receiver ESP32 is connected to (e.g. COM4, /dev/ttyUSB0).

    .PARAMETER OutputPath
        Local path to save known_devices.txt.
        Default: ~/.psgadget/known_devices.txt

    .PARAMETER PassThru
        Return the parsed device objects even when saving to disk (default behavior
        always returns objects).

    .EXAMPLE
        # Pull devices and save to default location
        Get-PsGadgetEspNowDevices -SerialPort "COM4"

    .EXAMPLE
        # Save to custom path and inspect in pipeline
        Get-PsGadgetEspNowDevices -SerialPort "/dev/ttyUSB0" -OutputPath "./lab_devices.txt"

    .OUTPUTS
        [PSCustomObject[]] with fields: Mac, LastSeen
        Returns empty array if file not found or contains no valid entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialPort,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    # -- resolve output path ------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $psgadgetDir = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.psgadget'
        if (-not (Test-Path -Path $psgadgetDir)) {
            New-Item -Path $psgadgetDir -ItemType Directory -Force | Out-Null
        }
        $OutputPath = Join-Path $psgadgetDir 'known_devices.txt'
    }

    # -- check mpremote -----------------------------------------------------
    if (-not (Test-NativeCommand 'mpremote')) {
        Write-Error "mpremote not found on PATH. Install with: pip install mpremote"
        return @()
    }

    # -- pull file from device ----------------------------------------------
    Write-Verbose ("Pulling known_devices.txt from {0}" -f $SerialPort)

    $pull = Invoke-NativeProcess -FilePath 'mpremote' `
        -ArgumentList @('connect', $SerialPort, 'cp', ':known_devices.txt', $OutputPath) `
        -TimeoutSeconds 20

    if (-not $pull.Success) {
        $errMsg = $pull.StandardError
        if ($errMsg -match 'ENOENT|No such file') {
            Write-Warning ("known_devices.txt not found on device. Has the receiver seen any transmitters yet?")
        } else {
            Write-Error ("Failed to pull known_devices.txt: {0}" -f $errMsg)
        }
        return @()
    }

    Write-Verbose ("Saved to: {0}" -f $OutputPath)

    # -- parse file ---------------------------------------------------------
    $devices = @()

    if (-not (Test-Path -Path $OutputPath)) {
        Write-Warning ("Output file not found after pull: {0}" -f $OutputPath)
        return $devices
    }

    $lines = Get-Content -Path $OutputPath -Encoding UTF8 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        $line = $line.Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }

        $parts = $line -split '\|'
        if ($parts.Count -eq 2) {
            $devices += [PSCustomObject]@{
                Mac      = $parts[0].Trim()
                LastSeen = $parts[1].Trim()
            }
        } else {
            Write-Verbose ("Skipping malformed line: {0}" -f $line)
        }
    }

    Write-Verbose ("{0} device(s) found in registry." -f $devices.Count)
    return $devices
}
