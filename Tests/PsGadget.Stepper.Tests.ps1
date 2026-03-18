# PsGadget.Stepper.Tests.ps1
# Pester tests for Invoke-PsGadgetStepper, -AcBus MPSSE path,
# Invoke-PsGadgetI2C SSD1306 dispatch, and combined stepper+SSD1306 flow.
# All tests run in stub mode (no physical hardware required).

#Requires -Module Pester

Describe 'Invoke-PsGadgetStepper and SSD1306 combined flow' {

    BeforeAll {
        $ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $ModuleRoot 'PSGadget.psd1') -Force

        # Mock MPSSE device: captures the first Write() call so tests can
        # inspect the opcode byte without requiring physical hardware.
        if (-not ([System.Management.Automation.PSTypeName]'PsGadgetMockMpsseDevice').Type) {
            Add-Type -TypeDefinition @"
public class PsGadgetMockMpsseDevice {
    public byte[] LastWrite = new byte[0];
    public int WriteCount = 0;
    public int Write(byte[] buffer, int bytesToWrite, ref uint bytesWritten) {
        WriteCount++;
        if (WriteCount == 1) {
            LastWrite = new byte[bytesToWrite];
            System.Array.Copy(buffer, LastWrite, bytesToWrite);
        }
        bytesWritten = (uint)bytesToWrite;
        return 0;
    }
    public void Reset() {
        WriteCount = 0;
        LastWrite = new byte[0];
    }
}
"@ -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        Remove-Module PSGadget -Force -ErrorAction SilentlyContinue
    }

    # ---------------------------------------------------------------------------
    Context 'Invoke-PsGadgetStepper result object' {
    # ---------------------------------------------------------------------------

        It 'Should return an object with all expected properties' {
            # Invoke-PsGadgetStepper -PsGadget requires an open device.
            # Use InModuleScope to create a PsGadgetFtdi stub with IsOpen = $true.
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'AsyncBitBang'
                    ActiveMode = 'AsyncBitBang'
                }
                $dev.IsOpen = $true

                $result = Invoke-PsGadgetStepper -PsGadget $dev -Steps 8

                $result | Should -Not -BeNullOrEmpty
                $result.PSObject.Properties.Name | Should -Contain 'StepMode'
                $result.PSObject.Properties.Name | Should -Contain 'Direction'
                $result.PSObject.Properties.Name | Should -Contain 'Steps'
                $result.PSObject.Properties.Name | Should -Contain 'Degrees'
                $result.PSObject.Properties.Name | Should -Contain 'StepsPerRevolution'
                $result.PSObject.Properties.Name | Should -Contain 'DelayMs'
                $result.PSObject.Properties.Name | Should -Contain 'Device'
            }
        }

        It 'Steps result should carry correct StepMode and Direction values' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'AsyncBitBang'
                    ActiveMode = 'AsyncBitBang'
                }
                $dev.IsOpen = $true

                $result = Invoke-PsGadgetStepper -PsGadget $dev -Steps 16 `
                    -StepMode Full -Direction Reverse -DelayMs 2

                $result.StepMode  | Should -Be 'Full'
                $result.Direction | Should -Be 'Reverse'
                $result.Steps     | Should -Be 16
                $result.Degrees   | Should -BeNullOrEmpty
                $result.DelayMs   | Should -Be 2
            }
        }

        It '-Degrees should produce non-null Degrees and non-zero Steps' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'AsyncBitBang'
                    ActiveMode = 'AsyncBitBang'
                }
                $dev.IsOpen = $true

                $result = Invoke-PsGadgetStepper -PsGadget $dev -Degrees 90 -StepMode Half

                $result.Degrees | Should -Be 90.0
                $result.Steps   | Should -BeGreaterThan 0
                # Sanity: 90 deg at ~4075.77 spr should be ~1019 half-steps
                $result.Steps   | Should -BeGreaterThan 1000
                $result.Steps   | Should -BeLessThan 1040
            }
        }

        It 'StepsPerRevolution in result should match calibrated default for Half mode' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'AsyncBitBang'
                    ActiveMode = 'AsyncBitBang'
                }
                $dev.IsOpen = $true

                $result  = Invoke-PsGadgetStepper -PsGadget $dev -Steps 8
                $default = Get-PsGadgetStepperDefaultStepsPerRev -StepMode Half

                [Math]::Abs($result.StepsPerRevolution - $default) | Should -BeLessThan 0.01
            }
        }

        It 'Custom -StepsPerRevolution is reflected in result' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'AsyncBitBang'
                    ActiveMode = 'AsyncBitBang'
                }
                $dev.IsOpen = $true

                $result = Invoke-PsGadgetStepper -PsGadget $dev -Steps 8 -StepsPerRevolution 4000.0

                [Math]::Abs($result.StepsPerRevolution - 4000.0) | Should -BeLessThan 0.01
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context '-AcBus MPSSE opcode selection' {
    # ---------------------------------------------------------------------------

        It 'Default (no -AcBus) sends MPSSE opcode 0x80 (SET_BITS_LOW / ADBUS)' {
            InModuleScope PSGadget {
                $mock = [PsGadgetMockMpsseDevice]::new()
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $mock
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                Invoke-PsGadgetStepperMove -Ftdi $dev -Steps 1 -StepMode Half `
                    -Direction Forward -DelayMs 1 -PinMask 0x0F

                $mock.WriteCount | Should -BeGreaterThan 0
                $mock.LastWrite[0] | Should -Be 0x80
            }
        }

        It '-AcBus sends MPSSE opcode 0x82 (SET_BITS_HIGH / ACBUS)' {
            InModuleScope PSGadget {
                $mock = [PsGadgetMockMpsseDevice]::new()
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $mock
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                Invoke-PsGadgetStepperMove -Ftdi $dev -Steps 1 -StepMode Half `
                    -Direction Forward -DelayMs 1 -PinMask 0x0F -AcBus

                $mock.WriteCount | Should -BeGreaterThan 0
                $mock.LastWrite[0] | Should -Be 0x82
            }
        }

        It '-AcBus with -Steps does not throw in no-Device stub mode' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                { Invoke-PsGadgetStepperMove -Ftdi $dev -Steps 8 -StepMode Half `
                    -Direction Forward -DelayMs 2 -AcBus } | Should -Not -Throw
            }
        }

        It 'Invoke-PsGadgetStepper -AcBus public cmdlet does not throw in stub mode' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                { Invoke-PsGadgetStepper -PsGadget $dev -Steps 8 -AcBus } | Should -Not -Throw
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Invoke-PsGadgetI2C SSD1306 (stub mode)' {
    # ---------------------------------------------------------------------------

        # Shared stub device used across SSD1306 sub-tests.
        BeforeEach {
            InModuleScope PSGadget {
                $script:ssd1306StubDev = [PsGadgetFtdi]::new(0)
                $script:ssd1306StubDev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $script:ssd1306StubDev.IsOpen = $true
            }
        }

        It '-Clear should not throw and return a result object' {
            InModuleScope PSGadget {
                $result = Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Clear
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It '-Text should not throw and return a result object' {
            InModuleScope PSGadget {
                $result = Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Text "Hello" -Page 0
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It '-FontSize 2 should not throw' {
            InModuleScope PSGadget {
                { Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Text "Big" -Page 0 -FontSize 2 } | Should -Not -Throw
            }
        }

        It '-Symbol should not throw and return a result object' {
            InModuleScope PSGadget {
                $result = Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Symbol Warning -Page 0
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It 'Result object should have Module property set to SSD1306' {
            InModuleScope PSGadget {
                $result = Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Text "Test" -Page 0
                $result.Module | Should -Be 'SSD1306'
            }
        }

        It 'Result object should have Address property' {
            InModuleScope PSGadget {
                $result = Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Clear
                $result.PSObject.Properties.Name | Should -Contain 'Address'
                $result.Address | Should -Not -BeNullOrEmpty
            }
        }

        It 'Result object should have Action and Page properties' {
            InModuleScope PSGadget {
                $result = Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Text "Hi" -Page 3
                $result.PSObject.Properties.Name | Should -Contain 'Action'
                $result.PSObject.Properties.Name | Should -Contain 'Page'
                $result.Page | Should -Be 3
            }
        }

        It 'Second call reuses cached SSD1306 instance (no re-init)' {
            InModuleScope PSGadget {
                # First call creates and caches; second call reuses from cache.
                # Both must succeed without throwing.
                { Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Text "First" -Page 0 } | Should -Not -Throw
                { Invoke-PsGadgetI2C -PsGadget $script:ssd1306StubDev `
                    -I2CModule SSD1306 -Text "Second" -Page 0 } | Should -Not -Throw
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Combined stepper + SSD1306 flow (stub mode)' {
    # ---------------------------------------------------------------------------

        It 'SSD1306 write then stepper move on the same device does not throw' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                # Display write first (pre-move intent)
                { Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 `
                    -Text "Moving..." -Page 0 } | Should -Not -Throw

                # Stepper move via ACBUS path
                { Invoke-PsGadgetStepperMove -Ftdi $dev -Steps 8 -StepMode Half `
                    -Direction Forward -DelayMs 2 -AcBus } | Should -Not -Throw
            }
        }

        It 'Stepper move then SSD1306 write on the same device does not throw' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                # Stepper move first
                { Invoke-PsGadgetStepperMove -Ftdi $dev -Steps 8 -StepMode Half `
                    -Direction Forward -DelayMs 2 -AcBus } | Should -Not -Throw

                # Display write after (post-move confirmation)
                { Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 `
                    -Text "Done" -Page 0 } | Should -Not -Throw
            }
        }

        It 'Device remains open after Invoke-PsGadgetI2C with -PsGadget' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 -Text "Open?" -Page 0 | Out-Null

                # Caller owns the device; Invoke-PsGadgetI2C must not close it
                $dev.IsOpen | Should -Be $true
            }
        }

        It 'Full intent-move-confirm sequence completes without error' {
            InModuleScope PSGadget {
                $dev = [PsGadgetFtdi]::new(0)
                $dev._connection = [PSCustomObject]@{
                    IsOpen     = $true
                    Device     = $null
                    GpioMethod = 'MpsseI2c'
                    ActiveMode = 'MpsseI2c'
                }
                $dev.IsOpen = $true

                {
                    # Pre-move: show intent
                    Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 `
                        -Text "FWD 90" -Page 0 | Out-Null

                    # Move: ACBUS stepper
                    Invoke-PsGadgetStepperMove -Ftdi $dev -Steps 1019 -StepMode Half `
                        -Direction Forward -DelayMs 2 -AcBus

                    # Post-move: show result
                    Invoke-PsGadgetI2C -PsGadget $dev -I2CModule SSD1306 `
                        -Text "Done" -Page 0 | Out-Null
                } | Should -Not -Throw
            }
        }
    }
}
