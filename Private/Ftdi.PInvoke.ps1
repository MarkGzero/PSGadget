# Ftdi.PInvoke.ps1
# Native P/Invoke wrappers for libftd2xx.so (Linux/macOS).
#
# When $script:FtdiNativeAvailable is $true (set by Initialize-FtdiNative),
# these wrappers let any code in the module call FT_Open / FT_Close /
# FT_SetBitMode / FT_ReadEE / FT_WriteEE directly against the native library
# without needing FTD2XX_NET.dll (which is Windows-only managed code).
#
# Usage (called from Initialize-FtdiAssembly after NativeLibrary.Load succeeds):
#   Initialize-FtdiNative -LibraryPath '/path/to/libftd2xx.so'
#
# Then any module function can call:
#   $handle = Invoke-FtdiNativeOpen -Index 0
#   Invoke-FtdiNativeSetBitMode -Handle $handle -Mask 0x11 -Mode 0x20
#   Invoke-FtdiNativeClose -Handle $handle

#Requires -Version 5.1

$script:FtdiNativeTypeDefined = $false
$script:FtdiNativeAvailable   = $false
$script:FtdiNativeLibPath     = ''

function Initialize-FtdiNative {
    <#
    .SYNOPSIS
    Registers C# P/Invoke declarations for the native libftd2xx.so.

    .DESCRIPTION
    Calls Add-Type to define the [FtdiNative] class with DllImport attributes
    pointing at the supplied absolute library path.  Safe to call multiple times-
    returns immediately (success) if the type is already defined.

    Sets $script:FtdiNativeAvailable = $true on success.

    .PARAMETER LibraryPath
    Absolute path to libftd2xx.so (or libftd2xx.so.x.y.z).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryPath
    )

    # Already defined in this session
    if ($script:FtdiNativeTypeDefined) {
        $script:FtdiNativeAvailable = $true
        return $true
    }

    # Already registered under a different call (type exists in AppDomain)
    if ('FtdiNative' -as [type]) {
        $script:FtdiNativeTypeDefined = $true
        $script:FtdiNativeAvailable   = $true
        $script:FtdiNativeLibPath     = $LibraryPath
        Write-Verbose "FtdiNative type already registered in AppDomain"
        return $true
    }

    if (-not [System.IO.File]::Exists($LibraryPath)) {
        Write-Warning "Initialize-FtdiNative: library not found at '$LibraryPath'"
        return $false
    }

    # Escape backslashes for the C# string literal (Linux paths never have them,
    # but be safe in case this runs on Windows with a UNC path).
    $escapedPath = $LibraryPath.Replace('\', '\\')

    $csharp = @"
using System;
using System.Runtime.InteropServices;

public static class FtdiNative {
    // FT_STATUS values
    public const int FT_OK                  = 0;
    public const int FT_INVALID_HANDLE      = 1;
    public const int FT_DEVICE_NOT_FOUND    = 2;
    public const int FT_DEVICE_NOT_OPENED   = 3;
    public const int FT_IO_ERROR            = 4;
    public const int FT_INSUFFICIENT_RESOURCES = 5;
    public const int FT_INVALID_PARAMETER   = 6;
    public const int FT_OTHER_ERROR         = 7;

    // SetBitMode modes
    public const byte MODE_RESET            = 0x00;
    public const byte MODE_BITBANG          = 0x01;
    public const byte MODE_MPSSE            = 0x02;
    public const byte MODE_SYNC_BITBANG     = 0x04;
    public const byte MODE_CBUS_BITBANG     = 0x20;
    public const byte MODE_FAST_SERIAL      = 0x40;
    public const byte MODE_SYNC_245         = 0x40;

    // CBUS EEPROM option codes (FT_CBUS_OPTIONS enum)
    public const byte CBUS_TXDEN            = 0;
    public const byte CBUS_PWREN           = 1;
    public const byte CBUS_RXLED           = 2;
    public const byte CBUS_TXLED           = 3;
    public const byte CBUS_TXRXLED        = 4;
    public const byte CBUS_SLEEP           = 5;
    public const byte CBUS_CLK48           = 6;
    public const byte CBUS_CLK24           = 7;
    public const byte CBUS_CLK12           = 8;
    public const byte CBUS_CLK6            = 9;
    public const byte CBUS_IOMODE          = 10;
    public const byte CBUS_BITBANG_WR      = 11;
    public const byte CBUS_BITBANG_RD      = 12;

    // FT232R EEPROM word addresses for CBUS pin mode.
    // Verified from FT_Prog hex dump (AN_107 / 93C46 EEPROM layout):
    //   Word 0x0A: bits[3:0]=CBUS0, bits[7:4]=CBUS1, bits[11:8]=CBUS2, bits[15:12]=CBUS3
    //   Word 0x0B: bits[3:0]=CBUS4
    // Prior constants EE_WORD_CBUS01=7, EE_WORD_CBUS23=8 were wrong (those are config words).
    public const uint EE_WORD_CBUS0123    = 10;  // 0x0A: all of CBUS0-3 packed into one word
    public const uint EE_WORD_CBUS4       = 11;  // 0x0B: bits[3:0]=CBUS4

    [DllImport("$escapedPath", EntryPoint = "FT_Open")]
    public static extern int FT_Open(int deviceNumber, out IntPtr pHandle);

    [DllImport("$escapedPath", EntryPoint = "FT_Close")]
    public static extern int FT_Close(IntPtr ftHandle);

    [DllImport("$escapedPath", EntryPoint = "FT_SetBitMode")]
    public static extern int FT_SetBitMode(IntPtr ftHandle, byte ucMask, byte ucEnable);

    [DllImport("$escapedPath", EntryPoint = "FT_GetBitMode")]
    public static extern int FT_GetBitMode(IntPtr ftHandle, out byte pucMode);

    [DllImport("$escapedPath", EntryPoint = "FT_ReadEE")]
    public static extern int FT_ReadEE(IntPtr ftHandle, uint dwWordOffset, out ushort lpwValue);

    [DllImport("$escapedPath", EntryPoint = "FT_WriteEE")]
    public static extern int FT_WriteEE(IntPtr ftHandle, uint dwWordOffset, ushort wValue);

    [DllImport("$escapedPath", EntryPoint = "FT_EE_UASize")]
    public static extern int FT_EE_UASize(IntPtr ftHandle, out uint lpdwSize);

    [DllImport("$escapedPath", EntryPoint = "FT_GetDeviceInfo")]
    public static extern int FT_GetDeviceInfo(
        IntPtr ftHandle,
        out int lpftDevice,
        out uint lpdwID,
        byte[] pcSerialNumber,
        byte[] pcDescription,
        IntPtr pvDummy);

    [DllImport("$escapedPath", EntryPoint = "FT_EE_Read")]
    public static extern int FT_EE_Read(IntPtr ftHandle, ref FtProgramData pData);

    [DllImport("$escapedPath", EntryPoint = "FT_EE_Program")]
    public static extern int FT_EE_Program(IntPtr ftHandle, ref FtProgramData pData);
}

// FT_PROGRAM_DATA struct -- full layout through Version 5 (FT232H extensions).
// String fields are char* pointers -- callers must allocate and pin buffers before use.
// Field layout follows the D2XX Programmer's Guide §4.4 / §4.6 exactly.
// All Version 3/4/5 fields zero-initialise automatically; safe to use with Version=5
// even when programming an FT232R (libftd2xx ignores inapplicable fields).
[System.Runtime.InteropServices.StructLayout(
    System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct FtProgramData {
    // Header -- must be set by caller
    public uint   Signature1;        // 0x00000000
    public uint   Signature2;        // 0xFFFFFFFF
    public uint   Version;           // 2 for FT232R
    public ushort VendorId;
    public ushort ProductId;
    public IntPtr Manufacturer;      // char* -- allocate >= 32 bytes
    public IntPtr ManufacturerId;    // char* -- allocate >= 16 bytes
    public IntPtr Description;       // char* -- allocate >= 64 bytes
    public IntPtr SerialNumber;      // char* -- allocate >= 16 bytes
    public ushort MaxPower;
    public ushort PnP;
    public ushort SelfPowered;
    public ushort RemoteWakeup;
    // BM extensions
    public byte Rev4;
    public byte IsoIn;
    public byte IsoOut;
    public byte PullDownEnable;
    public byte SerNumEnable;
    public byte USBVersionEnable;
    public ushort USBVersion;
    // FT2232 extensions (Version >= 1)
    public byte Rev5;
    public byte IsoInA;
    public byte IsoInB;
    public byte IsoOutA;
    public byte IsoOutB;
    public byte PullDownEnable5;
    public byte SerNumEnable5;
    public byte USBVersionEnable5;
    public ushort USBVersion5;
    public byte AIsHighCurrent;
    public byte BIsHighCurrent;
    public byte IFAIsFifo;
    public byte IFAIsFifoTar;
    public byte IFAIsFastSer;
    public byte AIsVCP;
    public byte IFBIsFifo;
    public byte IFBIsFifoTar;
    public byte IFBIsFastSer;
    public byte BIsVCP;
    // FT232R extensions (Version >= 2)
    public byte UseExtOsc;
    public byte HighDriveIOs;
    public byte EndpointSize;
    public byte PullDownEnableR;
    public byte SerNumEnableR;
    public byte InvertTXD;
    public byte InvertRXD;
    public byte InvertRTS;
    public byte InvertCTS;
    public byte InvertDTR;
    public byte InvertDSR;
    public byte InvertDCD;
    public byte InvertRI;
    public byte Cbus0;
    public byte Cbus1;
    public byte Cbus2;
    public byte Cbus3;
    public byte Cbus4;
    public byte RIsD2XX;
    // Rev 7 (FT2232H) Extensions [Version >= 3]
    public byte PullDownEnable7;
    public byte SerNumEnable7;
    public byte ALSlowSlew;
    public byte ALSchmittInput;
    public byte ALDriveCurrent;
    public byte AHSlowSlew;
    public byte AHSchmittInput;
    public byte AHDriveCurrent;
    public byte BLSlowSlew;
    public byte BLSchmittInput;
    public byte BLDriveCurrent;
    public byte BHSlowSlew;
    public byte BHSchmittInput;
    public byte BHDriveCurrent;
    public byte IFAIsFifo7;
    public byte IFAIsFifoTar7;
    public byte IFAIsFastSer7;
    public byte AIsVCP7;
    public byte IFBIsFifo7;
    public byte IFBIsFifoTar7;
    public byte IFBIsFastSer7;
    public byte BIsVCP7;
    public byte PowerSaveEnable;
    // Rev 8 (FT4232H) Extensions [Version >= 4]
    public byte PullDownEnable8;
    public byte SerNumEnable8;
    public byte ASlowSlew;
    public byte ASchmittInput;
    public byte ADriveCurrent;
    public byte BSlowSlew;
    public byte BSchmittInput;
    public byte BDriveCurrent;
    public byte CSlowSlew;
    public byte CSchmittInput;
    public byte CDriveCurrent;
    public byte DSlowSlew;
    public byte DSchmittInput;
    public byte DDriveCurrent;
    public byte ARIIsTXDEN;
    public byte BRIIsTXDEN;
    public byte CRIIsTXDEN;
    public byte DRIIsTXDEN;
    public byte AIsVCP8;
    public byte BIsVCP8;
    public byte CIsVCP8;
    public byte DIsVCP8;
    // Rev 9 (FT232H) Extensions [Version >= 5]
    public byte PullDownEnableH;
    public byte SerNumEnableH;
    public byte ACSlowSlewH;
    public byte ACSchmittInputH;
    public byte ACDriveCurrentH;
    public byte ADSlowSlewH;
    public byte ADSchmittInputH;
    public byte ADDriveCurrentH;
    public byte Cbus0H;
    public byte Cbus1H;
    public byte Cbus2H;
    public byte Cbus3H;
    public byte Cbus4H;
    public byte Cbus5H;
    public byte Cbus6H;
    public byte Cbus7H;
    public byte Cbus8H;
    public byte Cbus9H;
    public byte IsFifoH;
    public byte IsFifoTarH;
    public byte IsFastSerH;
    public byte IsFT1248H;
    public byte FT1248CpolH;
    public byte FT1248LsbH;
    public byte FT1248FlowControlH;
    public byte IsVCPH;
    public byte PowerSaveEnableH;
}
"@

    try {
        Add-Type -TypeDefinition $csharp -ErrorAction Stop
        $script:FtdiNativeTypeDefined = $true
        $script:FtdiNativeAvailable   = $true
        $script:FtdiNativeLibPath     = $LibraryPath
        Write-Verbose "FtdiNative P/Invoke type registered (lib: $LibraryPath)"
        return $true
    } catch {
        Write-Warning "Initialize-FtdiNative: Add-Type failed: $_"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Wrapper helpers  (thin PowerShell wrappers around the static C# methods)
# ---------------------------------------------------------------------------

function Invoke-FtdiNativeOpen {
    <#
    .SYNOPSIS
    Opens an FTDI device by zero-based index using the native D2XX library.
    Returns an IntPtr handle, or IntPtr.Zero on failure.
    #>
    [CmdletBinding()]
    [OutputType([IntPtr])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    if (-not $script:FtdiNativeAvailable) {
        throw "FtdiNative not initialised. Call Initialize-FtdiNative first."
    }

    $handle = [IntPtr]::Zero
    $status = [FtdiNative]::FT_Open($Index, [ref]$handle)

    if ($status -ne [FtdiNative]::FT_OK) {
        $msg = switch ($status) {
            ([FtdiNative]::FT_DEVICE_NOT_FOUND)   { "Device not found (index $Index)" }
            ([FtdiNative]::FT_DEVICE_NOT_OPENED)   { "Device could not be opened (already in use?)" }
            default { "FT_Open returned status $status" }
        }
        throw "Invoke-FtdiNativeOpen: $msg"
    }

    Write-Verbose "Invoke-FtdiNativeOpen: device $Index opened, handle=0x$('{0:X}' -f $handle.ToInt64())"
    return $handle
}

function Invoke-FtdiNativeClose {
    <#
    .SYNOPSIS
    Closes a native D2XX device handle.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle
    )

    if ($Handle -eq [IntPtr]::Zero) { return }
    $status = [FtdiNative]::FT_Close($Handle)
    if ($status -ne [FtdiNative]::FT_OK) {
        Write-Warning "Invoke-FtdiNativeClose: FT_Close returned $status"
    } else {
        Write-Verbose "Invoke-FtdiNativeClose: handle closed"
    }
}

function Invoke-FtdiNativeSetBitMode {
    <#
    .SYNOPSIS
    Calls FT_SetBitMode on an open native handle.
    Returns $true on success, throws on error.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle,

        [Parameter(Mandatory = $true)]
        [byte]$Mask,

        [Parameter(Mandatory = $true)]
        [byte]$Mode
    )

    $status = [FtdiNative]::FT_SetBitMode($Handle, $Mask, $Mode)
    if ($status -ne [FtdiNative]::FT_OK) {
        $desc = switch ($status) {
            ([FtdiNative]::FT_OTHER_ERROR) {
                "FT_OTHER_ERROR - CBUS pins may not be programmed as FT_CBUS_IOMODE in the " +
                "device EEPROM. Run: Set-PsGadgetFt232rCbusMode -Index <n> first, then replug."
            }
            default { "FT_SetBitMode returned status $status" }
        }
        throw "Invoke-FtdiNativeSetBitMode: $desc"
    }

    Write-Verbose ("Invoke-FtdiNativeSetBitMode: mode=0x{0:X2} mask=0x{1:X2} OK" -f $Mode, $Mask)
    return $true
}

function Invoke-FtdiNativeGetBitMode {
    <#
    .SYNOPSIS
    Reads the instantaneous pin state byte via FT_GetBitMode.
    For CBUS mode (0x20), bits 0-3 = current logic level of CBUS0-CBUS3.
    #>
    [CmdletBinding()]
    [OutputType([byte])]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle
    )

    [byte]$mode = 0
    $status = [FtdiNative]::FT_GetBitMode($Handle, [ref]$mode)
    if ($status -ne [FtdiNative]::FT_OK) {
        throw "Invoke-FtdiNativeGetBitMode: FT_GetBitMode returned status $status"
    }
    Write-Verbose ("Invoke-FtdiNativeGetBitMode: pinState=0x{0:X2}" -f $mode)
    return $mode
}

function Invoke-FtdiNativeReadEE {
    <#
    .SYNOPSIS
    Reads a single 16-bit word from the device EEPROM at the given word offset.
    Returns the word value as [ushort].
    #>
    [CmdletBinding()]
    [OutputType([ushort])]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle,

        [Parameter(Mandatory = $true)]
        [uint]$WordOffset
    )

    [ushort]$value = 0
    $status = [FtdiNative]::FT_ReadEE($Handle, $WordOffset, [ref]$value)
    if ($status -ne [FtdiNative]::FT_OK) {
        throw "Invoke-FtdiNativeReadEE: FT_ReadEE(offset=$WordOffset) returned status $status"
    }

    Write-Verbose ("Invoke-FtdiNativeReadEE: word[{0}] = 0x{1:X4}" -f $WordOffset, $value)
    return $value
}

function Invoke-FtdiNativeWriteEE {
    <#
    .SYNOPSIS
    Writes a 16-bit word to the device EEPROM at the given word offset.
    CAUTION: EEPROM writes are persistent across power cycles.  Verify values
    offline before writing.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle,

        [Parameter(Mandatory = $true)]
        [uint]$WordOffset,

        [Parameter(Mandatory = $true)]
        [ushort]$Value
    )

    $status = [FtdiNative]::FT_WriteEE($Handle, $WordOffset, $Value)
    if ($status -ne [FtdiNative]::FT_OK) {
        throw "Invoke-FtdiNativeWriteEE: FT_WriteEE(offset=$WordOffset, value=0x$('{0:X4}' -f $Value)) returned status $status"
    }

    Write-Verbose ("Invoke-FtdiNativeWriteEE: word[{0}] written 0x{1:X4}" -f $WordOffset, $Value)
    return $true
}

function Get-FtdiNativeFt232rEeprom {
    <#
    .SYNOPSIS
    Reads FT232R EEPROM fields via native P/Invoke (macOS/Linux).

    .DESCRIPTION
    Returns a PSCustomObject matching the shape of Get-FtdiFt232rEeprom.
    Uses FT_EE_Read with the full FtProgramData struct so all fields including
    string descriptors (Manufacturer, Description, SerialNumber) are populated.

    The device must not be open (no active New-PsGadgetFtdi connection) when this
    is called -- FT_Open does not allow a second handle on the same device.

    .PARAMETER Index
    Zero-based device index (from Get-FtdiDevice).

    .OUTPUTS
    PSCustomObject with EEPROM fields, or throws on P/Invoke error.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    if (-not $script:FtdiNativeAvailable) {
        throw "FtdiNative not initialised. Call Initialize-FtdiNative first."
    }

    $handle = Invoke-FtdiNativeOpen -Index $Index
    try {
        $manufBuf   = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(32)
        $manufIdBuf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        $descBuf    = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(64)
        $serialBuf  = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        try {
            $data = [FtProgramData]::new()
            $data.Signature1     = [uint32]0x00000000
            $data.Signature2     = [uint32]4294967295   # 0xFFFFFFFF
            $data.Version        = [uint32]5
            $data.Manufacturer   = $manufBuf
            $data.ManufacturerId = $manufIdBuf
            $data.Description    = $descBuf
            $data.SerialNumber   = $serialBuf

            $status = [FtdiNative]::FT_EE_Read($handle, [ref]$data)
            if ($status -ne [FtdiNative]::FT_OK) {
                throw "FT_EE_Read failed: status=$status"
            }

            $resolveCbus = {
                param([int]$v)
                if ($script:FT_CBUS_NAMES.ContainsKey($v)) { $script:FT_CBUS_NAMES[$v] }
                else { "UNKNOWN($v)" }
            }

            return [PSCustomObject]@{
                VendorID        = '0x{0:X4}' -f $data.VendorId
                ProductID       = '0x{0:X4}' -f $data.ProductId
                Manufacturer    = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.Manufacturer)
                ManufacturerID  = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.ManufacturerId)
                Description     = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.Description)
                SerialNumber    = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.SerialNumber)
                MaxPower        = $data.MaxPower
                SelfPowered     = [bool]$data.SelfPowered
                RemoteWakeup    = [bool]$data.RemoteWakeup
                UseExtOsc       = [bool]$data.UseExtOsc
                HighDriveIOs    = [bool]$data.HighDriveIOs
                EndpointSize    = $data.EndpointSize
                PullDownEnable  = [bool]$data.PullDownEnableR
                SerNumEnable    = [bool]$data.SerNumEnableR
                InvertTXD       = [bool]$data.InvertTXD
                InvertRXD       = [bool]$data.InvertRXD
                InvertRTS       = [bool]$data.InvertRTS
                InvertCTS       = [bool]$data.InvertCTS
                InvertDTR       = [bool]$data.InvertDTR
                InvertDSR       = [bool]$data.InvertDSR
                InvertDCD       = [bool]$data.InvertDCD
                InvertRI        = [bool]$data.InvertRI
                Cbus0           = & $resolveCbus $data.Cbus0
                Cbus1           = & $resolveCbus $data.Cbus1
                Cbus2           = & $resolveCbus $data.Cbus2
                Cbus3           = & $resolveCbus $data.Cbus3
                Cbus4           = & $resolveCbus $data.Cbus4
                RIsD2XX         = [bool]$data.RIsD2XX
                _NativeRead     = $true
            }
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($manufBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($manufIdBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($descBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($serialBuf)
        }
    } finally {
        Invoke-FtdiNativeClose -Handle $handle
    }
}

