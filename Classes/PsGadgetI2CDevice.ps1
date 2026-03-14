#Requires -Version 5.1

# Classes/PsGadgetI2CDevice.ps1
# Base class for I2C device drivers backed by FTDI hardware.
#
# Provides the five shared fields, the I2CWrite transport method,
# the no-arg Initialize() overload (polymorphically dispatched to the
# derived class), and BeginInitialize() which encapsulates the guard
# that every device's Initialize([bool]$force) must run first.
#
# PowerShell 5.1 inheritance notes:
#   - The parameterless base constructor runs automatically before every
#     derived constructor body. Derived constructors must NOT re-create Logger.
#   - There is no abstract keyword; direct instantiation is possible but
#     Initialize() will throw at runtime since Initialize([bool]) is not
#     defined on this class — it is defined on each derived device class.
#   - $this.Initialize($false) in Initialize() resolves to the derived
#     class override at runtime (dynamic dispatch).

class PsGadgetI2CDevice {
    [PsGadgetLogger]$Logger
    [System.Object]$FtdiDevice
    [System.Object]$I2cDevice   # FtdiSharp.Protocols.I2C instance when available; preferred over raw MPSSE
    [byte]$I2CAddress
    [bool]$IsInitialized

    # Parameterless constructor — called automatically before every derived
    # constructor body. Sets Logger so derived constructors can call
    # $this.Logger.WriteInfo() on their first line.
    PsGadgetI2CDevice() {
        $this.Logger = [PsGadgetLogger]::new()
        $this.IsInitialized = $false
    }

    # I2CWrite: send bytes to the device, preferring FtdiSharp when available.
    # All internal write operations in derived classes go through this method.
    [bool] I2CWrite([byte[]]$data) {
        try {
            if ($null -ne $this.I2cDevice) {
                $this.I2cDevice.Write($this.I2CAddress, $data)
                return $true
            } else {
                return (Send-MpsseI2CWrite -DeviceHandle $this.FtdiDevice -Address $this.I2CAddress -Data $data)
            }
        } catch {
            $this.Logger.WriteError("I2CWrite failed: $_")
            return $false
        }
    }

    # Initialize() no-arg overload — defined once here for all derived classes.
    # Dispatches to the derived class Initialize([bool]$force) at runtime.
    [bool] Initialize() {
        return $this.Initialize($false)
    }

    # BeginInitialize — shared guard called at the top of every derived
    # Initialize([bool]$force) implementation.
    #
    # Returns $true  = transport is ready; proceed with device-specific init.
    # Returns $false = bail; caller must: return $this.IsInitialized
    #   "already initialized" -> $this.IsInitialized is $true  -> caller returns $true
    #   "no device / failed"  -> $this.IsInitialized is $false -> caller returns $false
    [bool] BeginInitialize([bool]$force) {
        if ($this.IsInitialized -and -not $force) {
            $this.Logger.WriteInfo("Device already initialized")
            return $false
        }
        if (-not $this.FtdiDevice) {
            $this.Logger.WriteError("No FTDI device assigned")
            return $false
        }
        try {
            # Initialize MPSSE I2C only when using raw D2XX bit-bang path.
            # FtdiSharp and .NET IoT backends manage their own MPSSE / I2C init.
            # Skip if Set-PsGadgetFtdiMode already ran Initialize-MpsseI2C this session.
            if ($null -eq $this.I2cDevice) {
                if ($this.FtdiDevice.GpioMethod -ne 'MpsseI2c') {
                    if (-not (Initialize-MpsseI2C -DeviceHandle $this.FtdiDevice -ClockFrequency 100000)) {
                        $this.Logger.WriteError("MPSSE I2C initialization failed")
                        return $false
                    }
                }
            }
            return $true
        } catch {
            $this.Logger.WriteError("MPSSE I2C initialization error: $_")
            return $false
        }
    }
}
