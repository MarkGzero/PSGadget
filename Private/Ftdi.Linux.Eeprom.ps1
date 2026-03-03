# Ftdi.Linux.Eeprom.ps1
# FT232R EEPROM read via libusb-1.0 control transfers for Linux.
#
# Unlike FTD2XX_NET.dll, libusb-1.0 has no kernel32.dll dependency and loads cleanly
# on Linux. EEPROM reads use USB control transfers to endpoint 0, which do NOT require
# claiming any interface -- reads work whether the device is in D2XX mode (ftdi_sio
# unloaded) or VCP mode (ftdi_sio loaded).
#
# USB control transfer for EEPROM read (FTDI vendor command):
#   bmRequestType = 0xC0  (device-to-host, vendor class, device recipient)
#   bRequest      = 0x90  (FTDI_SIO_READ_EEPROM_REQUEST)
#   wValue        = 0
#   wIndex        = word address (0-based 16-bit word offset into EEPROM)
#   data          = 2 bytes (one 16-bit little-endian word)
#
# FT232R EEPROM word map (from pyftdi + Linux kernel ftdi_sio):
#   Word 0x01 (bytes 0x02-0x03): VendorID
#   Word 0x02 (bytes 0x04-0x05): ProductID
#   Word 0x03 (bytes 0x06-0x07): device type/version (bcdDevice)
#   Word 0x04 (bytes 0x08-0x09): byte[0x08] = power supply flags (bit6=SelfPowered, bit5=RemoteWakeup)
#                                              byte[0x09] = MaxPower value (MaxPower_mA = value * 2)
#   Word 0x05 (bytes 0x0a-0x0b): byte[0x0a] = config flags (bit2=PullDownEnable, bit3=SerNumEnable)
#                                              byte[0x0b] = invert flags (bit0=TXD, bit1=RXD,
#                                                           bit2=RTS, bit3=CTS, bit4=DTR,
#                                                           bit5=DSR, bit6=DCD, bit7=RI)
#   Word 0x0a (bytes 0x14-0x15): CBUS pin mux config
#                                  bits  3:0  = CBUS0 mux  (0xa = FT_CBUS_IOMODE)
#                                  bits  7:4  = CBUS1 mux
#                                  bits 11:8  = CBUS2 mux
#                                  bits 15:12 = CBUS3 mux
#   Word 0x0b (bytes 0x16-0x17): bits  3:0  = CBUS4 mux
#
# USB string descriptors (read via libusb, no EEPROM parsing needed):
#   Index 1 = Manufacturer
#   Index 2 = Product description
#   Index 3 = Serial number
#
# Reference: Linux kernel drivers/usb/serial/ftdi_sio.{c,h}
#            pyftdi/eeprom.py cmap entry for device version 0x0600 (FT232R)

#Requires -Version 5.1

# Track whether the libusb P/Invoke type has been registered in this session.
$script:LibusbTypeLoaded = $false

