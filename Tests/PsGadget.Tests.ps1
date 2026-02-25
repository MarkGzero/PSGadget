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
        }
        
        It 'Should have the correct module version' {
            (Get-Module PSGadget).Version.ToString() | Should -Be '0.1.0'
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
        It 'Should create logger instances' {
            $Logger = [PsGadgetLogger]::new()
            $Logger | Should -Not -BeNullOrEmpty
            $Logger.LogFilePath | Should -Not -BeNullOrEmpty
            $Logger.SessionId | Should -Not -BeNullOrEmpty
        }
        
        It 'Should create log file' {
            $Logger = [PsGadgetLogger]::new()
            Test-Path -Path $Logger.LogFilePath | Should -Be $true
        }
        
        It 'Should write log entries' {
            $Logger = [PsGadgetLogger]::new()
            $Logger.WriteInfo("Test log entry")
            
            Start-Sleep -Milliseconds 100  # Allow file write to complete
            $LogContent = Get-Content -Path $Logger.LogFilePath -Raw
            $LogContent | Should -Match "Test log entry"
        }
    }

    Context 'FTDI Functions' {
        It 'Should list FTDI devices without error' {
            { List-PsGadgetFtdi } | Should -Not -Throw
        }
        
        It 'Should return array from List-PsGadgetFtdi' {
            $Result = List-PsGadgetFtdi
            $Result | Should -BeOfType [System.Object[]]
        }
        
        It 'Should create FTDI connection object' {
            $Device = Connect-PsGadgetFtdi -Index 0
            $Device | Should -Not -BeNullOrEmpty
            $Device | Should -BeOfType [PsGadgetFtdi]
        }
        
        It 'Should set FTDI device properties correctly' {
            $Device = Connect-PsGadgetFtdi -Index 0
            $Device.Index | Should -Be 0
            $Device.IsOpen | Should -Be $false
            $Device.Logger | Should -BeOfType [PsGadgetLogger]
        }
    }

    Context 'MicroPython Functions' {
        It 'Should list serial ports without error' {
            { List-PsGadgetMpy } | Should -Not -Throw
        }
        
        It 'Should return array from List-PsGadgetMpy' {
            $Result = List-PsGadgetMpy
            $Result | Should -BeOfType [System.Object[]]
        }
        
        It 'Should create MicroPython connection object' {
            $Device = Connect-PsGadgetMpy -SerialPort "COM1"
            $Device | Should -Not -BeNullOrEmpty
            $Device | Should -BeOfType [PsGadgetMpy]
        }
        
        It 'Should set MicroPython device properties correctly' {
            $Device = Connect-PsGadgetMpy -SerialPort "COM1"
            $Device.SerialPort | Should -Be "COM1"
            $Device.Logger | Should -BeOfType [PsGadgetLogger]
        }
    }

    Context 'Class Functionality (Stub Mode)' {
        It 'Should handle FTDI device operations in stub mode' {
            # Connect-PsGadgetFtdi delegates to platform backend which throws
            # NotImplementedException in stub mode - verify graceful error handling
            { Connect-PsGadgetFtdi -Index 0 } | Should -Throw
        }
        
        It 'Should handle MicroPython operations in stub mode' {
            $Device = Connect-PsGadgetMpy -SerialPort "COM1"
            
            # These should not throw in stub mode
            { $Info = $Device.GetInfo() } | Should -Not -Throw
            { $Result = $Device.Invoke("print('test')") } | Should -Not -Throw
        }
    }
}