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

    # Check if cached DLL was compiled against the same libusb path
    $needCompile = $true
    if ((Test-Path $dllPath) -and (Test-Path $pathStamp)) {
        $stamped = (Get-Content $pathStamp -Raw).Trim()
        if ($stamped -eq $libPath) {
            $needCompile = $false
            Write-Verbose "Ftdi.Linux.Eeprom: using cached wrapper DLL from $dllPath"
        } else {
            Write-Verbose "Ftdi.Linux.Eeprom: libusb path changed ($stamped -> $libPath); recompiling"
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
                Set-Content -Path $pathStamp -Value $libPath -Encoding UTF8
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