function Initialize-FtdiLinuxLibusb {
    <#
    .SYNOPSIS
    Compiles and loads the libusb-1.0 P/Invoke wrapper DLL (once per user).
    Returns $true on success, $false if libusb is not available.

    .NOTES
    Root cause of "Value cannot be null (Parameter 'path1')":
    Add-Type -TypeDefinition compiles to an in-memory assembly with Assembly.Location == "".
    On .NET 8+, DllImport absolute-path resolution calls Path.GetDirectoryName("") -> null,
    then Path.Combine(null, absPath) throws ArgumentNullException("path1") at first P/Invoke.

    Fix: compile to a real .dll file on disk via Add-Type -OutputAssembly. When the
    assembly has a real Location, DllImport absolute paths resolve correctly. The compiled
    DLL is cached in ~/.psgadget/ and reused across sessions; it is only recompiled when
    the resolved libusb .so path changes (tracked via a companion .path file).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($script:LibusbTypeLoaded) { return $true }

    # Locate libusb-1.0 shared library
    $libLocations = @(
        '/lib/x86_64-linux-gnu/libusb-1.0.so.0',
        '/usr/lib/x86_64-linux-gnu/libusb-1.0.so.0',
        '/lib/aarch64-linux-gnu/libusb-1.0.so.0',
        '/usr/lib/aarch64-linux-gnu/libusb-1.0.so.0',
        '/lib/arm-linux-gnueabihf/libusb-1.0.so.0',
        '/usr/lib/arm-linux-gnueabihf/libusb-1.0.so.0',
        '/usr/local/lib/libusb-1.0.so.0',
        '/usr/local/lib/libusb-1.0.so',
        '/usr/lib/libusb-1.0.so.0',
        '/usr/lib/libusb-1.0.so'
    )
    $libPath = $libLocations | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $libPath) {
        Write-Verbose "Ftdi.Linux.Eeprom: libusb-1.0 not found in standard locations"
        return $false
    }
    Write-Verbose "Ftdi.Linux.Eeprom: using libusb from $libPath"

    # Paths for cached compiled DLL
    $cacheDir  = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.psgadget'
    $dllPath   = Join-Path $cacheDir 'FtdiLinuxLibusb.dll'
    $pathStamp = Join-Path $cacheDir 'FtdiLinuxLibusb.libpath'

    # v2: added libusb_reset_device. Bump this when C# source changes to force DLL recompile.
    $wrapperVersion = 'v2'

    # Check if cached DLL was compiled against the same libusb path and wrapper version
    $needCompile = $true
    if ((Test-Path $dllPath) -and (Test-Path $pathStamp)) {
        $stampLines = (Get-Content $pathStamp -Raw).Trim() -split '\r?\n' | ForEach-Object { $_.Trim() }
        if ($stampLines.Count -ge 2 -and $stampLines[0] -eq $libPath -and $stampLines[1] -eq $wrapperVersion) {
            $needCompile = $false
            Write-Verbose "Ftdi.Linux.Eeprom: using cached wrapper DLL from $dllPath"
        } else {
            Write-Verbose "Ftdi.Linux.Eeprom: wrapper changed or libusb path changed; recompiling DLL"
        }
    }

    $csSource = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class FtdiLinuxLibusb {

    // libusb_device_descriptor - 18 bytes, packed
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct LibusbDeviceDescriptor {
        public byte   bLength;
        public byte   bDescriptorType;
        public ushort bcdUSB;
        public byte   bDeviceClass;
        public byte   bDeviceSubClass;
        public byte   bDeviceProtocol;
        public byte   bMaxPacketSize0;
        public ushort idVendor;
        public ushort idProduct;
        public ushort bcdDevice;
        public byte   iManufacturer;
        public byte   iProduct;
        public byte   iSerialNumber;
        public byte   bNumConfigurations;
    }

    [DllImport("$libPath")]
    public static extern int libusb_init(out IntPtr context);

    [DllImport("$libPath")]
    public static extern void libusb_exit(IntPtr context);

    [DllImport("$libPath")]
    public static extern IntPtr libusb_get_device_list(IntPtr context, out IntPtr list);

    [DllImport("$libPath")]
    public static extern void libusb_free_device_list(IntPtr list, int unref_devices);

    [DllImport("$libPath")]
    public static extern int libusb_get_device_descriptor(IntPtr device, out LibusbDeviceDescriptor desc);

    [DllImport("$libPath")]
    public static extern int libusb_open(IntPtr device, out IntPtr handle);

    [DllImport("$libPath")]
    public static extern void libusb_close(IntPtr handle);

    [DllImport("$libPath")]
    public static extern int libusb_get_string_descriptor_ascii(
        IntPtr handle, byte desc_index, byte[] data, int length);

    [DllImport("$libPath")]
    public static extern int libusb_control_transfer(
        IntPtr handle,
        byte   requestType,
        byte   request,
        ushort value,
        ushort index,
        byte[] data,
        ushort length,
        uint   timeout);

    [DllImport("$libPath")]
    public static extern int libusb_reset_device(IntPtr handle);
}
"@

    try {
        if (-not ([System.Management.Automation.PSTypeName]'FtdiLinuxLibusb').Type) {
            if ($needCompile) {
                if (-not (Test-Path $cacheDir)) {
                    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                }
                # Remove stale DLL before recompiling (Add-Type -OutputAssembly fails if file exists)
                if (Test-Path $dllPath) { Remove-Item $dllPath -Force }
                Write-Verbose "Ftdi.Linux.Eeprom: compiling wrapper DLL to $dllPath"
                Add-Type -TypeDefinition $csSource -OutputAssembly $dllPath -ErrorAction Stop
                Set-Content -Path $pathStamp -Value "$libPath`n$wrapperVersion" -Encoding UTF8
            } else {
                # Load previously compiled DLL from disk
                [System.Reflection.Assembly]::LoadFrom($dllPath) | Out-Null
            }
        }
        $script:LibusbTypeLoaded = $true
        Write-Verbose "Ftdi.Linux.Eeprom: FtdiLinuxLibusb type ready"
        return $true
    } catch {
        Write-Verbose "Ftdi.Linux.Eeprom: failed to load wrapper: $_"
        return $false
    }
}

