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
            $ExportedFunctions | Should -Contain 'List-PsGadgetFtdi'
            $ExportedFunctions | Should -Contain 'Connect-PsGadgetFtdi'
            $ExportedFunctions | Should -Contain 'List-PsGadgetMpy'
            $ExportedFunctions | Should -Contain 'Connect-PsGadgetMpy'
            $ExportedFunctions | Should -Contain 'Set-PsGadgetGpio'
            $ExportedFunctions | Should -Contain 'Test-PsGadgetSetup'
        }
        
        It 'Should have the correct module version' {
            (Get-Module PSGadget).Version.ToString() | Should -Be '0.3.3'
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
            { List-PsGadgetFtdi } | Should -Not -Throw
        }
        
        It 'Should return array from List-PsGadgetFtdi' {
            $Result = List-PsGadgetFtdi
            # Use GetType() to check array type directly; piping to Should -BeOfType
            # unrolls the array and checks each element, which would fail for PSCustomObject.
            @($Result).Count | Should -BeGreaterThan 0
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
            { List-PsGadgetMpy } | Should -Not -Throw
        }
        
        It 'Should return array from List-PsGadgetMpy' {
            $Result = List-PsGadgetMpy
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

    Context 'Test-PsGadgetSetup' {
        It 'Should run without throwing' {
            { Test-PsGadgetSetup } | Should -Not -Throw
        }

        It 'Should return a status object with expected properties' {
            $result = Test-PsGadgetSetup
            $result                  | Should -Not -BeNullOrEmpty
            $result.Platform         | Should -Not -BeNullOrEmpty
            $result.PsVersion        | Should -Not -BeNullOrEmpty
            $result.Backend          | Should -Not -BeNullOrEmpty
            $result.DeviceCount      | Should -BeGreaterOrEqual 0
            $result.PSObject.Properties.Name | Should -Contain 'IsReady'
        }

        It 'Should return a bool IsReady property' {
            $result = Test-PsGadgetSetup
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
}