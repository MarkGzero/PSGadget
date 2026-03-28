# Changelog

All notable changes to PSGadget are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions match `ModuleVersion` in `PSGadget.psd1`.

---

## Table of Contents

- [Unreleased](#unreleased)
- [0.3.7](#037)
- [0.3.6](#036)
- [0.3.5](#035)
- [0.3.4](#034)

---

## Unreleased

### Added
- Comment-based help and `[OutputType]` for all 19 Public functions (`Get-Help` now works)
- `-PassThru` parameter on `Set-PsGadgetGpio`
- `PSScriptAnalyzer` CI gate (`.github/workflows/lint.yml`)
- PSGallery publish workflow with version gate (`.github/workflows/publish.yml`)
- `CONTRIBUTING.md`
- Pin-out reference table in `Getting-Started.md`
- `#Requires -Version 5.1` on all Public functions that were missing it

### Fixed
- README and Getting-Started install path contradiction resolved (PSGallery + source both documented)
- Quick Start now leads with `Test-PsGadgetEnvironment`
- udev rule `MODE` corrected from `0666` to `0664` with `GROUP=plugdev` in Getting-Started.md
- Stray `.PARAMETER WhatIf` removed from `Set-PsGadgetFt232rCbusMode` CBH (now uses native `-WhatIf` common parameter via `SupportsShouldProcess`)
- `$isWindows` renamed to `$runningOnWindows` in `Get-FtdiDevice.ps1` (PS 6+ readonly variable conflict)

---

## 0.3.7

### Removed
- 9 deprecated SSD1306/PCA9685 wrapper functions

### Changed
- `Send-PsGadgetI2CWrite` demoted to internal private helper
- `Invoke-PsGadgetI2C` is now the sole I2C entry point
- `PsGadgetFtdi.GetDisplay/Display/ClearDisplay` use class methods directly

---

## 0.3.6

### Added
- `Invoke-PsGadgetStepper`: unified stepper motor cmdlet for FT232R/FT232H via async bit-bang
- Bulk USB write for jitter-free step timing
- Calibrated StepsPerRevolution (28BYJ-48: ~4075.77 half-steps, not 4096)
- Angle-based moves via `-Degrees` parameter
- `PsGadgetFtdi.Step()` and `.StepDegrees()` shorthand methods

---

## 0.3.5

### Added
- SSD1306 OLED display integration in `Invoke-PsGadgetI2C`

---

## 0.3.4

### Added
- ESP-NOW wireless telemetry support
- `Get-PsGadgetEspNowDevices`
