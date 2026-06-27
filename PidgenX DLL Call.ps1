# Decode key based on Source's
# https://github.com/IonBazan/pidgenx
# UpdateProductKey/UpdateProductKeys/PidChecker.cs
# https://forums.mydigitallife.net/threads/simplepidx-simple-yet-powerful-product-key-checker.80300/

using namespace System.Runtime.InteropServices

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class PidGenXWrapper
{
    [DllImport("pidgenx.dll", EntryPoint = "PidGenX", CharSet = CharSet.Auto)]
    public static extern int PidGenX(
        [MarshalAs(UnmanagedType.LPWStr)] string ProductKey,
        [MarshalAs(UnmanagedType.LPWStr)] string PkeyPath,
        [MarshalAs(UnmanagedType.LPWStr)] string MSPID,
        int UnknownUsage,
        IntPtr ProductID,
        IntPtr DigitalProductID,
        IntPtr DigitalProductID4
    );

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DigitalProductId4
    {
        public uint uiSize;
        public ushort MajorVersion;
        public ushort MinorVersion;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public char[] szAdvancedPid;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public char[] szActivationId;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public char[] szOemID;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 260)]
        public char[] szEditionType;

        public byte bIsUpgrade;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 7)]
        public byte[] bReserved;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
        public byte[] bCDKey;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
        public byte[] bCDKey256Hash;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
        public byte[] b256Hash;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public char[] szEditionId;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public char[] szKeyType;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public char[] szEULA;
    }
}
"@
function KeyParser {
    param (
        [string]$key,
        [string]$configPath
    )
    try {
        if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($configPath)) {
            throw "KEY and CONFIG PATH cannot be empty."
        }

        # Allocate unmanaged memory for each structure
        $PIDPtr = [Marshal]::AllocHGlobal(0x32)
        $DPIDPtr = [Marshal]::AllocHGlobal(0xA4)
        $DPID4Ptr = [Marshal]::AllocHGlobal(0x04F8)

        try {
            # Prepare data to copy
            $gpid = New-Object byte[] 0x32
            $opid = New-Object byte[] 0xA4
            $npid = New-Object byte[] 0x04F8

            # Initialize the arrays with dummy data as needed
            $gpid[0] = 0x32
            $opid[0] = 0xA4
            $npid[0] = 0xF8
            $npid[1] = 0x04

            # Copy data to unmanaged memory
            [Marshal]::Copy($gpid, 0, $PIDPtr, $gpid.Length)
            [Marshal]::Copy($opid, 0, $DPIDPtr, $opid.Length)
            [Marshal]::Copy($npid, 0, $DPID4Ptr, $npid.Length)

            # Call the PidGenX function
            $result = [PidGenXWrapper]::PidGenX(
                $key,
                $configPath,
                "00000",
                0,
                $PIDPtr,
                $DPIDPtr,
                $DPID4Ptr
            )

            if ($result -ne 0) {
                # Handle errors based on HRESULT values
                $resultText = switch ($result) {
                    0 { "Operation completed successfully." }
                    -2147024809 { "The parameter is incorrect." }
                    -1979645695 { "Specified key is not valid." }
                    -1979645951 { "Specified key is valid but can't be verified." }
                    -2147024894 { "Can't find specified pkeyconfig file." }
                    -2147024893 { "Specified pkeyconfig path does not exist." }
                    default {
                        if ($result -lt 0) { $result += 4294967296 }
                        "Error: " + ("0x{0:X8}" -f $result)
                    }
                }
                throw "HRESULT: $resultText"
            }

            # Read the data from unmanaged memory
            $dpid4 = [Marshal]::PtrToStructure([System.IntPtr]$DPID4Ptr, [Type][PidGenXWrapper+DigitalProductId4])

            # Convert WCHAR arrays to strings
            $szAdvancedPid = -join ($dpid4.szAdvancedPid -replace '\0', '')
            $szActivationId = -join ($dpid4.szActivationId -replace '\0', '')
            $szEditionType = -join ($dpid4.szEditionType -replace '\0', '')
            $szEditionId = -join ($dpid4.szEditionId -replace '\0', '')
            $szKeyType = -join ($dpid4.szKeyType -replace '\0', '')
            $szEULA = -join ($dpid4.szEULA -replace '\0', '')

            # Prepare results
            $results = @(
                @{ Property = "EULA"; Value = $szEULA },
                @{ Property = "Edition ID"; Value = $szEditionId },
                @{ Property = "Key Type"; Value = $szKeyType },
                @{ Property = "Edition Type"; Value = $szEditionType },
                @{ Property = "Activation ID"; Value = $szActivationId },
                @{ Property = "Advanced PID"; Value = $szAdvancedPid }
            )

            return $results
        } finally {
            # Free the allocated unmanaged memory
            [Marshal]::FreeHGlobal($PIDPtr)
            [Marshal]::FreeHGlobal($DPIDPtr)
            [Marshal]::FreeHGlobal($DPID4Ptr)
        }
    } catch {
        return @(
            @{ Property = "Error"; Value = "$($_.Exception.Message)" }
        )
    }
}