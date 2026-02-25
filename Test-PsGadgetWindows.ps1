# Test-PsGadgetWindows.ps1
# Test script for Windows FTDI and logging functionality

function Test-PsGadgetWindows {
    <#
    .SYNOPSIS
    Tests PsGadget functionality on Windows with real FTDI devices.
    
    .DESCRIPTION
    Comprehensive test of PsGadget FTDI enumeration and logging on Windows.
    This function tests both the fixed Windows FTDI implementation and 
    logging functionality to help diagnose any issues.
    
    .EXAMPLE
    Test-PsGadgetWindows -Verbose
    #>
    
    [CmdletBinding()]
    param()
    
    Write-Host "=== PsGadget Windows Testing ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Test 1: Assembly Detection
    Write-Host "1. Testing FTDI Assembly Detection..." -ForegroundColor Yellow
    try {
        $ftdiType = [FTD2XX_NET.FTDI]
        Write-Host "   ✓ FTD2XX_NET.FTDI type available" -ForegroundColor Green
        
        $statusType = [FTD2XX_NET.FTDI+FT_STATUS] 
        Write-Host "   ✓ FT_STATUS enum available" -ForegroundColor Green
        
        $deviceType = [FTD2XX_NET.FTDI+FT_DEVICE]
        Write-Host "   ✓ FT_DEVICE enum available" -ForegroundColor Green
        
    } catch {
        Write-Host "   ✗ FTDI Assembly Error: $_" -ForegroundColor Red
        return
    }
    
    # Test 2: Direct FTDI Enumeration (like old working function)
    Write-Host "`n2. Testing Direct FTDI Enumeration..." -ForegroundColor Yellow
    try {
        $ftdi = [FTD2XX_NET.FTDI]::new()
        [int]$deviceCount = 0
        $status = $ftdi.GetNumberOfDevices([ref]$deviceCount)
        
        if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
            Write-Host "   ✓ Device count: $deviceCount" -ForegroundColor Green
            
            if ($deviceCount -gt 0) {
                $deviceList = New-Object 'FTD2XX_NET.FTDI+FT_DEVICE_INFO_NODE[]' $deviceCount
                $status = $ftdi.GetDeviceList($deviceList)
                
                if ($status -eq [FTD2XX_NET.FTDI+FT_STATUS]::FT_OK) {
                    Write-Host "   ✓ Device list retrieved successfully" -ForegroundColor Green
                    
                    for ($i = 0; $i -lt $deviceList.Count; $i++) {
                        $dev = $deviceList[$i]
                        Write-Host "     Device $i`: $($dev.Description) ($($dev.SerialNumber))" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "   ✗ GetDeviceList failed: $status" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "   ✗ GetNumberOfDevices failed: $status" -ForegroundColor Red
        }
        
        $ftdi.Close() | Out-Null
        
    } catch {
        Write-Host "   ✗ Direct enumeration error: $_" -ForegroundColor Red
    }
    
    # Test 3: PsGadget Module Functions
    Write-Host "`n3. Testing PsGadget Module Functions..." -ForegroundColor Yellow
    try {
        Write-Verbose "Calling List-PsGadgetFtdi..."
        $devices = List-PsGadgetFtdi -Verbose
        
        if ($devices -and $devices.Count -gt 0) {
            Write-Host "   ✓ List-PsGadgetFtdi found $($devices.Count) device(s)" -ForegroundColor Green
            $devices | Format-Table Index, Type, Description, SerialNumber, IsOpen -AutoSize
        } else {
            Write-Host "   ✗ List-PsGadgetFtdi returned no devices" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "   ✗ Module function error: $_" -ForegroundColor Red
    }
    
    # Test 4: Logging Functionality
    Write-Host "`n4. Testing Logging Functionality..." -ForegroundColor Yellow
    try {
        Write-Host "   Creating logger instance..." -ForegroundColor Gray
        $logger = [PsGadgetLogger]::new()
        
        Write-Host "   ✓ Logger created: $($logger.LogFilePath)" -ForegroundColor Green
        
        $logger.WriteInfo("Test log entry from Test-PsGadgetWindows")
        $logger.WriteDebug("Debug message test")
        
        if (Test-Path $logger.LogFilePath) {
            $logSize = (Get-Item $logger.LogFilePath).Length
            Write-Host "   ✓ Log file exists: $logSize bytes" -ForegroundColor Green
            
            Write-Host "   Recent log entries:" -ForegroundColor Gray
            $logEntries = Get-Content $logger.LogFilePath -Tail 5
            foreach ($entry in $logEntries) {
                Write-Host "     $entry" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "   ✗ Log file not created" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "   ✗ Logging error: $_" -ForegroundColor Red
    }
    
    # Test 5: Environment Check
    Write-Host "`n5. Environment Information..." -ForegroundColor Yellow
    $userHome = [Environment]::GetFolderPath("UserProfile")
    $psGadgetDir = Join-Path $userHome ".psgadget"
    $logsDir = Join-Path $psGadgetDir "logs"
    
    Write-Host "   User Home: $userHome" -ForegroundColor Gray
    Write-Host "   PsGadget Dir: $psGadgetDir (exists: $(Test-Path $psGadgetDir))" -ForegroundColor Gray 
    Write-Host "   Logs Dir: $logsDir (exists: $(Test-Path $logsDir))" -ForegroundColor Gray
    
    if (Test-Path $logsDir) {
        $logFiles = Get-ChildItem $logsDir -Filter "*.log" | Sort-Object LastWriteTime -Descending
        Write-Host "   Log files: $($logFiles.Count)" -ForegroundColor Gray
        $logFiles | Select-Object -First 3 | ForEach-Object {
            Write-Host "     $($_.Name) ($($_.Length) bytes, $($_.LastWriteTime))" -ForegroundColor DarkGray
        }
    }
    
    Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
}