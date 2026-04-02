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

    // FT232R EEPROM word addresses for CBUS pin mode
    public const uint EE_WORD_CBUS01       = 7;   // bits 3:0 = CBUS0, bits 7:4 = CBUS1
    public const uint EE_WORD_CBUS23       = 8;   // bits 3:0 = CBUS2, bits 7:4 = CBUS3

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
        $word7 = Invoke-FtdiNativeReadEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS01)
        $word8 = Invoke-FtdiNativeReadEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS23)

        $cbus0 = $word7 -band 0x0F
        $cbus1 = ($word7 -shr 4) -band 0x0F
        $cbus2 = $word8 -band 0x0F
        $cbus3 = ($word8 -shr 4) -band 0x0F

        $nameOf = {
            param([int]$v)
            if ($script:FT_CBUS_NAMES.ContainsKey($v)) { $script:FT_CBUS_NAMES[$v] } else { "UNKNOWN_$v" }
        }

        return [PSCustomObject]@{
            Cbus0     = & $nameOf $cbus0
            Cbus1     = & $nameOf $cbus1
            Cbus2     = & $nameOf $cbus2
            Cbus3     = & $nameOf $cbus3
            Cbus0Byte = [byte]$cbus0
            Cbus1Byte = [byte]$cbus1
            Cbus2Byte = [byte]$cbus2
            Cbus3Byte = [byte]$cbus3
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
        # Read current EEPROM words
        [ushort]$word7 = Invoke-FtdiNativeReadEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS01)
        [ushort]$word8 = Invoke-FtdiNativeReadEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS23)

        $origWord7 = $word7
        $origWord8 = $word8

        foreach ($pin in $Pins) {
            switch ($pin) {
                0 { $word7 = [ushort](($word7 -band 0xFFF0) -bor ($modeByte -band 0x0F)) }
                1 { $word7 = [ushort](($word7 -band 0xFF0F) -bor (($modeByte -band 0x0F) -shl 4)) }
                2 { $word8 = [ushort](($word8 -band 0xFFF0) -bor ($modeByte -band 0x0F)) }
                3 { $word8 = [ushort](($word8 -band 0xFF0F) -bor (($modeByte -band 0x0F) -shl 4)) }
            }
        }

        if ($word7 -ne $origWord7) {
            Invoke-FtdiNativeWriteEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS01) -Value $word7
            Write-Verbose ("EEPROM word7: 0x{0:X4} -> 0x{1:X4}" -f $origWord7, $word7)
        }
        if ($word8 -ne $origWord8) {
            Invoke-FtdiNativeWriteEE -Handle $handle -WordOffset ([FtdiNative]::EE_WORD_CBUS23) -Value $word8
            Write-Verbose ("EEPROM word8: 0x{0:X4} -> 0x{1:X4}" -f $origWord8, $word8)
        }

        Write-Host "EEPROM updated. Unplug and replug the device for the new CBUS mode to take effect."
        return $true
    } finally {
        Invoke-FtdiNativeClose -Handle $handle
    }
}