function Read-FtdiEepromWordLinux {
    <#
    .SYNOPSIS
    Reads one 16-bit word from the FT232R EEPROM via a libusb control transfer.

    .PARAMETER Handle
    Open libusb device handle (IntPtr).

    .PARAMETER WordAddress
    Zero-based 16-bit word address in the EEPROM.

    .OUTPUTS
    [ushort] value, or -1 on error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle,

        [Parameter(Mandatory = $true)]
        [int]$WordAddress
    )

    $buf = [byte[]]::new(2)
    # bmRequestType = 0xC0: device-to-host, vendor, device
    # bRequest      = 0x90: FTDI_SIO_READ_EEPROM_REQUEST
    # wValue        = 0
    # wIndex        = word address
    $transferred = [FtdiLinuxLibusb]::libusb_control_transfer(
        $Handle,
        [byte]0xC0,   # requestType
        [byte]0x90,   # request
        [uint16]0,    # value
        [uint16]$WordAddress,
        $buf,
        [uint16]2,
        [uint32]5000
    )
    if ($transferred -lt 2) {
        Write-Verbose "  EEPROM word 0x$('{0:X2}' -f $WordAddress) read failed (transferred=$transferred)"
        return [int]-1
    }
    # Little-endian 16-bit word
    return [int]([uint16]($buf[0] -bor ($buf[1] -shl 8)))
}

