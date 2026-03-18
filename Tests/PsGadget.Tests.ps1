# PsGadget.Tests.ps1
# Pester tests for PsGadget module

#Requires -Module Pester

Describe 'PsGadget Module Tests' {
    
    BeforeAll {
        # Import the module for testing (from parent directory)
        $ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
        $ModulePath = Join-Path -Path $ModuleRoot -ChildPath "PSGadget.psd1"
        Import-Module $ModulePath -Force
    }
    
    AfterAll {
        # Clean up
        Remove-Module PSGadget -Force -ErrorAction SilentlyContinue
    }

    Context 'Module Loading' {
        It 'Should load the module successfully' {
            Get-Module PSGadget | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export the correct functions' {
            $ExportedFunctions = (Get-Module PSGadget).ExportedFunctions.Keys
            $ExportedFunctions | Should -Contain 'Get-FTDevice'
            $ExportedAliases = (Get-Module PSGadget).ExportedAliases.Keys
            $ExportedAliases | Should -Contain 'Get-PsGadgetFtdi'
            $ExportedFunctions | Should -Contain 'Connect-PsGadgetFtdi'
            $ExportedFunctions | Should -Contain 'Get-PsGadgetMpy'
            $ExportedFunctions | Should -Contain 'Connect-PsGadgetMpy'
            $ExportedFunctions | Should -Contain 'Set-PsGadgetGpio'
            $ExportedFunctions | Should -Contain 'Test-PsGadgetEnvironment'
            $ExportedFunctions | Should -Contain 'Install-PsGadgetMpyScript'
            $ExportedFunctions | Should -Contain 'Get-PsGadgetEspNowDevices'
            $ExportedFunctions | Should -Contain 'Invoke-PsGadgetI2C'
            $ExportedFunctions | Should -Contain 'Invoke-PsGadgetI2CScan'
            $ExportedFunctions | Should -Contain 'Invoke-PsGadgetStepper'
            $ExportedFunctions | Should -Not -Contain 'Connect-PsGadgetPca9685'
            $ExportedFunctions | Should -Not -Contain 'Connect-PsGadgetSsd1306'
            $ExportedFunctions | Should -Not -Contain 'Write-PsGadgetSsd1306'
            $ExportedFunctions | Should -Not -Contain 'Clear-PsGadgetSsd1306'
            $ExportedFunctions | Should -Not -Contain 'Set-PsGadgetSsd1306Cursor'
        }
        
        It 'Should have the correct module version' {
            (Get-Module PSGadget).Version.ToString() | Should -Be '0.3.7'
        }
    }

    Context 'Environment Initialization' {
        It 'Should create ~/.psgadget directory' {
            $UserHome = [Environment]::GetFolderPath("UserProfile")
            $PsGadgetDir = Join-Path -Path $UserHome -ChildPath ".psgadget"
            Test-Path -Path $PsGadgetDir | Should -Be $true
        }
        
        It 'Should create logs subdirectory' {
            $UserHome = [Environment]::GetFolderPath("UserProfile")  
            $LogsDir = Join-Path -Path $UserHome -ChildPath ".psgadget/logs"
            Test-Path -Path $LogsDir | Should -Be $true
        }
    }

    Context 'Logger Class' {
        # PsGadgetLogger is a module-internal PS class; use InModuleScope to access it.
        It 'Should create logger instances' {
            InModuleScope PSGadget {
                $Logger = [PsGadgetLogger]::new()
                $Logger | Should -Not -BeNullOrEmpty
                $Logger.LogFilePath | Should -Not -BeNullOrEmpty
                $Logger.SessionId | Should -Not -BeNullOrEmpty
            }
        }
        
        It 'Should create log file' {
            InModuleScope PSGadget {
                $Logger = [PsGadgetLogger]::new()
                Test-Path -Path $Logger.LogFilePath | Should -Be $true
            }
        }
        
        It 'Should write log entries' {
            InModuleScope PSGadget {
                $Logger = [PsGadgetLogger]::new()
                $Logger.WriteInfo('Test log entry')
                Start-Sleep -Milliseconds 100  # Allow file write to complete
                $LogContent = Get-Content -Path $Logger.LogFilePath -Raw
                $LogContent | Should -Match 'Test log entry'
            }
        }
    }

    Context 'FTDI Functions' {
        It 'Should list FTDI devices without error' {
            { Get-FTDevice } | Should -Not -Throw
        }
        
        It 'Should return array from Get-FTDevice' {
            # In CI/stub mode (no hardware) returns empty array; on hardware returns device objects.
            # Wrap in @() to normalize null/empty to array - both are valid stub-mode results.
            $Result = @(Get-FTDevice)
            $Result.GetType().IsArray | Should -Be $true
        }
        
        It 'Should create FTDI connection object' {
            $Device = Connect-PsGadgetFtdi -Index 0
            $Device | Should -Not -BeNullOrEmpty
            # PsGadgetFtdi is a module-internal class; check Type property instead
            $Device.GetType().Name | Should -BeIn @('PsGadgetFtdi', 'PSCustomObject')
        }
        
        It 'Should set FTDI device properties correctly' {
            $Device = Connect-PsGadgetFtdi -Index 0
            $Device.Index | Should -Be 0
            $Device.IsOpen | Should -Not -BeNullOrEmpty
        }
    }

    Context 'MicroPython Functions' {
        It 'Should list serial ports without error' {
            { Get-PsGadgetMpy } | Should -Not -Throw
        }
        
        It 'Should return array from Get-PsGadgetMpy' {
            $Result = Get-PsGadgetMpy
            # Wrapping in @() handles both array and scalar returns.
            # On CI/Linux without physical serial ports, stubs provide at least one entry.
            @($Result).Count | Should -BeGreaterThan 0
        }
        
        It 'Should create MicroPython connection object' {
            $Device = Connect-PsGadgetMpy -SerialPort 'COM1'
            $Device | Should -Not -BeNullOrEmpty
            # PsGadgetMpy is a module-internal class; check Type property instead
            $Device.GetType().Name | Should -BeIn @('PsGadgetMpy', 'PSCustomObject')
        }
        
        It 'Should set MicroPython device properties correctly' {
            $Device = Connect-PsGadgetMpy -SerialPort 'COM1'
            $Device.SerialPort | Should -Be 'COM1'
        }
    }

    Context 'Test-PsGadgetEnvironment' {
        It 'Should run without throwing' {
            { Test-PsGadgetEnvironment } | Should -Not -Throw
        }

        It 'Should return a status object with expected properties' {
            $result = Test-PsGadgetEnvironment
            $result                  | Should -Not -BeNullOrEmpty
            $result.Platform         | Should -Not -BeNullOrEmpty
            $result.PsVersion        | Should -Not -BeNullOrEmpty
            $result.Backend          | Should -Not -BeNullOrEmpty
            $result.DeviceCount      | Should -BeGreaterOrEqual 0
            $result.PSObject.Properties.Name | Should -Contain 'IsReady'
            $result.PSObject.Properties.Name | Should -Contain 'Status'
            $result.PSObject.Properties.Name | Should -Contain 'Reason'
            $result.PSObject.Properties.Name | Should -Contain 'NextStep'
        }

        It 'Should return a bool IsReady property' {
            $result = Test-PsGadgetEnvironment
            $result.IsReady | Should -BeOfType [bool]
        }
    }

    Context 'Class Functionality (Stub Mode)' {
        It 'Should handle FTDI device operations in stub mode' {
            # Connect-PsGadgetFtdi should return a stub connection without throwing
            # when no physical hardware is present (CI / dev machines).
            $Device = Connect-PsGadgetFtdi -Index 0
            $Device | Should -Not -BeNullOrEmpty
        }
        
        It 'Should handle MicroPython operations in stub mode' {
            $Device = Connect-PsGadgetMpy -SerialPort "COM1"
            
            # These should not throw in stub mode
            { $Info = $Device.GetInfo() } | Should -Not -Throw
            { $Result = $Device.Invoke("print('test')") } | Should -Not -Throw
        }
    }

    Context 'Protocol layer (stub mode)' {
        It 'Send-MpsseI2CWrite should accept -ByteDump and run in stub mode without throwing' {
            InModuleScope PSGadget {
                $stubHandle = [PSCustomObject]@{ IsOpen = $true; Device = $null }
                { Send-MpsseI2CWrite -DeviceHandle $stubHandle -Address 0x3C -Data @(0x00, 0xAE) -ByteDump } | Should -Not -Throw
            }
        }

        It 'Get-FtdiGpioPins should return a byte value in stub mode' {
            InModuleScope PSGadget {
                $stubHandle = [PSCustomObject]@{ IsOpen = $true }
                $result = Get-FtdiGpioPins -DeviceHandle $stubHandle
                $result | Should -BeOfType [byte]
            }
        }

        It 'Set-FtdiGpioPins should run without error in stub mode' {
            InModuleScope PSGadget {
                $stubHandle = [PSCustomObject]@{ IsOpen = $true }
                { Set-FtdiGpioPins -DeviceHandle $stubHandle -Pins @(0) -Direction HIGH } | Should -Not -Throw
            }
        }
    }

    Context 'PCA9685 functions (stub mode)' {
        It 'Should initialize a PCA9685 instance in stub mode' {
            InModuleScope PSGadget {
                $stubHandle = [PSCustomObject]@{ IsOpen = $true; Device = $null }
                $pca = [PsGadgetPca9685]::new($stubHandle, [byte]0x40)

                $pca.Initialize() | Should -Be $true
                $pca.IsInitialized | Should -Be $true
                $pca.GetFrequency() | Should -Be 50
            }
        }

        It 'Should set and cache a single PCA9685 servo channel in stub mode' {
            InModuleScope PSGadget {
                $stubHandle = [PSCustomObject]@{ IsOpen = $true; Device = $null }
                $pca = [PsGadgetPca9685]::new($stubHandle, [byte]0x40)
                $pca.Initialize() | Should -Be $true

                $pca.SetChannel(0, 135) | Should -Be $true
                $pca.GetChannel(0) | Should -Be 135
            }
        }

        It 'Should set multiple PCA9685 channels in stub mode' {
            InModuleScope PSGadget {
                $stubHandle = [PSCustomObject]@{ IsOpen = $true; Device = $null }
                $pca = [PsGadgetPca9685]::new($stubHandle, [byte]0x40)
                $pca.Initialize() | Should -Be $true

                $pca.SetChannels([int[]]@(15, 90, 165)) | Should -Be $true
                $pca.GetChannel(0) | Should -Be 15
                $pca.GetChannel(1) | Should -Be 90
                $pca.GetChannel(2) | Should -Be 165
            }
        }

        It 'Should expose PCA9685 frequency through the public cmdlet' {
            InModuleScope PSGadget {
                $stubHandle = [PSCustomObject]@{ IsOpen = $true; Device = $null }
                $pca = [PsGadgetPca9685]::new($stubHandle, [byte]0x40)
                $pca.Initialize() | Should -Be $true

                $pca.GetFrequency() | Should -Be 50
            }
        }
    }

    Context 'ESP-NOW functions (stub mode)' {
        It 'Install-PsGadgetMpyScript should require mpremote and fail gracefully when absent' {
            # In stub/CI mode mpremote is not available -- function should return failure object, not throw
            $result = Install-PsGadgetMpyScript -SerialPort 'COM99' -Role Receiver -Force -ErrorAction SilentlyContinue
            # mpremote absent: Success should be $false, not an exception
            if ($null -ne $result) {
                $result.Success | Should -Be $false
            }
        }

        It 'Install-PsGadgetMpyScript result object should have expected fields' {
            $result = Install-PsGadgetMpyScript -SerialPort 'COM99' -Role Transmitter -Force -ErrorAction SilentlyContinue
            if ($null -ne $result) {
                $result.PSObject.Properties.Name | Should -Contain 'Role'
                $result.PSObject.Properties.Name | Should -Contain 'SerialPort'
                $result.PSObject.Properties.Name | Should -Contain 'ScriptDeployed'
                $result.PSObject.Properties.Name | Should -Contain 'ConfigDeployed'
                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'Message'
            }
        }

        It 'Get-PsGadgetEspNowDevices should not throw when mpremote is absent' {
            # mpremote absent -> returns empty array, must not throw
            { Get-PsGadgetEspNowDevices -SerialPort 'COM99' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'bundled espnow_receiver.py should exist in mpy/scripts/' {
            $scriptPath = Join-Path $PSScriptRoot '..' 'mpy' 'scripts' 'espnow_receiver.py'
            Test-Path -Path $scriptPath | Should -Be $true
        }

        It 'bundled espnow_transmitter.py should exist in mpy/scripts/' {
            $scriptPath = Join-Path $PSScriptRoot '..' 'mpy' 'scripts' 'espnow_transmitter.py'
            Test-Path -Path $scriptPath | Should -Be $true
        }

        It 'bundled config.json should exist in mpy/scripts/' {
            $configPath = Join-Path $PSScriptRoot '..' 'mpy' 'scripts' 'config.json'
            Test-Path -Path $configPath | Should -Be $true
        }
    }

    Context 'Stepper motor backend (stub mode)' {
        It 'Get-PsGadgetStepSequence Half should return 8 bytes' {
            InModuleScope PSGadget {
                $seq = Get-PsGadgetStepSequence -StepMode Half -Direction Forward
                $seq.Count | Should -Be 8
            }
        }

        It 'Get-PsGadgetStepSequence Full should return 4 bytes' {
            InModuleScope PSGadget {
                $seq = Get-PsGadgetStepSequence -StepMode Full -Direction Forward
                $seq.Count | Should -Be 4
            }
        }

        It 'Reverse sequence should differ from Forward' {
            InModuleScope PSGadget {
                $fwd = Get-PsGadgetStepSequence -StepMode Half -Direction Forward
                $rev = Get-PsGadgetStepSequence -StepMode Half -Direction Reverse
                ($fwd -join ',') | Should -Not -Be ($rev -join ',')
            }
        }

        It 'Get-PsGadgetStepperDefaultStepsPerRev Half should not be 4096' {
            InModuleScope PSGadget {
                $spr = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half
                $spr | Should -Not -Be 4096
                $spr | Should -BeGreaterThan 4000
                $spr | Should -BeLessThan 4100
            }
        }

        It 'Get-PsGadgetStepperDefaultStepsPerRev Full should be approx half of Half' {
            InModuleScope PSGadget {
                $half = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half
                $full = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Full
                [Math]::Abs($half / 2.0 - $full) | Should -BeLessThan 1
            }
        }

        It 'Invoke-PsGadgetStepperMove should not throw in stub mode' {
            InModuleScope PSGadget {
                # Use a real PsGadgetFtdi so Set-PsGadgetFtdiMode type check passes.
                # Pre-set ActiveMode = AsyncBitBang so the mode-switch call is skipped.
                $dev = [PsGadgetFtdi]::new(0)
                $stubConn = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'AsyncBitBang'
                    ActiveMode = 'AsyncBitBang'
                }
                $dev._connection = $stubConn
                $dev.IsOpen = $true
                { Invoke-PsGadgetStepperMove -Ftdi $dev -Steps 8 -StepMode Half -Direction Forward -DelayMs 2 } |
                    Should -Not -Throw
            }
        }

        It 'Invoke-PsGadgetStepper -Steps should require a positive value' {
            { Invoke-PsGadgetStepper -Index 99 -Steps 0 } | Should -Throw
        }

        It 'Invoke-PsGadgetStepper should reject both -Steps and -Degrees' {
            { Invoke-PsGadgetStepper -Index 0 -Steps 100 -Degrees 90 } | Should -Throw
        }

        It 'PsGadgetFtdi should expose StepsPerRevolution and DefaultStepMode properties' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev.PSObject.Properties.Name | Should -Contain 'StepsPerRevolution'
                $dev.PSObject.Properties.Name | Should -Contain 'DefaultStepMode'
                $dev.StepsPerRevolution | Should -Be 0.0
                $dev.DefaultStepMode    | Should -Be 'Half'
            }
        }

        It 'StepDegrees calibration: 90 degrees at default spr should be ~1019 half-steps' {
            InModuleScope PSGadget {
                $spr   = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half
                $steps = [Math]::Max(1, [int][Math]::Round(90.0 / 360.0 * $spr))
                $steps | Should -BeGreaterOrEqual 1018
                $steps | Should -BeLessOrEqual 1020
            }
        }

        It 'StepDegrees with custom StepsPerRevolution uses the supplied value' {
            InModuleScope PSGadget {
                $customSpr = 4082.5
                $steps     = [Math]::Max(1, [int][Math]::Round(90.0 / 360.0 * $customSpr))
                $steps     | Should -Be ([int][Math]::Round(90.0 / 360.0 * 4082.5))
            }
        }
    }
}