function Get-FtdiNativeFt232hEeprom {
    <#
    .SYNOPSIS
    Reads FT232H EEPROM fields via native P/Invoke (macOS/Linux).

    .DESCRIPTION
    Uses FT_EE_Read with the full FtProgramData struct (Version 5) to populate
    all FT232H fields including string descriptors, drive settings, and CBUS pin
    modes.  Returns a PSCustomObject matching the shape of Get-FtdiFt232hEeprom.

    The device must not be open (no active New-PsGadgetFtdi connection) when this
    is called -- FT_Open does not allow a second handle on the same device.

    .PARAMETER Index
    Zero-based device index (from Get-FtdiDevice).

    .OUTPUTS
    PSCustomObject with EEPROM fields, or throws on P/Invoke error.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    if (-not $script:FtdiNativeAvailable) {
        throw "FtdiNative not initialised. Call Initialize-FtdiNative first."
    }

    $handle = Invoke-FtdiNativeOpen -Index $Index
    try {
        $manufBuf   = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(32)
        $manufIdBuf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        $descBuf    = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(64)
        $serialBuf  = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        try {
            $data = [FtProgramData]::new()
            $data.Signature1     = [uint32]0x00000000
            $data.Signature2     = [uint32]4294967295   # 0xFFFFFFFF
            $data.Version        = [uint32]5
            $data.Manufacturer   = $manufBuf
            $data.ManufacturerId = $manufIdBuf
            $data.Description    = $descBuf
            $data.SerialNumber   = $serialBuf

            $status = [FtdiNative]::FT_EE_Read($handle, [ref]$data)
            if ($status -ne [FtdiNative]::FT_OK) {
                throw "FT_EE_Read failed: status=$status"
            }

            $resolveCbus = {
                param([int]$v)
                if ($script:FT_232H_CBUS_NAMES.ContainsKey($v)) { $script:FT_232H_CBUS_NAMES[$v] }
                else { "UNKNOWN($v)" }
            }

            return [PSCustomObject]@{
                VendorID            = '0x{0:X4}' -f $data.VendorId
                ProductID           = '0x{0:X4}' -f $data.ProductId
                Manufacturer        = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.Manufacturer)
                ManufacturerID      = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.ManufacturerId)
                Description         = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.Description)
                SerialNumber        = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($data.SerialNumber)
                MaxPower            = $data.MaxPower
                SelfPowered         = [bool]$data.SelfPowered
                RemoteWakeup        = [bool]$data.RemoteWakeup
                PullDownEnable      = [bool]$data.PullDownEnableH
                SerNumEnable        = [bool]$data.SerNumEnableH
                ACSlowSlew          = [bool]$data.ACSlowSlewH
                ACSchmittInput      = [bool]$data.ACSchmittInputH
                ACDriveCurrent      = $data.ACDriveCurrentH
                ADSlowSlew          = [bool]$data.ADSlowSlewH
                ADSchmittInput      = [bool]$data.ADSchmittInputH
                ADDriveCurrent      = $data.ADDriveCurrentH
                Cbus0               = & $resolveCbus $data.Cbus0H
                Cbus1               = & $resolveCbus $data.Cbus1H
                Cbus2               = & $resolveCbus $data.Cbus2H
                Cbus3               = & $resolveCbus $data.Cbus3H
                Cbus4               = & $resolveCbus $data.Cbus4H
                Cbus5               = & $resolveCbus $data.Cbus5H
                Cbus6               = & $resolveCbus $data.Cbus6H
                Cbus7               = & $resolveCbus $data.Cbus7H
                Cbus8               = & $resolveCbus $data.Cbus8H
                Cbus9               = & $resolveCbus $data.Cbus9H
                IsFifo              = [bool]$data.IsFifoH
                IsFifoTar           = [bool]$data.IsFifoTarH
                IsFastSer           = [bool]$data.IsFastSerH
                IsFT1248            = [bool]$data.IsFT1248H
                FT1248Cpol          = [bool]$data.FT1248CpolH
                FT1248Lsb           = [bool]$data.FT1248LsbH
                FT1248FlowControl   = [bool]$data.FT1248FlowControlH
                IsVCP               = [bool]$data.IsVCPH
                PowerSaveEnable     = [bool]$data.PowerSaveEnableH
                _NativeRead         = $true
            }
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($manufBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($manufIdBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($descBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($serialBuf)
        }
    } finally {
        Invoke-FtdiNativeClose -Handle $handle
    }
}