function Get-FtdiFt232rEepromLinux {
    <#
    .SYNOPSIS
    Reads FT232R EEPROM on Linux using libusb-1.0 control transfers.

    .DESCRIPTION
    Returns the same PSCustomObject shape as Get-FtdiFt232rEeprom (Windows/D2XX path)
    so callers do not need to branch on platform.

    Works in both D2XX mode (ftdi_sio unloaded) and VCP mode (ftdi_sio loaded)
    because EEPROM reads target USB endpoint 0 and do not require interface claim.

    .PARAMETER Index
    Zero-based FTDI device index. Used for multi-device disambiguation.

    .PARAMETER SerialNumber
    Serial number string to match. Preferred over Index for disambiguation.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Index = 0,

        [Parameter(Mandatory = $false)]
        [string]$SerialNumber = ''
    )

    if (-not (Initialize-FtdiLinuxLibusb)) {
        Write-Warning (
            "Get-PsGadgetFtdiEeprom (Linux): libusb-1.0 not available.`n" +
            "Install it with: sudo apt-get install libusb-1.0-0"
        )
        return $null
    }

    $ctx     = [IntPtr]::Zero
    $handle  = [IntPtr]::Zero
    $listPtr = [IntPtr]::Zero
    $count   = [IntPtr]::Zero

    try {
        $rc = [FtdiLinuxLibusb]::libusb_init([ref]$ctx)
        if ($rc -ne 0) {
            Write-Warning "Get-PsGadgetFtdiEeprom (Linux): libusb_init failed ($rc)"
            return $null
        }

        # Enumerate all USB devices and find FTDI FT232R(s)
        $count   = [FtdiLinuxLibusb]::libusb_get_device_list($ctx, [ref]$listPtr)
        $numDevs = $count.ToInt64()
        if ($numDevs -le 0) {
            Write-Warning "Get-PsGadgetFtdiEeprom (Linux): no USB devices found (count=$numDevs)"
            return $null
        }

        Write-Verbose "  libusb: $numDevs USB device(s) in enumeration list"

        $ftdiCandidates = [System.Collections.Generic.List[IntPtr]]::new()
        for ($i = 0; $i -lt $numDevs; $i++) {
            $devPtr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($listPtr, $i * [IntPtr]::Size)
            if ($devPtr -eq [IntPtr]::Zero) { break }

            $desc = [FtdiLinuxLibusb+LibusbDeviceDescriptor]::new()
            $rc   = [FtdiLinuxLibusb]::libusb_get_device_descriptor($devPtr, [ref]$desc)
            if ($rc -ne 0) { continue }

            # FTDI VID = 0x0403, FT232R PID = 0x6001
            if ($desc.idVendor -eq 0x0403 -and $desc.idProduct -eq 0x6001) {
                $ftdiCandidates.Add($devPtr)
                Write-Verbose "  Found FTDI FT232R candidate at device list index $i"
            }
        }

        if ($ftdiCandidates.Count -eq 0) {
            Write-Warning "Get-PsGadgetFtdiEeprom (Linux): no FT232R device found (VID=0x0403 PID=0x6001)"
            return $null
        }

        # Select the target device: match by serial number, or fall back to index order
        $targetDev = $null
        $matchedSerial = ''

        foreach ($devPtr in $ftdiCandidates) {
            $testHandle = [IntPtr]::Zero
            $openRc = [FtdiLinuxLibusb]::libusb_open($devPtr, [ref]$testHandle)
            if ($openRc -ne 0) {
                Write-Verbose "  libusb_open failed for candidate ($openRc) - may need udev rules"
                continue
            }

            if ($SerialNumber -ne '') {
                # Read string descriptor 3 = serial number
                $strBuf = [byte[]]::new(64)
                $strRc  = [FtdiLinuxLibusb]::libusb_get_string_descriptor_ascii(
                    $testHandle, [byte]3, $strBuf, $strBuf.Length)
                if ($strRc -gt 0) {
                    $devSerial = [System.Text.Encoding]::ASCII.GetString($strBuf, 0, $strRc).TrimEnd([char]0)
                    Write-Verbose "  Candidate serial: '$devSerial'"
                    if ($devSerial -eq $SerialNumber) {
                        $handle        = $testHandle
                        $testHandle    = [IntPtr]::Zero
                        $targetDev     = $devPtr
                        $matchedSerial = $devSerial
                        break
                    }
                }
            } else {
                # No serial filter: pick by $Index order among FTDI candidates
                if ($ftdiCandidates.IndexOf($devPtr) -eq $Index) {
                    # Read serial for reporting
                    $strBuf = [byte[]]::new(64)
                    $strRc  = [FtdiLinuxLibusb]::libusb_get_string_descriptor_ascii(
                        $testHandle, [byte]3, $strBuf, $strBuf.Length)
                    if ($strRc -gt 0) {
                        $matchedSerial = [System.Text.Encoding]::ASCII.GetString($strBuf, 0, $strRc).TrimEnd([char]0)
                    }
                    $handle     = $testHandle
                    $testHandle = [IntPtr]::Zero
                    $targetDev  = $devPtr
                }
            }

            if ($testHandle -ne [IntPtr]::Zero) {
                [FtdiLinuxLibusb]::libusb_close($testHandle)
            }
        }

        if ($handle -eq [IntPtr]::Zero -or $targetDev -eq $null) {
            $hint = if ($SerialNumber -ne '') { " with serial '$SerialNumber'" } else { " at index $Index" }
            Write-Warning "Get-PsGadgetFtdiEeprom (Linux): could not open FT232R device$hint."
            Write-Warning "If permission denied, add udev rule: echo 'SUBSYSTEM==""usb"", ATTR{idVendor}==""0403"", MODE=""0666""' | sudo tee /etc/udev/rules.d/99-ftdi.rules && sudo udevadm control --reload"
            return $null
        }

        Write-Verbose "  Opened FT232R (serial=$matchedSerial) - reading EEPROM"

        # ---- Read EEPROM words ----
        $w01 = Read-FtdiEepromWordLinux -Handle $handle -WordAddress 0x01   # VID
        $w02 = Read-FtdiEepromWordLinux -Handle $handle -WordAddress 0x02   # PID
        $w04 = Read-FtdiEepromWordLinux -Handle $handle -WordAddress 0x04   # power (low=supply flags, high=MaxPower)
        $w05 = Read-FtdiEepromWordLinux -Handle $handle -WordAddress 0x05   # config (low=misc, high=invert)
        $w0a = Read-FtdiEepromWordLinux -Handle $handle -WordAddress 0x0a   # CBUS0-3
        $w0b = Read-FtdiEepromWordLinux -Handle $handle -WordAddress 0x0b   # CBUS4

        # ---- Read USB string descriptors ----
        $ReadStr = {
            param($Idx)
            $buf = [byte[]]::new(128)
            $rc  = [FtdiLinuxLibusb]::libusb_get_string_descriptor_ascii($handle, [byte]$Idx, $buf, $buf.Length)
            if ($rc -gt 0) { [System.Text.Encoding]::ASCII.GetString($buf, 0, $rc).TrimEnd([char]0) } else { '' }
        }
        $strManufacturer = & $ReadStr 1
        $strProduct      = & $ReadStr 2
        $strSerial       = & $ReadStr 3

        # ---- Decode fields ----
        # VID / PID
        $vid = if ($w01 -ge 0) { '0x{0:X4}' -f $w01 } else { '0x0403' }
        $pid = if ($w02 -ge 0) { '0x{0:X4}' -f $w02 } else { '0x6001' }

        # MaxPower / SelfPowered / RemoteWakeup (word 0x04)
        # byte[0x08] = word4 low byte,  byte[0x09] = word4 high byte
        $powerSupplyByte = if ($w04 -ge 0) { $w04 -band 0xFF } else { 0 }
        $powerMaxByte    = if ($w04 -ge 0) { ($w04 -shr 8) -band 0xFF } else { 0 }
        $selfPowered     = [bool]($powerSupplyByte -band 0x40)   # bit 6
        $remoteWakeup    = [bool]($powerSupplyByte -band 0x20)   # bit 5
        $maxPower        = $powerMaxByte * 2                     # value in mA

        # Config flags (word 0x05 low byte = byte 0x0a)
        $confByte       = if ($w05 -ge 0) { $w05 -band 0xFF } else { 0 }
        $pullDownEnable = [bool]($confByte -band 0x04)   # bit 2
        $serNumEnable   = [bool]($confByte -band 0x08)   # bit 3

        # Invert flags (word 0x05 high byte = byte 0x0b)
        $invertByte = if ($w05 -ge 0) { ($w05 -shr 8) -band 0xFF } else { 0 }
        $invertTXD  = [bool]($invertByte -band 0x01)
        $invertRXD  = [bool]($invertByte -band 0x02)
        $invertRTS  = [bool]($invertByte -band 0x04)
        $invertCTS  = [bool]($invertByte -band 0x08)
        $invertDTR  = [bool]($invertByte -band 0x10)
        $invertDSR  = [bool]($invertByte -band 0x20)
        $invertDCD  = [bool]($invertByte -band 0x40)
        $invertRI   = [bool]($invertByte -band 0x80)

        # CBUS modes (word 0x0a = CBUS0-3, word 0x0b low nibble = CBUS4)
        $ResolveCbus = {
            param($nibble)
            $v = [int]$nibble
            if ($script:FT_CBUS_NAMES.ContainsKey($v)) { $script:FT_CBUS_NAMES[$v] } else { "UNKNOWN($v)" }
        }
        $cbus0Nib = if ($w0a -ge 0) {  $w0a        -band 0x0F } else { -1 }
        $cbus1Nib = if ($w0a -ge 0) { ($w0a -shr 4) -band 0x0F } else { -1 }
        $cbus2Nib = if ($w0a -ge 0) { ($w0a -shr 8) -band 0x0F } else { -1 }
        $cbus3Nib = if ($w0a -ge 0) { ($w0a -shr 12) -band 0x0F } else { -1 }
        $cbus4Nib = if ($w0b -ge 0) {  $w0b        -band 0x0F } else { -1 }

        $cbus0 = if ($cbus0Nib -ge 0) { & $ResolveCbus $cbus0Nib } else { 'READ_ERROR' }
        $cbus1 = if ($cbus1Nib -ge 0) { & $ResolveCbus $cbus1Nib } else { 'READ_ERROR' }
        $cbus2 = if ($cbus2Nib -ge 0) { & $ResolveCbus $cbus2Nib } else { 'READ_ERROR' }
        $cbus3 = if ($cbus3Nib -ge 0) { & $ResolveCbus $cbus3Nib } else { 'READ_ERROR' }
        $cbus4 = if ($cbus4Nib -ge 0) { & $ResolveCbus $cbus4Nib } else { 'READ_ERROR' }

        # RIsD2XX: inferred from runtime - IoT/D2XX backend available means D2XX driver is active.
        # Cannot be read directly from EEPROM without knowing the exact bit position across
        # all FT232R firmware versions; runtime inference is reliable for this field's purpose.
        $rIsD2xx = $script:IotBackendAvailable

        Write-Verbose "  EEPROM read complete: CBUS0=$cbus0 CBUS1=$cbus1 CBUS2=$cbus2 CBUS3=$cbus3 CBUS4=$cbus4"

        return [PSCustomObject]@{
            VendorID        = $vid
            ProductID       = $pid
            Manufacturer    = $strManufacturer
            ManufacturerID  = if ($strManufacturer.Length -ge 2) { $strManufacturer.Substring(0, 2) } else { $strManufacturer }
            Description     = $strProduct
            SerialNumber    = $strSerial
            MaxPower        = $maxPower
            SelfPowered     = $selfPowered
            RemoteWakeup    = $remoteWakeup
            UseExtOsc       = $false    # FT232R-specific bit; position varies by firmware; not decoded
            HighDriveIOs    = $false    # FT232R-specific bit; position varies by firmware; not decoded
            EndpointSize    = 64        # FT232R always 64 bytes; not in accessible EEPROM word
            PullDownEnable  = $pullDownEnable
            SerNumEnable    = $serNumEnable
            InvertTXD       = $invertTXD
            InvertRXD       = $invertRXD
            InvertRTS       = $invertRTS
            InvertCTS       = $invertCTS
            InvertDTR       = $invertDTR
            InvertDSR       = $invertDSR
            InvertDCD       = $invertDCD
            InvertRI        = $invertRI
            Cbus0           = $cbus0
            Cbus1           = $cbus1
            Cbus2           = $cbus2
            Cbus3           = $cbus3
            Cbus4           = $cbus4
            RIsD2XX         = $rIsD2xx
        }

    } catch {
        Write-Error "Get-FtdiFt232rEepromLinux failed: $_"
        return $null
    } finally {
        if ($handle  -ne [IntPtr]::Zero) { [FtdiLinuxLibusb]::libusb_close($handle) }
        if ($listPtr -ne [IntPtr]::Zero) { [FtdiLinuxLibusb]::libusb_free_device_list($listPtr, 1) }
        if ($ctx     -ne [IntPtr]::Zero) { [FtdiLinuxLibusb]::libusb_exit($ctx) }
    }
}

