# PsGadgetMpy Class  
# Represents a MicroPython device connection with automatic logging

class PsGadgetMpy {
    [string]$SerialPort
    [PsGadgetLogger]$Logger

    # Constructor
    PsGadgetMpy([string]$Port) {
        $this.SerialPort = $Port
        $this.Logger = [PsGadgetLogger]::new()
        
        $this.Logger.WriteInfo("Created PsGadgetMpy instance for serial port: $Port")
    }

    # Get device info
    [hashtable] GetInfo() {
        $this.Logger.WriteInfo("Getting device info for serial port: $($this.SerialPort)")
        
        try {
            # TODO: Call Invoke-MpyBackendGetInfo when implemented
            throw [System.NotImplementedException]::new("MicroPython device info logic not yet implemented")
            
        } catch [System.NotImplementedException] {
            # Return stub device info
            $StubInfo = @{
                Port = $this.SerialPort
                PythonVersion = "MicroPython v1.20.0 (STUB)"
                Board = "Generic Board (STUB)"
                ChipFamily = "Unknown (STUB)"
                FlashSize = "Unknown (STUB)"
                FreeMemory = 50000
                Connected = $true
            }
            
            $this.Logger.WriteInfo("Retrieved device info (STUB MODE): $($StubInfo | ConvertTo-Json -Compress)")
            return $StubInfo
        } catch {
            $this.Logger.WriteError("Failed to get device info: $($_.Exception.Message)")
            throw
        }
    }

    # Invoke MicroPython code
    [string] Invoke([string]$Code) {
        $this.Logger.WriteTrace("Invoking MicroPython code: $($Code.Substring(0, [Math]::Min($Code.Length, 50)))...")
        
        if ([string]::IsNullOrWhiteSpace($Code)) {
            $this.Logger.WriteError("Cannot invoke empty code")
            throw [System.ArgumentException]::new("Code cannot be null or empty")
        }

        try {
            # TODO: Call Invoke-MpyBackendExecute when implemented
            throw [System.NotImplementedException]::new("MicroPython code execution logic not yet implemented")
            
        } catch [System.NotImplementedException] {
            # Return stub response
            $StubResponse = ">>> $Code`r`n# Code executed successfully (STUB MODE)`r`n>>> "
            $this.Logger.WriteInfo("Executed MicroPython code successfully (STUB MODE)")
            return $StubResponse
        } catch {
            $this.Logger.WriteError("Failed to execute MicroPython code: $($_.Exception.Message)")
            throw
        }
    }

    # Push file to device  
    [void] PushFile([string]$LocalPath) {
        $this.Logger.WriteInfo("Pushing file to device: $LocalPath -> $($this.SerialPort)")
        
        if (-not (Test-Path -Path $LocalPath)) {
            $this.Logger.WriteError("Local file not found: $LocalPath")
            throw [System.IO.FileNotFoundException]::new("File not found: $LocalPath")
        }

        try {
            # TODO: Call Invoke-MpyBackendPushFile when implemented  
            throw [System.NotImplementedException]::new("MicroPython file push logic not yet implemented")
            
        } catch [System.NotImplementedException] {
            $FileSize = (Get-Item -Path $LocalPath).Length
            $this.Logger.WriteInfo("Pushed file $LocalPath ($FileSize bytes) to device (STUB MODE)")
        } catch {
            $this.Logger.WriteError("Failed to push file: $($_.Exception.Message)")
            throw
        }
    }

    # Overload: Push file with remote path
    [void] PushFile([string]$LocalPath, [string]$RemotePath) {
        $this.Logger.WriteInfo("Pushing file to device: $LocalPath -> $RemotePath")
        
        if (-not (Test-Path -Path $LocalPath)) {
            $this.Logger.WriteError("Local file not found: $LocalPath")
            throw [System.IO.FileNotFoundException]::new("File not found: $LocalPath")
        }

        try {
            # TODO: Call Invoke-MpyBackendPushFile with remote path when implemented
            throw [System.NotImplementedException]::new("MicroPython file push with remote path logic not yet implemented")
            
        } catch [System.NotImplementedException] {
            $FileSize = (Get-Item -Path $LocalPath).Length
            $this.Logger.WriteInfo("Pushed file $LocalPath ($FileSize bytes) to $RemotePath on device (STUB MODE)")
        } catch {
            $this.Logger.WriteError("Failed to push file: $($_.Exception.Message)")
            throw
        }
    }
}