function Get-FtdiNativeCbusEepromInfo {
    <#
    .SYNOPSIS
    Reads the FT232R EEPROM CBUS pin configuration using native P/Invoke.
    Returns a PSCustomObject with Cbus0..Cbus3 mode names (e.g. FT_CBUS_IOMODE).
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    if (-not $script:FtdiNativeAvailable) {
        throw "FtdiNative not initialised."
    }

    $handle = Invoke-FtdiNativeOpen -Index $Index
    try {
        $wordCbus0123 = Invoke-FtdiNativeReadEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS0123)
        $wordCbus4    = Invoke-FtdiNativeReadEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS4)

        $cbus0 = $wordCbus0123 -band 0x000F
        $cbus1 = ($wordCbus0123 -shr 4) -band 0x000F
        $cbus2 = ($wordCbus0123 -shr 8) -band 0x000F
        $cbus3 = ($wordCbus0123 -shr 12) -band 0x000F
        $cbus4 = $wordCbus4 -band 0x000F

        $nameOf = {
            param([int]$v)
            if ($script:FT_CBUS_NAMES.ContainsKey($v)) { $script:FT_CBUS_NAMES[$v] } else { "UNKNOWN_$v" }
        }

        return [PSCustomObject]@{
            Cbus0     = & $nameOf $cbus0
            Cbus1     = & $nameOf $cbus1
            Cbus2     = & $nameOf $cbus2
            Cbus3     = & $nameOf $cbus3
            Cbus4     = & $nameOf $cbus4
            Cbus0Byte = [byte]$cbus0
            Cbus1Byte = [byte]$cbus1
            Cbus2Byte = [byte]$cbus2
            Cbus3Byte = [byte]$cbus3
            Cbus4Byte = [byte]$cbus4
        }
    } finally {
        Invoke-FtdiNativeClose -Handle $handle
    }
}