function Write-FtdiEepromWordLinux {
    <#
    .SYNOPSIS
    Writes one 16-bit word to the FT232R EEPROM via a libusb control transfer.

    .PARAMETER Handle
    Open libusb device handle (IntPtr).

    .PARAMETER WordAddress
    Zero-based 16-bit word address in the EEPROM.

    .PARAMETER WordValue
    16-bit value to write.

    .OUTPUTS
    [int] 0 on success, negative libusb error code on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle,

        [Parameter(Mandatory = $true)]
        [int]$WordAddress,

        [Parameter(Mandatory = $true)]
        [uint16]$WordValue
    )

    # bmRequestType = 0x40: host-to-device, vendor, device
    # bRequest      = 0x91: FTDI_SIO_WRITE_EEPROM_REQUEST
    # wValue        = word data to write
    # wIndex        = word address
    # length        = 0 (no data buffer; data is in wValue)
    $emptyBuf = [byte[]]::new(2)   # non-null pointer; length param below is 0
    $rc = [FtdiLinuxLibusb]::libusb_control_transfer(
        $Handle,
        [byte]0x40,           # requestType
        [byte]0x91,           # request: WRITE_EEPROM
        [uint16]$WordValue,   # value: word data
        [uint16]$WordAddress, # index: word address
        $emptyBuf,
        [uint16]0,            # length: 0 (no data phase)
        [uint32]5000
    )
    if ($rc -lt 0) {
        Write-Verbose ("  EEPROM write word 0x{0:X2} = 0x{1:X4} failed (rc={2})" -f $WordAddress, $WordValue, $rc)
    }
    return $rc
}