function Set-FtdiNativeCbusEeprom {
    <#
    .SYNOPSIS
    Programs FT232R EEPROM CBUS pin modes using native P/Invoke.
    Pins not listed keep their current EEPROM value.

    .DESCRIPTION
    Reads the current EEPROM words for the CBUS pins, patches in the new values
    for the requested pins, and writes back.  Only modified words are written.

    CAUTION: This directly alters non-volatile EEPROM.  The device must be
    unplugged and replugged for the new modes to take effect.

    .PARAMETER Index
    Zero-based device index.

    .PARAMETER Pins
    Which CBUS pin numbers to reconfigure (0-3).

    .PARAMETER Mode
    EEPROM mode name or byte value.  Use 'FT_CBUS_IOMODE' (10) to enable GPIO.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 3)]
        [int[]]$Pins,

        [Parameter(Mandatory = $false)]
        [string]$Mode = 'FT_CBUS_IOMODE'
    )

    if (-not $script:FtdiNativeAvailable) {
        throw "FtdiNative not initialised."
    }

    # Resolve mode byte
    if ($script:FT_CBUS_VALUES.ContainsKey($Mode)) {
        [byte]$modeByte = $script:FT_CBUS_VALUES[$Mode]
    } elseif ([byte]::TryParse($Mode, [ref]([byte]0))) {
        [byte]$modeByte = [byte]$Mode
    } else {
        throw "Unknown CBUS mode '$Mode'. Valid names: $($script:FT_CBUS_VALUES.Keys -join ', ')"
    }

    $handle = Invoke-FtdiNativeOpen -Index $Index
    try {
        # Use FT_EE_Read / FT_EE_Program -- the official D2XX EEPROM programming API.
        # FT_WriteEE only buffers words in libftd2xx RAM; it does not flush to the
        # physical chip on the FT232R internal EEPROM.  FT_EE_Program does a full
        # atomic write-verify cycle that commits to the physical EEPROM.

        # Allocate string buffers for FT_EE_Read output (sizes per D2XX guide §4.4)
        $manufBuf   = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(32)
        $manufIdBuf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        $descBuf    = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(64)
        $serialBuf  = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        try {
            $data = [FtProgramData]::new()
            $data.Signature1     = [uint32]0x00000000
            $data.Signature2     = [uint32]4294967295   # 0xFFFFFFFF
            $data.Version        = [uint32]5  # Version 5 = full struct through FT232H (Rev9)
            $data.Manufacturer   = $manufBuf
            $data.ManufacturerId = $manufIdBuf
            $data.Description    = $descBuf
            $data.SerialNumber   = $serialBuf

            $status = [FtdiNative]::FT_EE_Read($handle, [ref]$data)
            if ($status -ne [FtdiNative]::FT_OK) {
                throw "FT_EE_Read failed: status=$status"
            }
            Write-Verbose ("FT_EE_Read: Cbus0={0} Cbus1={1} Cbus2={2} Cbus3={3} Cbus4={4}" -f
                $data.Cbus0, $data.Cbus1, $data.Cbus2, $data.Cbus3, $data.Cbus4)

            # Patch only the requested CBUS pins
            foreach ($pin in $Pins) {
                switch ($pin) {
                    0 { $data.Cbus0 = $modeByte }
                    1 { $data.Cbus1 = $modeByte }
                    2 { $data.Cbus2 = $modeByte }
                    3 { $data.Cbus3 = $modeByte }
                    4 { $data.Cbus4 = $modeByte }
                }
            }

            $status = [FtdiNative]::FT_EE_Program($handle, [ref]$data)
            if ($status -ne [FtdiNative]::FT_OK) {
                throw "FT_EE_Program failed: status=$status"
            }
            Write-Verbose ("FT_EE_Program: Cbus0={0} Cbus1={1} Cbus2={2} Cbus3={3} Cbus4={4}" -f
                $data.Cbus0, $data.Cbus1, $data.Cbus2, $data.Cbus3, $data.Cbus4)

        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($manufBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($manufIdBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($descBuf)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($serialBuf)
        }

        Write-Host "EEPROM updated. Unplug and replug the device for the new CBUS mode to take effect."
        return $true
    } finally {
        Invoke-FtdiNativeClose -Handle $handle
    }
}