function Set-FtdiFt232rCbusModeLinux {
    <#
    .SYNOPSIS
    Programs FT232R CBUS pin functions via EEPROM write on Linux using libusb-1.0.

    .DESCRIPTION
    Reads the FT232R EEPROM word at offset 0x0a (CBUS0-3 mux config, 4 nibbles),
    modifies the nibbles for the requested pins, recalculates the EEPROM checksum
    (word 0x3F), and writes both words back. All via libusb control transfers on
    endpoint 0 -- no interface claim required, works whether ftdi_sio is loaded or not.

    EEPROM word 0x0a layout (per Linux kernel ftdi_sio + pyftdi):
      bits  3:0  = CBUS0 mux  (0xa = FT_CBUS_IOMODE)
      bits  7:4  = CBUS1 mux
      bits 11:8  = CBUS2 mux
      bits 15:12 = CBUS3 mux
    EEPROM word 0x0b bits 3:0 = CBUS4 mux (EEPROM-config only; not runtime bit-bangable)

    Checksum algorithm (pyftdi / ftdi_sio):
      checksum = 0xAAAA
      for each word[0..62]: checksum = ROL16(checksum XOR word, 1)
      result written to word[63] (0x3F)

    After writing, the device is reset via libusb_reset_device so the new EEPROM
    settings take effect immediately without physical replug. Pass -ResetDevice $false
    to skip the reset (e.g. when writing multiple fields before applying).

    .PARAMETER Index
    Zero-based FTDI device index.

    .PARAMETER SerialNumber
    Target device serial number (preferred over Index for disambiguation).

    .PARAMETER Pins
    CBUS pin numbers to reconfigure (0-3). Defaults to @(0,1,2,3).

    .PARAMETER Mode
    FT_CBUS_OPTIONS mode name to write. Defaults to FT_CBUS_IOMODE.

    .PARAMETER ResetDevice
    Reset the device after writing to force re-enumeration. Default: $true.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Index = 0,

        [Parameter(Mandatory = $false)]
        [string]$SerialNumber = '',

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3)]
        [int[]]$Pins = @(0, 1, 2, 3),

        [Parameter(Mandatory = $false)]
        [ValidateSet(
            'FT_CBUS_TXDEN','FT_CBUS_PWREN','FT_CBUS_RXLED','FT_CBUS_TXLED',
            'FT_CBUS_TXRXLED','FT_CBUS_SLEEP','FT_CBUS_CLK48','FT_CBUS_CLK24',
            'FT_CBUS_CLK12','FT_CBUS_CLK6','FT_CBUS_IOMODE',
            'FT_CBUS_BITBANG_WR','FT_CBUS_BITBANG_RD'
        )]
        [string]$Mode = 'FT_CBUS_IOMODE',

        [Parameter(Mandatory = $false)]
        [bool]$ResetDevice = $true
    )

    if (-not (Initialize-FtdiLinuxLibusb)) {
        Write-Warning "Set-FtdiFt232rCbusModeLinux: libusb-1.0 not available. Install with: sudo apt-get install libusb-1.0-0"
        return [PSCustomObject]@{ Success = $false; Error = 'libusb not available' }
    }

    if (-not $script:FT_CBUS_VALUES.ContainsKey($Mode)) {
        Write-Error "Unknown CBUS mode '$Mode'"
        return [PSCustomObject]@{ Success = $false; Error = "Unknown mode: $Mode" }
    }
    $targetNibble = [byte]$script:FT_CBUS_VALUES[$Mode]

    $ctx     = [IntPtr]::Zero
    $handle  = [IntPtr]::Zero
    $listPtr = [IntPtr]::Zero
    $count   = [IntPtr]::Zero

    try {
        $rc = [FtdiLinuxLibusb]::libusb_init([ref]$ctx)
        if ($rc -ne 0) {
            Write-Warning "Set-FtdiFt232rCbusModeLinux: libusb_init failed ($rc)"
            return [PSCustomObject]@{ Success = $false; Error = "libusb_init failed: $rc" }
        }

        $count   = [FtdiLinuxLibusb]::libusb_get_device_list($ctx, [ref]$listPtr)
        $numDevs = $count.ToInt64()
        if ($numDevs -le 0) {
            Write-Warning "Set-FtdiFt232rCbusModeLinux: no USB devices found"
            return [PSCustomObject]@{ Success = $false; Error = 'No USB devices found' }
        }

        $ftdiCandidates = [System.Collections.Generic.List[IntPtr]]::new()
        for ($i = 0; $i -lt $numDevs; $i++) {
            $devPtr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($listPtr, $i * [IntPtr]::Size)
            if ($devPtr -eq [IntPtr]::Zero) { break }
            $desc = [FtdiLinuxLibusb+LibusbDeviceDescriptor]::new()
            $rc   = [FtdiLinuxLibusb]::libusb_get_device_descriptor($devPtr, [ref]$desc)
            if ($rc -ne 0) { continue }
            if ($desc.idVendor -eq 0x0403 -and $desc.idProduct -eq 0x6001) {
                $ftdiCandidates.Add($devPtr)
            }
        }

        if ($ftdiCandidates.Count -eq 0) {
            Write-Warning "Set-FtdiFt232rCbusModeLinux: no FT232R device found (VID=0x0403 PID=0x6001)"
            return [PSCustomObject]@{ Success = $false; Error = 'No FT232R found' }
        }

        # Open target device: match by serial or by index order
        foreach ($devPtr in $ftdiCandidates) {
            $testHandle = [IntPtr]::Zero
            $openRc = [FtdiLinuxLibusb]::libusb_open($devPtr, [ref]$testHandle)
            if ($openRc -ne 0) {
                Write-Verbose "  libusb_open failed ($openRc) - check udev rules: SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"0403\", MODE=\"0666\""
                continue
            }

            if ($SerialNumber -ne '') {
                $strBuf = [byte[]]::new(64)
                $strRc  = [FtdiLinuxLibusb]::libusb_get_string_descriptor_ascii($testHandle, [byte]3, $strBuf, $strBuf.Length)
                if ($strRc -gt 0) {
                    $devSerial = [System.Text.Encoding]::ASCII.GetString($strBuf, 0, $strRc).TrimEnd([char]0)
                    if ($devSerial -eq $SerialNumber) {
                        $handle = $testHandle; $testHandle = [IntPtr]::Zero; break
                    }
                }
            } else {
                if ($ftdiCandidates.IndexOf($devPtr) -eq $Index) {
                    $handle = $testHandle; $testHandle = [IntPtr]::Zero; break
                }
            }

            if ($testHandle -ne [IntPtr]::Zero) { [FtdiLinuxLibusb]::libusb_close($testHandle) }
        }

        if ($handle -eq [IntPtr]::Zero) {
            $msg = if ($SerialNumber -ne '') { "serial '$SerialNumber'" } else { "index $Index" }
            Write-Warning "Set-FtdiFt232rCbusModeLinux: could not open device ($msg). Check udev rules."
            return [PSCustomObject]@{ Success = $false; Error = "Device not opened ($msg)" }
        }

        # --- Read all 64 EEPROM words for checksum calculation ---
        $words = [int[]]::new(64)
        for ($i = 0; $i -lt 64; $i++) {
            $words[$i] = Read-FtdiEepromWordLinux -Handle $handle -WordAddress $i
        }

        # Decode current CBUS nibbles from word 0x0a
        $w0a = if ($words[0x0a] -ge 0) { [uint16]$words[0x0a] } else { [uint16]0 }
        $prevNibs = @(
            ($w0a -band 0x000F),
            (($w0a -shr 4) -band 0x000F),
            (($w0a -shr 8) -band 0x000F),
            (($w0a -shr 12) -band 0x000F)
        )
        $prevNames = $prevNibs | ForEach-Object {
            if ($script:FT_CBUS_NAMES.ContainsKey([int]$_)) { $script:FT_CBUS_NAMES[[int]$_] } else { "UNKNOWN(0x$('{0:X}' -f $_))" }
        }

        # Show planned changes
        $pinLines = $Pins | ForEach-Object { "  CBUS$_ : $($prevNames[$_]) -> $Mode" }
        Write-Verbose ("EEPROM CBUS change plan:`n" + ($pinLines -join "`n"))

        $pinNames = ($Pins | ForEach-Object { "CBUS$_" }) -join ', '
        if (-not $PSCmdlet.ShouldProcess("FT232R EEPROM (device index $Index)", "Set $pinNames to $Mode")) {
            return $null
        }

        # Apply new nibble values to word 0x0a
        $new0a = $w0a
        foreach ($pin in $Pins) {
            # Clear the 4-bit nibble for this pin then write the target value
            $shift   = $pin * 4
            $clearMask = [uint16](0xFFFF -bxor ([uint16](0xF -shl $shift)))
            $new0a = [uint16](($new0a -band $clearMask) -bor ([uint16]($targetNibble -shl $shift)))
        }
        Write-Verbose ("  Word 0x0a: 0x{0:X4} -> 0x{1:X4}" -f $w0a, $new0a)

        # Substitute new word into array for checksum recalculation
        $words[0x0a] = [int]$new0a

        # Recalculate checksum over words 0x00-0x3E (Hovold / pyftdi algorithm)
        [uint32]$cs = 0xAAAA
        for ($i = 0; $i -lt 63; $i++) {
            $w = if ($words[$i] -ge 0) { [uint32]($words[$i] -band 0xFFFF) } else { [uint32]0 }
            $cs = ($cs -bxor $w) -band 0xFFFF
            $cs = (($cs -shl 1) -bor ($cs -shr 15)) -band 0xFFFF
        }
        $newChecksum = [uint16]($cs -band 0xFFFF)
        Write-Verbose ("  Checksum: 0x{0:X4} -> 0x{1:X4}" -f $words[0x3F], $newChecksum)

        # Write modified word 0x0a
        $rc0a = Write-FtdiEepromWordLinux -Handle $handle -WordAddress 0x0a -WordValue $new0a
        if ($rc0a -lt 0) {
            throw "EEPROM write word 0x0a failed (libusb rc=$rc0a). Check udev rules: SUBSYSTEM==""usb"", ATTRS{idVendor}==""0403"", MODE=""0666"""
        }

        # Write updated checksum to word 0x3F
        $rc3f = Write-FtdiEepromWordLinux -Handle $handle -WordAddress 0x3F -WordValue $newChecksum
        if ($rc3f -lt 0) {
            throw "EEPROM write word 0x3F (checksum) failed (libusb rc=$rc3f)"
        }

        Write-Verbose "  EEPROM words written successfully"

        # Build restore command(s) for undo
        $restoreLines = @()
        $byMode = @{}
        foreach ($pin in $Pins) {
            $prev = $prevNames[$pin]
            if (-not $byMode.ContainsKey($prev)) { $byMode[$prev] = [System.Collections.Generic.List[int]]::new() }
            $byMode[$prev].Add($pin)
        }
        foreach ($modeName in $byMode.Keys) {
            $pinsStr = '@(' + ($byMode[$modeName] -join ',') + ')'
            $restoreLines += "Set-PsGadgetFt232rCbusMode -Index $Index -Pins $pinsStr -Mode $modeName"
        }

        # Reset device so new EEPROM takes effect without physical replug
        if ($ResetDevice) {
            Write-Verbose "  Resetting device for re-enumeration..."
            [FtdiLinuxLibusb]::libusb_reset_device($handle) | Out-Null
            Write-Host "Device reset. New CBUS settings are active."
        } else {
            Write-Warning "EEPROM written. Replug the USB device for changes to take effect."
        }

        return [PSCustomObject]@{
            Success        = $true
            DeviceIndex    = $Index
            PinsChanged    = $Pins
            NewMode        = $Mode
            PreviousCbus0  = $prevNames[0]
            PreviousCbus1  = $prevNames[1]
            PreviousCbus2  = $prevNames[2]
            PreviousCbus3  = $prevNames[3]
            PortCycled     = $ResetDevice
            RestoreCommand = $restoreLines -join "`n"
            Message        = "EEPROM written. $pinNames set to $Mode."
        }

    } catch {
        Write-Error "Set-FtdiFt232rCbusModeLinux failed: $_"
        return [PSCustomObject]@{ Success = $false; Error = $_.Exception.Message }
    } finally {
        if ($handle  -ne [IntPtr]::Zero) { [FtdiLinuxLibusb]::libusb_close($handle) }
        if ($listPtr -ne [IntPtr]::Zero) { [FtdiLinuxLibusb]::libusb_free_device_list($listPtr, 1) }
        if ($ctx     -ne [IntPtr]::Zero) { [FtdiLinuxLibusb]::libusb_exit($ctx) }
    }
}
