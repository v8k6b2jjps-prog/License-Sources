using namespace System
using namespace System.IO
using namespace System.Text
using namespace System.Numerics
using namespace System.Reflection
using namespace System.IO.Compression
using namespace System.Management.Automation
using namespace System.Runtime.InteropServices

enum LicenseCategory {
    KMS38        # Valid until 2038
    KMS4K        # Beyond 2038
    ShortTermVL  # Volume expiring within 6 months
    Unknown
    NonKMS
}
enum LicenseStatusEnum {
    Unlicensed        = 0
    Licensed          = 1
    OOBGrace          = 2
    OOTGrace          = 3
    NonGenuineGrace   = 4
    Notification      = 5
    ExtendedGrace     = 6
}
function New-IntPtr {
    [CmdletBinding(DefaultParameterSetName = 'BySize')]
    param(
        # --- Shared Set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'BySize')]
        [Parameter(Mandatory = $true, ParameterSetName = 'FromCustomObjectList')]
        [int]$Size,

        # --- BySize Set ---
        [Parameter(Mandatory = $false, ParameterSetName = 'BySize')]
        [long]$InitialValue = 0,

        [Parameter(Mandatory = $false, ParameterSetName = 'BySize')]
        [ValidateSet('byte', 'short', 'int', 'long')]
        [string]$ValueType = 'int',

        [Parameter(Mandatory = $false, ParameterSetName = 'BySize')]
        [switch]$WriteSizeAtZero,

        # --- ByData Set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'ByData')]
        [Alias('FromArray')]
        [byte[]]$Data,

        # --- ByObject Set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject')]
        [Alias('FromObject')]
        [object]$Object,

        # --- FromCustomObjectList Set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'FromCustomObjectList')]
        [object[]]$TypeSize,

        [Parameter(Mandatory = $true, ParameterSetName = 'FromCustomObjectList')]
        [object[]]$Values,

        # --- MakeRefType Set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'Release')]
        [Parameter(Mandatory = $true, ParameterSetName = 'MakeRefType')]
        [Alias('FromHandle')]
        [IntPtr]$hHandle,

        [Parameter(Mandatory = $true, ParameterSetName = 'MakeRefType')]
        [switch]$MakeRefType,

        # --- Release Set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'Release')]
        [switch]$Release,

        # --- Shared Parameters ---
        [Parameter(Mandatory = $false, ParameterSetName = 'BySize')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByObject')]
        [switch]$UsePointerSize
    )

    switch ($PsCmdlet.ParameterSetName) {
        
        'FromCustomObjectList' {
            if ($TypeSize.Count -ne $Values.Count) {
                throw [System.ArgumentException]::new("The number of items in -TypeSize ($($TypeSize.Count)) must match the number of items in -Values ($($Values.Count)).")
            }

            $byteSizes = foreach ($element in $TypeSize) {
                if ($element -is [type]) {
                    [Marshal]::SizeOf([Type]$element)
                } else {
                    [int]$element 
                }
            }

            $TotalSize = 0
            foreach ($s in $byteSizes) { $TotalSize += $s }
            if ($Size -gt $TotalSize) {
                $TotalSize = $Size
            }

            $AlignedSize = ($TotalSize + 7) -band (-8)
            $ptr = [Marshal]::AllocHGlobal($AlignedSize)

            0..(($AlignedSize / 8) - 1) | % {
                [Marshal]::WriteInt64($ptr, ($_ * 8), 0L)
            }

            $currentOffset = 0
            for ($i = 0; $i -lt $Values.Count; $i++) {
                $size  = $byteSizes[$i]
                $value = $Values[$i]

                switch ($size) {
                    1 { [Marshal]::WriteByte($ptr, $currentOffset, [byte]$value) }
                    2 { [Marshal]::WriteInt16($ptr, $currentOffset, [int16]$value) }
                    4 { [Marshal]::WriteInt32($ptr, $currentOffset, [int32]$value) }
                    8 { [Marshal]::WriteInt64($ptr, $currentOffset, [int64]$value) }
                    Default {
                        [Marshal]::FreeHGlobal($ptr)
                        throw [System.ArgumentException]::new("Unsupported size element '$size'. Only sizes 1, 2, 4, and 8 are supported.")
                    }
                }
                $currentOffset += $size
            }
            return $ptr
        }

        'MakeRefType' {
            $handlePtr = [Marshal]::AllocHGlobal([IntPtr]::Size)
            [Marshal]::WriteIntPtr($handlePtr, 0, $hHandle)
            return $handlePtr
        }

        'Release' {
            # FIXED: Changed $ReleaseHandle to $hHandle to match parameter definition
            if ($hHandle -and $hHandle -ne [IntPtr]::Zero) {
                [Marshal]::FreeHGlobal($hHandle)
            }
            return
        }

        'ByData' {
            $Size = $Data.Length
            $ptr = [Marshal]::AllocHGlobal($Size)
            [Marshal]::Copy($Data, 0, $ptr, $Size)
            return $ptr
        }

        Default {
            if ($PsCmdlet.ParameterSetName -eq 'ByObject') {
                $Size = [Marshal]::SizeOf($Object)
            }

            if ($Size -le 0) {
                throw [System.ArgumentException]::new("Size must be a positive non-zero integer.")
            }

            $AlignedSize = ($Size + 7) -band (-8)
            $ptr = [Marshal]::AllocHGlobal($AlignedSize)

            0..(($AlignedSize / 8) - 1) | % {
                [Marshal]::WriteInt64($ptr, ($_ * 8), 0L)
            }

            if ($PSBoundParameters.ContainsKey('Object')) {
                [Marshal]::StructureToPtr($Object, $ptr, $false)
            }
            elseif ($WriteSizeAtZero) {
                # --- Guardrails for Header Size Assignment ---
                $requiredSize = if ($UsePointerSize) { [IntPtr]::Size } else { 4 }
                if ($Size -lt $requiredSize) {
                    [Marshal]::FreeHGlobal($ptr)
                    throw [System.ArgumentException]::new("Cannot write header size. Allocated buffer size ($Size bytes) is smaller than required header size ($requiredSize bytes).")
                }

                if ($UsePointerSize) {
                    [Marshal]::WriteIntPtr($ptr, 0, [IntPtr]::new([long]$Size))
                } else {
                    [Marshal]::WriteInt32($ptr, 0, $Size)
                }
            }
            elseif ($InitialValue -ne 0) {
                
                # A. Value Range Check via TryParse
                if (-not $UsePointerSize) {
                    $outOfBounds = switch ($ValueType) {
                        'byte'  { $InitialValue -lt [byte]::MinValue -or $InitialValue -gt [byte]::MaxValue }
                        'short' { $InitialValue -lt [int16]::MinValue -or $InitialValue -gt [int16]::MaxValue }
                        'int'   { $InitialValue -lt [int32]::MinValue -or $InitialValue -gt [int32]::MaxValue }
                        'long'  { $false }
                    }

                    if ($outOfBounds) {
                        [Marshal]::FreeHGlobal($ptr)
                        throw [System.ArgumentOutOfRangeException]::new("The InitialValue ($InitialValue) is outside the valid range allowed for data type '$ValueType'.")
                    }
                }

                # --- New Dynamic -ValueType Space Check logic ---
                $requiredSize = switch ($ValueType) {
                    'byte'  { 1 }
                    'short' { 2 }
                    'int'   { 4 }
                    'long'  { 8 }
                }

                if ($UsePointerSize) { $requiredSize = [IntPtr]::Size }

                # Safety Check: Stop bad allocations from smashing the stack / heap
                if ($Size -lt $requiredSize) {
                    [Marshal]::FreeHGlobal($ptr)
                    throw [System.ArgumentException]::new("Buffer overflow hazard! You allocated $Size byte(s), but requested a -ValueType of '$ValueType' (requires $requiredSize bytes).")
                }

                # Safe Write
                if ($UsePointerSize) {
                    [Marshal]::WriteIntPtr($ptr, 0, [IntPtr]::new($InitialValue))
                } else {
                    switch ($ValueType) {
                        'byte'  { [Marshal]::WriteByte($ptr, 0, [byte]$InitialValue) }
                        'short' { [Marshal]::WriteInt16($ptr, 0, [int16]$InitialValue) }
                        'int'   { [Marshal]::WriteInt32($ptr, 0, [int32]$InitialValue) }
                        'long'  { [Marshal]::WriteInt64($ptr, 0, [int64]$InitialValue) }
                    }
                }
            }

            return $ptr
        }
    }
}
function IsValid-IntPtr {
    param (
        [Parameter(Mandatory = $false)]
        [Object]$handle
    )

    if ($null -eq $handle) {
        return $false
    }

    if ($handle -is [IntPtr]) {
        return ($handle -ne [IntPtr]::Zero)
    }

    if ($handle -is [UIntPtr]) {
        return ($handle -ne [UIntPtr]::Zero)
    }

    if ($handle -is [ValueType]) {
        $tname = $handle.GetType().Name
        if ($tname -in @('SByte','Byte','Int16','UInt16','Int32','UInt32','Int64','UInt64')) {
            if ([IntPtr]::Size -eq 4) {
                # x86: cast to Int32 first
                $val = [int32]$handle
                return ([IntPtr]$val -ne [IntPtr]::Zero)
            }
            else {
                # x64: cast to Int64
                $val = [int64]$handle
                return ([IntPtr]$val -ne [IntPtr]::Zero)
            }
        }
    }

    return $false
}
function Guid-Handler {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [object]$InputData,

        [Parameter(Position = 1)]
        [object]$ReferenceData,

        [Parameter(Position = 2)]
        [ValidateSet("Guid", "ByteArray", "Pointer")]
        [string]$OutputType,

        [Parameter(Position = 3)]
        [switch]$Generate,
        [Parameter(Position = 4)]
        [switch]$Compare
    )

    begin {
        $GuidValue, $GuidBytes, $GuidPtr = `
            $null, $null, $null
        
        $GuidValueNew, $GuidBytesNew, $GuidPtrNew = `
            $null, $null, $null

        Add-Type `
            -AssemblyName System.Runtime.InteropServices
    }

    Process {
        # Case New Guid
        if ($Generate) {
            if ($Compare -or $ReferenceData) {
                Write-Error "can't combine -Compare and [-Generate or -ReferenceData]"
                return
            }
           return [guid]::NewGuid()
        }

        if ($ReferenceData -and !$Compare) {
            Write-Error "-ReferenceData must be used with -Compare"
            return
        }
       
        # Case Guid Value [Struct]
        try {
          if (!$GuidValue -or !$GuidBytes) {
            [Guid]$GuidValue = $InputData
            $GuidBytes = $GuidValue.ToByteArray()
          }
        } catch {}
        
        # Case Guid Bytes Array
        try {
          if (!$GuidValue -or !$GuidBytes) {
            [byte[]]$GuidBytes = $InputData
            try {
              $GuidValue = [Guid]::new($GuidBytes)
            } catch {
              $GuidValue = [Activator]::CreateInstance([type]'System.Guid', $GuidBytes)
            }
          }
        } catch {}
        
        # Case Guid Pointer
        try {
          if (!$GuidValue -or !$GuidBytes) {
            [IntPtr]$GuidPtr = $InputData

            if (!(IsValid-IntPtr $GuidPtr)) {
                Write-Error "Pointer not valid"
                return
            }

            # Alt` [Byte[]]::new(16) -or @(0) * 16
            [byte[]]$GuidBytes = New-Object byte[] 16
            [Marshal]::Copy($GuidPtr, $GuidBytes, 0, 16)

            # Directly Case from Pointer, Work just fine.
            # Avoid use [Guid]::new / [Activator]::CreateInstance
            $GuidValue = [Marshal]::PtrToStructure(
                $GuidPtr, [type][Guid]) # Or [type]'Guid'
          }
        } catch {}

        # Case Equal
        if ($Compare) {
            if (!$ReferenceData) {
                Write-Error "Must Provide ReferenceData Object"
                return
            }
            try {
              if (!$GuidValueNew -or !$GuidBytesNew) {
                [Guid]$GuidValueNew = $ReferenceData
                $GuidBytesNew = $GuidValueNew.ToByteArray()
              }
            } catch {}
            try {
              if (!$GuidValueNew -or !$GuidBytesNew) {
                [byte[]]$GuidBytesNew = $ReferenceData
                try {
                  $GuidValueNew = [Guid]::new($GuidBytesNew)
                } catch {
                  $GuidValueNew = [Activator]::CreateInstance([type]'System.Guid', $GuidBytesNew)
                }
              }
            } catch {}
            try {
              if (!$GuidValueNew -or !$GuidBytesNew) {
                [IntPtr]$GuidPtrNew = $ReferenceData
                if (!(IsValid-IntPtr $GuidPtrNew)) {
                    Write-Error "Pointer not valid"
                    return
                }

                # Alt` [Byte[]]::new(16) -or @(0) * 16
                [byte[]]$GuidBytesNew = New-Object byte[] 16
                [Marshal]::Copy($GuidPtrNew, $GuidBytesNew, 0, 16)

                # Directly Case from Pointer, Work just fine.
                # Avoid use [Guid]::new / [Activator]::CreateInstance
                $GuidValueNew = [Marshal]::PtrToStructure(
                    $GuidPtrNew, [type][Guid]) # Or [type]'Guid'
              }
            } catch {}
            try {
                $IsEqal = [Guid]::Equals($GuidValue, $GuidValueNew)
                return $IsEqal
            }
            catch{}
            return $false
        }

        # Return results
        if ($OutputType -eq "Guid") {
            return $GuidValue
          }
          elseif ($OutputType -eq "ByteArray") {
            return $GuidBytes
          }
          elseif ($OutputType -eq "Pointer") {
            $GuidPtr = if (IsValid-IntPtr $GuidPtr) {
                $GuidPtr 
            } else {
                New-IntPtr -Data $GuidBytes 
            }
            return $GuidPtr
          } else {
            return $null
        }
    }
}
function Import-Block {
    [CmdletBinding(DefaultParameterSetName = "ToFile")]
    param (
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory=$true, Position=1)]
        [string]$PSPath,

        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory=$true, Position=0)]
        [string]$BlockName
    )

    try {
        # Managed .NET Read (significant speed boost over Get-Content)
        $content = [System.IO.File]::ReadAllText($PSPath)

        # Managed .NET Regex for extraction
        $regexPattern = "(?s)## $BlockName ##\r?\n<#\r?\n(.*?)\r?\n#>\r?\n## END ##"
        $match = [System.Text.RegularExpressions.Regex]::Match($content, $regexPattern)

        if (-not $match.Success) {
            Write-Warning "Block '## $BlockName ##' not found."
            return $false
        }

        # Cleanup Base64 and Decompress via .NET Streams
        $b64 = $match.Groups[1].Value -replace "[\r\n\s]", ""
        $data = [System.Convert]::FromBase64String($b64)
        
        $msIn = [System.IO.MemoryStream]::new($data)
        $gzip = [GZipStream]::new($msIn, [CompressionMode]::Decompress)
        $msOut = [System.IO.MemoryStream]::new()
        
        $gzip.CopyTo($msOut)
        $finalBytes = $msOut.ToArray()

        # Explicit cleanup
        $gzip.Dispose(); $msIn.Dispose(); $msOut.Dispose()

        [System.Reflection.Assembly]::Load($finalBytes) | Out-Null
    } catch {
        Write-Error "Failed to process block $BlockName : $($_.Exception.Message)"
        return $false
    }
}
function Get-SLLicensingStatus {
    [CmdletBinding()]
    param(
        [Nullable[Guid]]$ApplicationID = $null,
        [Nullable[Guid]]$SkuID = $null,
        [switch]$Expend,
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    function Test-Guid {
        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [object] $Value
        )
        process {
            if (-not $Value) { return $false }
            try {
                $guid = [Guid]::Parse($Value.ToString())
                return ($guid -ne [Guid]::Empty)
            } catch { return $false }
        }
    }

    # Or both null, Or both same,
    # but If one exist, we can handle things
    # $ApplicationID & [Optional: $skuId]
    # But even with just $skuId, we can get -> $ApplicationID
    # And still continue

    # region --- Handle management ---

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:API::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }
    # endregion

    # region --- Define struct if not already loaded ---
    if (-not ([PSTypeName]'SL_LICENSING_STATUS').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct SL_LICENSING_STATUS
{
    public Guid SkuId;
    public int eStatus;
    public uint dwGraceTime;
    public uint dwTotalGraceDays;
    public int hrReason;
    public ulong qwValidityExpiration;
}
"@
}
    # endregion

    try {
        # region --- Call SL API ---
        $pAppID = [Guid]$ApplicationID
        $pSkuId = if (!$SkuID -or $SkuID -eq [Guid]::Empty) { [IntPtr]::Zero } else { Guid-Handler $SkuID $null Pointer }
        $pnCount = [uint32]0
        $ppStatus = [IntPtr]::Zero

        $result = $Global:API::SLGetLicensingStatusInformation(
            $hSLC,
            [ref]$pAppID,
            $pSkuId,
            [IntPtr]::Zero,
            [ref]$pnCount,
            [ref]$ppStatus
        )

        [marshal]::FreeHGlobal($pSkuId)
        # endregion

        if ($result -ne 0 -or $pnCount -le 0 -or $ppStatus -eq [IntPtr]::Zero) {
            Write-Warning ("SLGetLicensingStatusInformation returned 0x{0:X8}" -f $result)
            return $null
        }

        # region --- Build results ---
        $blockSize = [Marshal]::SizeOf([Type][SL_LICENSING_STATUS])
        $LicensingStatusArr = New-Object SL_LICENSING_STATUS[] $pnCount

        0..($pnCount - 1) | % {
            $LicensingStatusArr[$_] = [Marshal]::PtrToStructure(([IntPtr]::Add($ppStatus, $_ * $blockSize)), [Type]'SL_LICENSING_STATUS')
        }

        if (Test-Guid $SkuID) {
            $ItemsToProcess = $LicensingStatusArr | Where-Object { $_.SkuId -eq $SkuID } | Select-Object -First 1
        } else {
            if ($expend.IsPresent) {
                $ItemsToProcess = $LicensingStatusArr
            } else {
                return $LicensingStatusArr
            }
        }

        $Results = @()
        foreach ($Status in $ItemsToProcess) {
            # --- Logic starts once here ---
            $expirationDateTime = $null
            if ($Status.qwValidityExpiration -gt 0) {
                try { $expirationDateTime = [DateTime]::FromFileTimeUtc($Status.qwValidityExpiration) } catch { }
            }

            $now = Get-Date
            $graceExpiration = $now.AddMinutes($Status.dwGraceTime)
            $daysLeft = ($graceExpiration - $now).Days

            $licenseCategory = $Global:PKeyDatabase | 
                Where-Object ActConfigId -eq "{$($Status.SkuID)}" | 
                Select-Object -First 1 -ExpandProperty ProductKeyType

            switch -Regex ($licenseCategory) {
                'Volume:GVLK' {
                    if ($graceExpiration.Year -gt 2038) { $typeKMS = [LicenseCategory]::KMS4K }
                    elseif ($graceExpiration.Year -in 2037, 2038) { $typeKMS = [LicenseCategory]::KMS38 }
                    elseif ($daysLeft -le 180 -and $daysLeft -ge 0) { $typeKMS = [LicenseCategory]::ShortTermVL }
                    else { $typeKMS = [LicenseCategory]::Unknown }
                }
                default { $typeKMS = [LicenseCategory]::NonKMS }
            }

            $errorMessage = Parse-ErrorMessage -MessageId $Status.hrReason -Flags ACTIVATION
            $hrHex = '0x{0:X8}' -f ($Status.hrReason -band 0xFFFFFFFF)

            $Results += [PSCustomObject]@{
                ID                   = $Status.SkuID
                LicenseStatus        = [Enum]::GetName([LicenseStatusEnum], $Status.eStatus)
                GracePeriodRemaining = $Status.dwGraceTime
                TotalGraceDays       = $Status.dwTotalGraceDays
                EvaluationEndDate    = $expirationDateTime
                LicenseStatusReason  = $hrHex
                LicenseChannel       = $licenseCategory
                LicenseTier          = $typeKMS
                ApiCallHResult       = ('0x{0:X8}' -f $result)
                ErrorMessage         = $errorMessage
            }
        }
        return $Results
        # endregion
    }
    catch {
        Write-Warning "Error while retrieving licensing info: $_"
        return $null
    }
    finally {
        [marshal]::FreeHGlobal($ppStatus)
        $Global:API::SLClose($hSLC) | Out-Null
    }
}
function Retrieve-TokenSKUInfo {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Guid]$SkuId,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Table", "MetaData")]
        [string]$Mode = "Table",

        [LibTSforge.TokenStore.TokenStoreModern]$Store,
        [switch]$KeepAlive
    )

    $SPP = @{
        Pub = "msft:sl/EUL/GENERIC/PUBLIC"; Priv = "msft:sl/EUL/GENERIC/PRIVATE"
        Met = "_--_met"; App = "applicationId"; Pk = "pkeyId"; Fil = "fileId"
    }

    $tsPath = [LibTSforge.SPP.SPPUtils]::GetTokensPath(
        [LibTSforge.Utils]::DetectVersion())
    $tsTmp  = [IO.Path]::GetTempFileName()
    
    try {
        if (-not $Store) {
            [File]::Copy($tsPath, $tsTmp, $true)
            $Store = [LibTSforge.TokenStore.TokenStoreModern]::new($tsTmp)
        }
        if (-not $Store) { throw "Store Init Failed" }

        $GetMeta = { param($id) if($id){ try {[LibTSforge.TokenStore.TokenMeta]::new($Store.GetEntry("$($id)$($SPP.Met)", 'xml').Data).Data} catch {} } }

        $SkuData = &$GetMeta $SkuId
        $Pub     = &$GetMeta $(if($SkuData){ $SkuData[$SPP.Pub] })
        $Priv    = &$GetMeta $(if($SkuData){ $SkuData[$SPP.Priv] })

        if ($Mode -eq "Table") {

            # Mode 1: Conversion Table (Friendly Name -> Value)
            return [PSCustomObject]@{
                ID_SKU          = $SkuId.ToString()
                ID_APPLICATION  = $Pub[$SPP.App]
                ID_PKEY         = $SkuData[$SPP.Pk]
                ID_LICENSE      = @($SkuData[$SPP.Pub], $SkuData[$SPP.Priv])
                ID_LICENSE_FILE = $Pub[$SPP.Fil]
            }
        } 
        elseif ($Mode -eq "MetaData") {

            # Mode 2: Extended Info (Internal Metadata)
            return [PSCustomObject]@{

                # --- Product Identification ---
                productName                = $Pub["productName"]
                Family                     = $Pub["Family"]
                productDescription         = $Pub["productDescription"]
                productAuthor              = $Pub["productAuthor"]
                UXDifferentiator           = $Pub["UXDifferentiator"]
                'win:branding'             = $Priv["win:branding"]

                # --- Licensing Configuration & Logic ---
                licenseVersion             = $Pub["licenseVersion"]
                metaInfoType               = $Pub["metaInfoType"]
                ActivationSequence         = $Pub["ActivationSequence"]
                EnableActivationValidation = $Pub["EnableActivationValidation"]
                EnableNotificationMode     = $Pub["EnableNotificationMode"]
                GraceTimerUniqueness       = $Pub["GraceTimerUniqueness"]
                ValidityTimerUniqueness    = $Pub["ValidityTimerUniqueness"]
                ProductKeyGroupUniqueness  = $Pub["ProductKeyGroupUniqueness"]

                # --- Identity & Global IDs ---
                applicationId              = $Pub["applicationId"]
                productSkuId               = $Pub["productSkuId"]
                fileId                     = $Pub["fileId"]
                pkeyConfigLicenseId        = $Pub["pkeyConfigLicenseId"]
                ValidationTemplateId       = $Pub["ValidationTemplateId"]

                # --- Certificates & Security ---
                issuanceCertificateId      = $Pub["issuanceCertificateId"]
                publicCertificateId        = $Priv["publicCertificateId"]
                privateCertificateId       = $Pub["privateCertificateId"]

                # --- Network Endpoints ---
                licensorUrl                = $Pub["licensorUrl"]
                ValidationURL              = $Pub["ValUrl"]
                UseLicenseURL              = $Pub["PAUrl"]
            }
        }
    }
    catch { Write-Error $_ }
    finally {
        if (!($KeepAlive.IsPresent) -and $Store) { $Store.Dispose() }
        if (Test-Path $tsTmp) { Remove-Item $tsTmp -Force }
    }
}
function Get-SppStoreLicense {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Office", "Windows")]
        [string]$SkuType,

        [switch]$IgnoreEsu,
        [switch]$Dump,
        [switch]$Export
    )

# Tsforge, GetPhoneData Function
function Parse-PhoneData {
    param (
        [Parameter(Mandatory=$true)]
        [byte[]]$Data
    )

    try {
        $guid = [Activator]::CreateInstance([guid], ([byte[]]$Data[0..15]))
        $group = [BitConverter]::ToInt32($Data, 16)
        $serialHigh = [BitConverter]::ToInt32($Data, 20)
        $serialLow  = [BitConverter]::ToInt32($Data, 24)
        $totalSerial = ([int64]$serialHigh * 1000000) + $serialLow
        $upgrade = [BitConverter]::ToInt32($Data, 28)
        $security = [BitConverter]::ToInt64($Data, 32)
        return "GUID: $($guid.ToString().ToUpper()) =======================, < Group: $group, Serial: $totalSerial, Security: $security, Upgrade: $upgrade >"
    }
    catch {
        Write-Error "Failed to parse PhoneData: $_"
    }
}

# https://github.com/WitherOrNot/winkeycheck
function Parse-Token {
    param (
        [ValidateNotNullOrEmpty()]
        [string]$Token
    ) 

    if ($Token -match '&(?<base64>.*)$') {
        $base64Data = $Matches['base64']
    } else {
        Write-Error "Invalid Token Format"
        return
    }

    try {
        $bytes = [Convert]::FromBase64String($base64Data)
        $hash = [System.Numerics.BigInteger]::new($bytes)
    } catch {
        Write-Error "Failed to decode Base64 data"
        return
    }

    $mask30 = ([System.Numerics.BigInteger]1 -shl 30) - 1
    $mask20 = ([System.Numerics.BigInteger]1 -shl 20) - 1
    $mask53 = ([System.Numerics.BigInteger]1 -shl 53) - 1

    $upgrade  = [int]($hash -band 1)
    $serial   = [long](($hash -shr 1) -band $mask30)
    $group    = [long](($hash -shr 31) -band $mask20)
    $security = [long](($hash -shr 51) -band $mask53)

    return [string]::Format("{0}, < Group: {1}, Serial: {2}, Security: {3}, Upgrade: {4} >", $Token, $Group, $serial, $security, $upgrade)
}

# LicensingDiagSpp.dll, LicensingWinRT.dll, SppComApi.dll, SppWinOb.dll
# __int64 __fastcall CProductKeyUtilsT<CEmptyType>::BinaryDecode(__m128i *a1, __int64 a2, unsigned __int16 **a3)
function Parse-abCdKey {
    param (
        [Parameter(Mandatory=$true)]
        [byte[]]$bCDKeyArray,

        [Parameter(Mandatory=$false)]
        [switch]$Log
    )

    # Clone input to v21 (like C++ __m128i copy)
    $keyData = $bCDKeyArray.Clone()

    # +2 for N` Logic Shift right [else fail]
    $Src = New-Object char[] 27

    # Character set for base-24 decoding
    $charset = "BCDFGHJKMPQRTVWXY2346789"

    # Validate input length
    if ($keyData.Length -lt 15 -or $keyData.Length -gt 16) {
        throw "Input data must be a 15 or 16 byte array."
    }

    # Win.8 key check
    if (($keyData[14] -band 0xF0) -ne 0) {
        throw "Failed to decode.!"
    }

    # N-flag
    $T = 0
    $BYTE14 = [byte]$keyData[14]
    $flag = (($BYTE14 -band 0x08) -ne 0)

    # BYTE14(v22) = (4 * (((BYTE14(v22) & 8) != 0) & 2)) | BYTE14(v22) & 0xF7;
    $keyData[14] = (4 * (([int](($BYTE14 -band 8) -ne 0)) -band 2)) -bor ($BYTE14 -band 0xF7)

    # BYTE14(v22) ^= (BYTE14(v22) ^ (4 * ((BYTE14(v22) & 8) != 0))) & 8;
    #$keyData[14] = $BYTE14 -bxor (($BYTE14 -bxor (4 * ([int](($BYTE14 -band 8) -ne 0)))) -band 8)

    # Base-24 decoding loop
    for ($idx = 24; $idx -ge 0; $idx--) {
        $last = 0
        for ($j = 14; $j -ge 0; $j--) {
            $val = $keyData[$j] + ($last -shl 8)
            $keyData[$j] = [math]::Floor($val / 0x18)
            $last = $val % 0x18
        }
        $Src[$idx] = $charset[$last]
    }

    if ($keyData[0] -ne 0) {
        throw "Invalid product key data"
    }

    # Handle N-flag
    $rev = $last -gt 13
    $pos = if ($rev) {25} else {-1}
    if ($Log) {
        $Output = (0..4 | % { -join $Src[(5*$_)..((5*$_)+4)] }) -join '-'
        Write-Warning "Before, $Output"
    }

    # Shift Left, Insert N, At position 0 >> $Src[0]=`N`
    if ($flag -and ($last -le 0)) {
        $Src[0] = [Char]78
    }
    # Shift right, Insert N, Count 1-25 [27 Base,0-24 & 2` Spacer's]
    elseif ($flag -and $rev) {
        while ($pos-- -gt $last){$Src[$pos + 1]=$Src[$pos]}
        $T, $Src[$last+1] = 1, [char]78
    }
    # Shift left, Insert N,
    elseif ($flag -and !$rev) {
        while (++$pos -lt $last){$Src[$pos] = $Src[$pos + 1]}
        $Src[$last] = [char]78
    }

    # Dynamically format 5x5 with dashes
    $Output = (0..4 | % { -join $Src[((5*$_)+$T)..((5*$_)+4+$T)] }) -join '-'
    if ($Log) {
        Write-Warning "After,  $Output"
    }
    return $Output
}

    if (-not ([PSTypeName]'LibTSforge.SPP.ProductConfig').Type) {
        Write-Error "Required assembly 'LibTSforge' not loaded."
        return
    }

    $version    = [LibTSforge.Utils]::DetectVersion()
    $production = [LibTSforge.SPP.SPPUtils]::DetectCurrentKey()
    $psPath     = [LibTSforge.SPP.SPPUtils]::GetPSPath($version)
    $tsPath     = [LibTSforge.SPP.SPPUtils]::GetTokensPath($version)
    $psTmpFile  = [System.IO.Path]::GetTempFileName()
    $tsTmpFile  = [System.IO.Path]::GetTempFileName()

    [File]::Copy($psPath, $psTmpFile, $true) | Out-Null
    [File]::Copy($tsPath, $tsTmpFile, $true) | Out-Null

    try {
        $mappedData    = @{}
        $TokenStore    = [LibTSforge.TokenStore.TokenStoreModern]::new($tsTmpFile)
        $PhysicalStore = [LibTSforge.PhysicalStore.PhysicalStoreModern]::new($psTmpFile, $production, $version)
        if (!$PhysicalStore -or !$TokenStore ) {
            Write-Error "Invalid Store Object"
            return
        }
    } catch {
        return
    }

    $AppID      = if ($SkuType -eq 'Office') { '0ff1ce15-a989-479d-af46-f275c6370663' } else { '55c92734-d682-4d71-983e-d6ec3f16059f' }
    $SkuIDList  = [Guid[]](Get-SLLicensingStatus -ApplicationID $AppID | ? eStatus -NE 0 | select -ExpandProperty SkuId)
    if ($IgnoreEsu) {
        $SkuIDList = $SkuIDList | ? {
            $TokenInfo = Retrieve-TokenSKUInfo -SkuId $_ -Mode MetaData -Store $TokenStore -KeepAlive
            $TokenInfo.productName -notmatch 'Esu' -and $TokenInfo.productDescription -notmatch 'Esu'
            #$Name          = Get-ProductSkuInformation -ActConfigId ($_.Guid) -pwszValueName 'productName'
            #$Description   = Get-ProductSkuInformation -ActConfigId ($_.Guid) -pwszValueName 'Description'
            #$Name -notmatch 'Esu' -and $Description -notmatch 'Esu'
        }
    }
    if (-not $SkuIDList) {
        Write-warning "Invalid Sku List Object"
        return
    }
    $Results = New-Object System.Collections.Generic.List[PSCustomObject]
    try {
        foreach ($Item in $SkuIDList) {
            try {
                # Get SkuID->Pkey From TokenStore
                try {
                  $pkeyID = ''
                  $SkuID = $Item.ToString()
                  $Entry = $TokenStore.GetEntry(($SkuID -split '_')[0] + "_--_met", "xml")
                  if ($Entry) {
                    $pkeyID = ([LibTSforge.TokenStore.TokenMeta]::new($Entry.Data)).Data.pkeyId
                  }
                } catch {
                    write-error $_
                }
                if ([string]::IsNullOrEmpty($pkeyID)) {
                  Write-Error "Could not resolve PKeyID for SkuID: $SkuID"
                  return
                }

                # Get SkuID BLock From TokenStore PhysicalStore
                try {
                  $block = $PhysicalStore.GetBlock("SPPSVC\$AppId\$SkuId", $pkeyId)
                  if (-not $block) { throw "Blob not found for $SkuId" }
                } catch {
                    $bindingFlags = [Reflection.BindingFlags]"NonPublic, Instance"
                    $fieldInfo = $PhysicalStore.GetType().GetField("Data", $bindingFlags)
                    $privateData = $fieldInfo.GetValue($PhysicalStore)
                    $realKey = $privateData.Keys | Where-Object { $_ -eq "SPPSVC\$AppId\$SkuId" }
                    $block = $privateData[$realKey] | ? ValueAsStr -Match $pkeyId
                }
                if (-not $block) { throw "Blob not found for $SkuId" }

                if ($Dump.IsPresent) {
                    $bindingFlags = [Reflection.BindingFlags]"NonPublic, Instance"
                    $fieldInfo = $PhysicalStore.GetType().GetField("Data", $bindingFlags)
                    $privateData = $fieldInfo.GetValue($PhysicalStore)
                    $realKey = $privateData.Keys | Where-Object { $_ -eq "SPPSVC\$AppId\$SkuId" }
                    $block = $privateData[$realKey]
                    $DataBlocks = $block | % {
                        [PsOBject]@{
                            Value = $_.ValueAsStr
                            Data  = [BitConverter]::ToString($_.Data)
                            Raw   = $_.Data
                        }
                    }
                    return $DataBlocks
                }
        
                $blob = $block.Data
                $ms = [MemoryStream]::new($blob)
                $br = [BinaryReader]::new($ms)

                while ($ms.Position + 16 -le $ms.Length) {
                    [void]$br.ReadInt64() # Skip Header ID
                    $nSize = $br.ReadInt32()
                    $dSize = $br.ReadInt32()

                    $name = [Encoding]::Unicode.GetString($br.ReadBytes($nSize)).TrimEnd("`0")
                    $ms.Position = ($ms.Position + 7) -band -8

                    if ($ms.Position + $dSize -le $ms.Length) {
                        $mappedData[$name] = $br.ReadBytes($dSize)
                    }
                    $ms.Position = ($ms.Position + 7) -band -8
                }

                [Byte[]]$RawBlob = $mappedData["SppPkeyBindingPid3"]
                $pid3Obj = [PSCustomObject]@{
	                MajorVersion = [BitConverter]::ToUInt16($RawBlob, 4)
	                MinorVersion = [BitConverter]::ToUInt16($RawBlob, 6)
	                ProductId    = [Encoding]::ASCII.GetString($RawBlob[8..31]).TrimEnd("`0")
	                KeyIdx       = [BitConverter]::ToUInt32($RawBlob, 32)
	                EditionId    = [Encoding]::ASCII.GetString($RawBlob[36..51]).TrimEnd("`0")
	                CDKey        = Parse-abCdKey($RawBlob[52..67])
                }
                $pid3txt = ("DPID v{0}.{1}: {2}, Group: {3}, PFN: {4}, Key: {5}" -f 
                    $pid3Obj.MajorVersion, 
                    $pid3Obj.MinorVersion, 
                    $pid3Obj.ProductId, 
                    $pid3Obj.KeyIdx, 
                    $pid3Obj.EditionId, 
                    $pid3Obj.CDKey
                )

                [Byte[]]$RawBlob = $mappedData["SppPkeyBindingPid4"]
                $pid4Obj = [PSCustomObject]@{
	                MajorVersion = [BitConverter]::ToUInt16($RawBlob, 4)
	                MinorVersion = [BitConverter]::ToUInt16($RawBlob, 6)
	                AdvancedPid  = [Encoding]::Unicode.GetString($RawBlob[8..135]).TrimEnd("`0")
	                ActivationId = [Encoding]::Unicode.GetString($RawBlob[136..263]).TrimEnd("`0")
	                OemId        = [Encoding]::Unicode.GetString($RawBlob[264..279]).TrimEnd("`0")
	                EditionId    = [Encoding]::Unicode.GetString($RawBlob[280..799]).TrimEnd("`0")
	                CDKey        = Parse-abCdKey($RawBlob[808..823])
	                PartNumber   = [Encoding]::Unicode.GetString($RawBlob[888..1015]).TrimEnd("`0")
	                KeyType      = [Encoding]::Unicode.GetString($RawBlob[1016..1143]).TrimEnd("`0")
	                EulaType     = [Encoding]::Unicode.GetString($RawBlob[1144..1271]).TrimEnd("`0")
                }
                $pid4txt = ("DPID v{0}.{1}: {2}, Edition: {3}, Type: {4}, Eula: {5}, Key: {6}" -f 
                    $pid4Obj.MajorVersion, 
                    $pid4Obj.MinorVersion, 
                    $pid4Obj.AdvancedPid, 
                    $pid4Obj.EditionId, 
                    $pid4Obj.KeyType, 
                    $pid4Obj.EulaType, 
                    $pid4Obj.CDKey
                )
            }
            catch {
                Write-Error "Failed to extract/parse blob: $($_.Exception.Message)"
            }

            if ($Export.IsPresent) {
                return (
                    [PSObject][ordered]@{
                        AppId                        = $AppId
                        SkuId                        = $SkuID
                        PkeyId                       = $pkeyId
                        SppPkeyBindingProductKey     = [BitConverter]::ToString($mappedData["SppPkeyBindingProductKey"]) -replace ('-','')
                        SppPkeyBindingMPC            = [BitConverter]::ToString($mappedData["SppPkeyBindingMPC"]) -replace ('-','')
                        SppPkeyBindingPid2           = [BitConverter]::ToString($mappedData["SppPkeyBindingPid2"]) -replace ('-','')
                        SppPkeyBindingPid3           = [BitConverter]::ToString($mappedData["SppPkeyBindingPid3"]) -replace ('-','')
                        SppPkeyBindingPid4           = [BitConverter]::ToString($mappedData["SppPkeyBindingPid4"]) -replace ('-','')
                        SppPkeyChannelId             = [BitConverter]::ToString($mappedData["SppPkeyChannelId"]) -replace ('-','')
                        SppPkeyUniqueIdToken         = [BitConverter]::ToString($mappedData["SppPkeyUniqueIdToken"]) -replace ('-','')
                        SppPkeyBindingEditionId      = [BitConverter]::ToString($mappedData["SppPkeyBindingEditionId"]) -replace ('-','')
                        SppPkeyPhoneActivationData   = [BitConverter]::ToString($mappedData["SppPkeyPhoneActivationData"]) -replace ('-','')
                        SppPkeyBindingMiscData       = [BitConverter]::ToString($mappedData["SppPkeyBindingMiscData"]) -replace ('-','')
                    }
                )
            }

            if ($mappedData.Count -gt 0) {
                $Results.Add(
                [PSCustomObject]@{
                    MPC               = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingMPC"]).TrimEnd("`0")
                    Channel           = [Encoding]::Unicode.GetString($mappedData["SppPkeyChannelId"]).TrimEnd("`0")
                    EditionId         = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingEditionId"]).TrimEnd("`0")
                    ProductId         = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingPid2"]).TrimEnd("`0")
                    ProductKey        = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingProductKey"]).TrimEnd("`0")
                    AppId             = $AppId
                    SkuId             = $SkuId
                    PkeyId            = $pkeyId
                    DigitalProductId  = $pid3txt
                    DigitalProductId4 = $pid4txt
                    PhoneData         = Parse-PhoneData ($mappedData["SppPkeyPhoneActivationData"])
                   #MiscData          = ($mappedData["SppPkeyBindingMiscData"] | ForEach-Object { "{0:X2}" -f $_ }) -join ' '
                    Token             = Parse-Token(([Encoding]::Unicode.GetString($mappedData["SppPkeyUniqueIdToken"]).TrimEnd("`0")))
                })
            }
        }
    }
    finally {
        if ($br)            { $br.Dispose() }
        if ($ms)            { $ms.Dispose() }
        if ($TokenStore)    { $TokenStore.Dispose() }
        if ($PhysicalStore) { $PhysicalStore.Dispose() }
        $PhysicalStore = $null; $TokenStore = $null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [File]::Delete($tsTmpFile)  | Out-Null
        [File]::Delete($psTmpFile) | Out-Null
    }

    return $Results
}
function Hwid-ConvertToLargeInt {
    param ([byte[]]$Raw)

    # State tracking: Use [int64] internally to prevent overflow during calculation
    $S = [PSCustomObject]@{ P = 28; L = [int64]0; H = [int64]0; S = 0 }

    $Pack = {
        param([int]$idx, [int]$bits, [int]$shift, [int64]$mask, [bool]$isHigh, $sShift)
        
        $cnt = [BitConverter]::ToUInt16($Raw, $idx * 2)
        if ($cnt -eq 0) { return }

        $v4 = [BitConverter]::ToUInt16($Raw, $S.P)
        for ($i=0; $i -lt $cnt; $i++) {
            $val = [BitConverter]::ToUInt16($Raw, $S.P + ($i * 2))
            if (($val -band 1) -eq 0) { $v4 = $val; break }
        }
        $S.S = ($v4 -band 1)
        
        $m = (1 -shl $bits) - 1
        $hash = $m -band ($v4 -shr 1)
        if ($hash -eq 0) { $hash = $m }

        # Logic: Perform bitwise as Int64, then mask to 32-bit to mimic register overflow
        if ($isHigh) {
            $valToXor = ([int64]$hash -shl $shift)
            $S.H = ($S.H -bxor (($S.H -bxor $valToXor) -band $mask)) -band 0xFFFFFFFF
        } else {
            $valToXor = ([int64]$hash -shl $shift)
            $S.L = ($S.L -bxor (($S.L -bxor $valToXor) -band $mask)) -band 0xFFFFFFFF
        }

        if ($null -ne $sShift) {
            $S.L = ($S.L -bxor (($S.L -bxor ($S.L -bor ($S.S -shl $sShift))) -band 0x7C0)) -band 0xFFFFFFFF
        }

        $S.P += (2 * $cnt)
    }

    # Header Logic
    $v3 = [BitConverter]::ToUInt16($Raw, 26)
    if ($v3) { 
        $v6 = (($v3 -shr 1) -band 0x3F)
        $S.L = if ($v6) { [int64]$v6 } else { [int64]63 }
    }

    $v8 = [BitConverter]::ToUInt16($Raw, 24)
    if ($v8) { 
        $v9 = (($v8 -shr 1) -band 7)
        $v10 = if ($v9) { $v9 } else { 7 }
        $S.H = ([int64]$v10 -shl 29) -band 0xFFFFFFFF
    }

    # Word 2-10 (Full Implementation)
    &$Pack 2  7 21 0xFE00000    $false 6
    &$Pack 3  4 28 0xF0000000   $false $null
    &$Pack 4  7 9  0xFE00       $true  7
    &$Pack 5  5 21 0x3E00000    $true  $null
    &$Pack 6  5 16 0x1F0000     $true  8
    &$Pack 7  6 3  0x1F8        $true  9
    
    $S.P += (2 * [BitConverter]::ToUInt16($Raw, 16)) 
    
    &$Pack 9  10 11 0x1FF800    $false 10
    &$Pack 10 3  26 0x1C000000   $true  $null

    # Merge High and Low into final 64-bit ID
    $final = ([int64]$S.H -shl 32) -bor ([uint32]$S.L)
    return $final
}

try {
    $Module = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.ScopeName -eq "API" } | Select-Object -Last 1
    $Global:API = $Module.GetTypes()[0]
}
catch {
    # Choke pipeline output by assigning assembly components or using [void]
    $AssemblyName = New-Object System.Reflection.AssemblyName("null")
    $DynamicAssembly = [AppDomain]::CurrentDomain.DefineDynamicAssembly($AssemblyName, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $Module = $DynamicAssembly.DefineDynamicModule("API", $false).DefineType("null")
    
    @(
        @('SLOpen',  'slc.dll', [Int32], @([IntPtr].MakeByRefType())),
        @('SLClose', 'slc.dll', [Int32], @([IntPtr])),
        @('SLGetLicensingStatusInformation', 'sppc.dll', [Int32], @(
                [IntPtr],                     # hSLC (HSLC handle)
                [GUID].MakeByRefType(),       # pAppID (const SLID * - pass [IntPtr]::Zero or allocated GUID)
                [IntPtr],                     # pProductSkuId (const SLID * - pass [IntPtr]::Zero or allocated GUID)
                [IntPtr],                     # pwszRightName (PCWSTR - pass [IntPtr]::Zero for NULL)
                [uint32].MakeByRefType(),     # pnStatusCount (UINT *)
                [IntPtr].MakeByRefType()      # ppLicensingStatus (SL_LICENSING_STATUS **)
        ))
    ) | ForEach-Object {
        [void]$Module.DefinePInvokeMethod(($_[0]), ($_[1]), 22, 1, [Type]($_[2]), [Type[]]($_[3]), 1, 3).SetImplementationFlags(128)
    }
    $Global:API = $Module.CreateType()
}

if (!([PSTypeName]'LibTSforge.SPP.ProductConfig').Type) {
  Import-Block -PSPath $PSCommandPath -BlockName TSforge
  if (!([PSTypeName]'LibTSforge.SPP.ProductConfig').Type) {
    Write-error "Fail to load: LibTSforge.SPP.ProductConfig"
    return
  }
}
$LibTSforge = ([PSTypeName]'LibTSforge.SPP.ProductConfig').Type
try {
    $Hwid = Get-SppStoreLicense -SkuType Windows -IgnoreEsu -Dump | 
        Where-Object Value -match 'current' | 
        Select-Object -First 1
} catch {}

if ($Hwid -ne $null) {
    return Hwid-ConvertToLargeInt -Raw $Hwid.Raw
}


## TSforge ##
<#
H4sIAAAAAAAEAOS9CXgcxdEw3DO7O7OndmdX2tW9K59rryTrPoxtrBOEL2HJxieybK0tGVkrZmUMGDkmQMJpcLjNZQgkQAgEwg0JkBASEkjIwZEEDLyQQBJykBBCCLH/quq5VloZ8v1fvv/5n8+P1dPVXd1dXVVdXd3T07ts3WXMxhizw9+RI4w9zPi/xezT/+2Fv5zooznsftfzZQ8LS58v6x0cSsdG1dQ2tX9HbEv/yEhqLLY5G
VN3jsSGRmLtK3piO1IDyUqfzz1Dq6O7g7Glgo099MHJB/V632DTYh6hirGYwJjE0y5shHgMCRMQDFBc5HQzZj7ZXoHS8Z+NLT4PUfG/+TQe9K8R6l3BeL1Vtiyd3CQwLzyWNgis9zPwxPgH9DktoBPg4y1w5Vjy9DF4flSq9Stm0m2pYlOlmla3QJxow75jR6cJGXiL4X+lmhxOAaJXo5nqmjUJr3Uimac0chykTWQOZr8J4lczJk
xE/Iz/QkDopYzKK9FZlyyE2MwXdgPZcT9j7r0yxGI3Qr6Wc5aR48Sct82c040cF+bYBSNn3MhxQ2w6FDl85MjrLXEQq9sdZHEFszyQFa2KVqWDCAFX7HOBNjubTv1kChNTIchJ5UIw5OaAlLRF1vZtj6TyAJg1l/oyk6EeAX48DImiLRXBUvkQRC4B1RXyUwUQDx9wJ5g0l/pvZ8VmG4WWNnj1cQfq9NzVTAzb4tCpRBxQE6kSwGF
z9zExXgoxWyqKBSlRtNtSoAnutVpJzmPIQlVQmA1ZIUHtOra0b8hEBVyBhXVcTs8Y0CekypBbnOgiqK8LcByI8wLQVBSfBrnx6YgiEdc9ckEchqzby8SLESEoxmdiv+OzsFF2yMMgZTbFX5V9CebCtoUA8iHG8puYh+uGyIAAHNJASzpO1YupOcge4qsnwWTkQXh7mMtAtO0b2p6aSx2zhQFIJYhPvK7iTNlYpJIq13uHvCrS+8/x
VOjAaLwCGRw1mIB4WwFPRrw8aM4T9iaWyc79Pia5ovmb+93hkD1RziQQBdvbFz5sCzkUR3kOkyKbYw+VPGXvd7OEhBCwQLFH1oTsir30sD0kKVLFs8wZWeN1yvuGar4ubQ3JCabIWh+AULQTClOB+6P58Uokax5xRq1FOsEMuitsUsKhHgsgcQjLnQ3lXNSnaixRg0EtFYvtBckctocPg9DK7YXexHopNgrcrfFJsTQ8D4uQlRDCP
le5Hfq4UIp9o4Tn3ldi5iL55faIN1Eixf4CinBYoP7a870Jj3ocUJKug9bOdM7V5AriQuErbI8PmA11uKVyWYzXk7imifEGTW5FgPsg4HoQN90IqekmIjuSaiYx7w5qw1vySMAwnirJXLshGwaqPTUfVTGxHHTuGIj5WNAWX4Aai8VCdoAWGpBDUuxGNYrDjNp5lZCm1Q21LUJm33HIHxQPh0GzilLHYs6rUtyJVUkgNxwvXK+PZe
sPML9u805jZHthPKYXY6e4cqdaUIv5wyNKchwqlcaxh4kaxpO9/OGTnJQZsksuHnHwvip2ILCVCJRMkwVDoXTtdk29Hpiriuk2SB3HAhqvYcCguoMVWJklE3TIwTbAQPDRWNxdjFzFgbgHytihYq+z3NG0COcRyovOMIYkwdQ/D5NT7ZjGH+6wr+kQ8oODITt/RlB1tCRJe8ra0xkm6xJyKY6QW3GXL4Gy2EdFisbWjGgtargexaP
IhwVQrZBX8ZZ7mXoJqmEHqqEcjZEBmSUrMkVCLr0mezTXqEncXYS0AwOlmXLs80AqF0gOpM6USzngR0BxjQfo6RhXkDWdxDVXZI3PtQfqtwPnfYpvvnLkyBHejqS3wSS0DTlKzvxDMC3NLQI+/wbqzTH03S2RxofsYCb25GLlx2HlABQgUMIBy8yBA690DUjaQcJZE5LDIWfTLTjBK07epRRM326gCXkYYjxNcaa6OCcS8xn1GVmo
CgIbpQ7rcT/Fw9RPeJJAqPOKB8pqlCgOXf6kj82cyLAe4TiSBUfSsxTXbqy5whZOCJEsiSJIbGJqXsIFcaRBH66fnold4iKVUespDbtWqsNWjkpabaRJo0YHZLMDGcLI1h4mxGcITJqApIN7CqeQpgxSi6whLdpYIStOUBe0t6BOzd9nWWQaUALlUVMOhWssXNZYl00Ce/KRQIel76YMSY+isbV88OVISk5YT0qdQMVzqGshv1GUq
x4gWFr3a92TJ2soo06GnBmdoT6v1/q+DrqmKMr8pn8fOQIFtVmeHfLBvOOEZjXLS36KRy7EsZmQozPidnSZHLrfRGR6ZbK5bs00NZE5JQsVCmr2K5xpviSydbxJlxIs5F4d701QtyUuJ08BBCXITS+5KoVrLehIcBAIDmoE43zYUsfdb5wcIkD3LBvZWfqH6WMAo0//siV9kTZqbdzUzDXh5QTjvLmV16kwLS+1gtyXY8Dn7ebmmE
aBjXyG8hyZ9N9OEGgYWPSAVlBOnYgdPFTEoOhKnPMehzmPHQ5L5pxnzHM57PjVfJ5DP/F8RusnsGU92LiVEk9icVAgSrzMaaWkwGmhpNzjpKFnOCEwBTs1+8qgPJHzEJAjZJAj8oakuIRSB/1KjCM8l9OYy5b16zSKTGXEpIl8WvyZ+ZQHGBqNQKCYkOSQ/VDMYNZDk5iVC74hDDMLz5atN30DXFsFaZ61qTYwuegoSwYQR/ddyj0
sQMPA1nycnGzkI3hYAvxLsirouElAOLnWuMa4FuvGOsPuRK/WT4kMviejd2Fr78qdvF+8l/lMdpCh10rLqdXYmUQ7eLFrwDG3WiGfq+KAdfaM0HQBdNLUaeeTJq9NU+A7RdIQkpLpkhQWhOMnYXIxJU/T10K41pB0P2QNM3389dr4KNibqy8d9+ZhLAZDfi9aGzI5ezBt/V40LNGte9H0RVdFY+b6ai+a89idUDojtVBbF4qsVPdf
xd0x5F5Vjk3cXYYzveYQ0zLBdGRRrl+EMrm8TALpXgtZ3O0G58QDsk2vQ+dE3D2X6xLw3K3h+hIreGTP55BzFZFZe/ZgY9I8sGdp6LR75l7MQcczEQdHPwHOpFY/uebQwhxB98IlvuIKVUlsKdCURzShxCV3eiOqhCTz0qmTMejDISo7qaNO6mRqE9pMF1hJTqzoTDeTM0pabXHfYXxJ7HKwwWG+9uxDtRR3V5JR6adKwG/cCQhyH
OqUvM70Zu7spLfgEyYKsO0DZGgdqSQ801vJMVQk1S2yUTUAQWob5UvqykkpqzFlg5niSA1icXD71LshFdyOIYSd8e04azlTp8AjPsy0Jbt70vTCqXNp1IH7pLg06twW6tBv2mWDlnfbjJbd6lsAKJ7UDsTwArzRbsI+gL9rgXPSI/jwp1P4CKRHUcJqhYONhlOnYn0z1SQAEQ6EFKbkpFSawBLLYW5JQ3RsJk7WIaaE1BscVDN2lf
dwDFFzFb+SC1NqSH1gQn5qJwancQ0PpnYxWuWEleDOQqwzT8kDnuRpPGGKjzcdbvoQDWnY0nqEKRH1xQm1h/KVgJKfOl3TzkKlEOwYJqXPQJQzqdn0PDQbUPpf2Wgfj5GzHVH9UrbcMi03OiF3fJqW0TwxY7qWcdKEjNRuCNSUpC2sx2egE1hA9J+FGlOQGudcChOX5h8GHx4YFc7OKC9nVFFTG253FVkYVcyUYvWMCY2HSoKlSkl
8DzZUrF6brauhKNBSEoylPocTtBKDaSFUppSVS6zpdRRGjBuB6qC4uwJd9NLUXs52dCGnKdOaaf8WFCEanJ46G+tI1xDjo+MziSXF6kMTeTVLy/j5xIzZWoYgT8iIT5ExkbtzCG/6+Fx6xsYT9CwdL0euz9C7oMxIfZ5P/8BC4vq9nOtFWbkOQ9gFsEt3DDTjcw63UC1ncR8L91UugL8HWKbvlQRJ4ZzypEA2zEh/A2AX/P1OzEx3
gY+2GtL77JnpP4S/uyHvdLtZP/oeOEFFNN8Du5c6F/lyHjkg/eBAfEFzQFAaNpoSwOGW+fzxRbSfiWjQFj+faQtEe6qS9gIUB6iAHJIOteJexwU4gF8BL8R2OBwwvRD0MuIXYt5V3EPxm3nqbJBV+iKcLfgeRjH2o5mVJ7mfIoI3MXK26UPBJM7yqR+2+ABuPVxMXSiCFi6hLjBRjtfSXt4hB2jQIWp8Hzb+Km9cyfQli2kWZ96Zz
IEg+kgwq1B7Z4rpS1FdkF9i+jKMVppeA5+fZxl7mLurcF7cD1ni7mo9aq4IaJ6eZdnnkNi/qWWmGG5IjoP4P16DrdjGa/FhH6/Dh2O8Hh859vEGekq70caMN2oA2pV82mKcGY7Ov2FmJHrMDakv4RA8MN5EOI7dOJ7GmzUAh8r4fA1AvR8/hlqLHQHWbO+L1my2bY8dOXLkWIjnbt4k7kaaMMUPuZvGq4imCli/JMTI9mj1Zns0Z6
AM8I+AgWCAUE2MAvIk3P+WYkdAJ/vcImeNNBKdvZnjzNV80Tp9z1S9ExRC3I29LI/wZ6RSVn8FqQmH+nv++EDWdkq1vVSZ3Q/lC7F8YdonoOO6G8yWveASMKTizHBagrSZ+eOn4kBXD0Pp1IeoIzPF1OU4Dj5C4JaZEcKDVR0hymqVU0eUtf2HNKbfMjM/s8KTnWaF8fmolbzC1BUoVynlBGRaEUYDtF4khUhfie5OgjlJFyK4ew3
0p6uQetCmBVBz7mEbOVU5GhxyNP0FdxIyt1Y9ohxjIM95M2XaY50XlmlrdJ6s7nMSuw7wx1f44z54jGN16rchFr8KbeMrGLsaCXLGr4FHORhyVBX1PewaOPWwAomgN1TuMWhJbJPUv2A5GFESR6cqxvei/xY/AFHpsFSNjuN1OBRAwxM+F/YJ3KLyGBNdEV1jF3JljRxI3YAVYP1mM+BNcR9yBHhUzMfaQs4dt1Tu0yBP04m4K8j3
jhbS6qFBd2+bK/C1kYh7sZJP3I2DRhVd2myAmwHlzYwSQnau6PnrowMbYwGYaNaJu3EYxg5+QWDr1+DmpwFuDEkssYJpKYtb/Wx9yBV0qW6s+UaylJa8jVjWrPtd0IN15ARTlBzgNVBhOCSzoCN+E7l94ZAnMQN8P0/qIDlzTJGD3vjN+qSM+xmKJ7KGtiDd9DKm5qclilyycW1IFtUA0FF0SYA47ALlVuyguIrjYnD+hVtmFiiyF
itUJB6L34LMX8iZTzzFXX3z3VnJxL3x2K2Qqu1bF2hPEfe4pWg+Logl1Avss563G20RDAKeFx3m+0B8G9sjxz3G9gnajK3xW7GnRqJX0jY+OL6+trCx54CK0km0fWQ3aCs0aFuMtmivsRsHFKHZ8+CivhTfz6A1sOYDrQ4NEfU75hQtRdEi6yYwdRu1EO028LGrmU3Nn5TSOCGFOqbZBAfND1G+ZlpA79IsmuaxqpY37qVV0QTDEH
LEv0IKHnTGv4oRyYRvx4jMKcD1RciluMwxUREAqNWApIQz35dwFvgS9jCwXe2GnKhLUy0JVItLWdOnfF2xCpy6hrm0SJFiv3gjxYoNRSzR1W9mqa6SpIig+6Dd+vzwFqP3zrC2i2grTdyJokkpOmezuBsnyWgUJypky/YIxqzy2YS+Ck3JIanparQGFmZaObvRY2qRV5uHZPUFF5nOQjcb9Tld6T3EvaAcv4PpG25Oq6Y7tW1mp7Y
R6tSIsWw2OznNXG+cGS9y0NYNg8Uqo/kQDZqbVx5jPzxwjGaR1qTvJNtvWrnyNqYOAIFukFGcSXvm4VwVzedrazIg9qCdWw+aOvlrg6LDdmRNxY9Z07PEFppxgcdg7JsfQjcITBKfyUPOaH7IldgBKe5oDsinBpabMXylvo6WqE7Fs39NiJ6KO5q//mfX42MjqRdZqrVoqcL0DhB3uCueJBqVCdRJGnmKCwqAWmoFfIqv4jwposip
r+GMtQ96KilyZI1Ehk+R10bWUk78LipdFMpJhJmk5KhfAszU13mVOcVr8B0ILwM99yv+il9JoQAwPjC3Ur0KUPciTXNxP+Ex6Pw0sis1NClLu2FqtPvZnruhcG5QCIrx5eRpOuP3oIuMb2KHmEux//xwMchYXLfmVHwge3d/CccZsBR3maQ930A672V8h6BcTFRAxkbiMMxFYqLUVuGFMpdzSeASCtiA+32KFHIfiuuvcbfLI9AFY
GnFhYyqhEyPVC5LmnuruOdq+34y+8rX+btu3CuFDuJ5A6NfuR69Z0EhvgTIKLflJgTZm1GZ06yraJpel0RnT2ZM4lHEzwqJP8vQULsqJJmWghEauG6NWMehIo1zp6LtBTiDeMdcvb1jO/X27AymZDz7MEkmNnt8KU4iGXXIJs2hQl7HLBbGzVZp1lxOfxWlTa5P/QGoAnYBljUnIj7LqNmgrWSGyVe0VbMn1aW+ATX5Wbw3Sy3MoC
9S+hl4Gv5v8FSifeB4Nh7A3DsKHBA0HmBL4ZocxR4L/sX+JL3yRN2cso3a+Z/WpwI/y//v9AnfY8zJ1qcFngy5YksVklNrFh1cvVn50PSgwxW/D4cqbY044idjATmzeYuOLV9l6iksd1EfYO42Bzt4qx51wKPvvxJluObWxh6StJLx97R8YZ0LC+sOJ38bZge7EnbGv8n4Sz17dAFO+gn+3gndI5j+aXPRTluKUNIjl8uyTqZ5PqC
MrT/L5NPiqWT/4GTZm2KfWgYwJxh1QzmWyFb3u6YMuibJwOx6Huc+dsXamGSe4ZHZgjazvR6+vzLZNkzoR4VXLnc5I5oCf7YW9fYWdZjt4dmKis8wP9DWgU/T4ZAdRkyiDKcJxWFMFDQ/8L0iWO6AeQeauHnHgxQ/Y64samfQ1D9o2qCp7KNfiPd8FvuI/QKSWKWlDtJgbY4Q8YyLxJfNYehj/Dj0WCfOFCZtM8v1ekU6szbZPoJp
PD6raTTqCBaYdWyG5zy+j2Xd/2k09n9kmmG9TnPY0auysMwnWDQsYsLpjG+jmVvfG3oy696Q9s6sfSXfD2pVP8LBi8Zg7yJt7wJ5vgY8oCoa6+AptnrJU+yGBxCTfoDGfepBRgdO8C3Ea+W4GD0UC9mZugGw5PhDfNg+rHtm6UfQPKgXGpnxEBIb9qLmDGKnsboCPhLRZAHXHqXlR2Q6bfgt/tzi+GPo9T1OCnUoAcydCy6YeidUC
Q6U0RKvOPYBUBT/FuIeskW8mgI6KzyKI9Zkx0NbaObBNak4BwcpOSOKmuvTyUt/m+id78ukV6yQ4zBEJCyMB0AamToCKFpn4ru0kx/g3ukHZ66A7PQTVNl3DEw2V4hjpxRWUsliFXSEcxurPcDslXr8RjYb01EWRwCzmmRBZ72a3yOGkDhIFh6ZmFeoyeLnmHuoEGXxCbSYRQqVOQbJOv95FfkW/supJ5F7cuGn8H9lzn/K/0EhO/
896qNQl8b53xo0svhafsKS88zHyipZIefZela7T+cZxL+k80xkpwJmDZ3Zo8J7nkL/utQPXvN3yGsGhfsusi7sTSRk5wEfc6l1mPs0mTMYUAFI6fRrG0UwN8wwzxX+JHNYqyf4je1ehznGI6xljX4W085gxcNqSYY+l9cZaRATs6Iz499Dqv4NxePPIOd8MLfMrJBm0fooZG96HsV8VYCNqssUCDA1/gNAHGuBRuLP0jBUt0BW/Id
kzeI/wnHvkWm7yzIR7GKFl7TQwlbdCdiwuFUvoGe+ehs9C9Tv4jMkwVqNjjwlmhVZcR4IuZhGpeKiNiyt8VZoFDhkWCVMN46hKMikJ/CIJqZ71N8pBn/s+rndcAY/yp0JYG9lSaJBTQShAeyaujCoNQWceBc5YWb93pL1mZh0R+j/JJPM1j47k54IZTAJ9wdguY57yLhXsoP2SrxO8H+AVXKk0pvIlWzpH9OeUR7E/kwxj2QT0/fo
G0l4HhlGEKvndYzQ4Yd0AqdM2gRDnw7WkKyBn21w5NL79JDWXMAWcYvofsEIdGhMc1iYBlKLMPVfQLZDXZILHcY1Ku8BFCiIROjwAQws3CSFSQoGlU2Mz8Jt4+e4CfG4ymX91ZJ6IlRhNyvShv6hkPZGxgVUncK/UODzKL1TWcuKd/IxJrLlbMm11F2av6CzrBH7ZddIt1tIB6cVSL+UWrwjk3Stx6ItnuKnQOzx59HqXc7JsfqfG
kHq87m6pbKcV1W69bEv4xoBZQkygBU6ezJMvlQBf8TTUDCCgtT3/Z3QE4b+isJUXx5UPYZyi8R/Qtobc25ie6lkWI4ERV7HTvQ15PgL1EGbT47/lGbO1M/w4TLOy2Ddq6Du+RPqLtTqhsktZj/I9iYcMXbQaKVwQis/R6lmb8JyeAF1DzwP/v5D3L0MN9JzsDHs5HzkL54YHsf0uRNwl0+Bu5zjini+h94xabjh+C907hEy7rByZD
aJjhVT1L0iS90rpqqbkBeJ4fGl1jdnk9rqmaKtnixt9UzVVk/2fvROUXdvlrp7p6q716hbZP1M+2cTd3cz/aAsACdaAaRm35AB9maCKyei8l1EDVH77IJx2zYEz2P4dxJ0npk/PPzh5Q+fqB1uFp38oLFDdPGIlD6Ib9qlcSR1pjyORM5U7OMrGT9H3ENPzg7tE4AJ5+I/hvYXTNxfF3evMggFYDUCL+LofwkDfvzTmvwyktyEr75
h0fAKo082KNuZ+iXS79QOyWcci9frd6V+ZdQqFeKaFwyMK/Vr6miiOOiIv0pdhdlGSt1IW+k6FuS9hkbt1+DhOw6H8y2vpYGQQxCbf8qRI0f4wb7wpLP1+jcR3IZezeY8qb+XbmXXHzLP0sHYZgsnnrMXpVKSwTiyqukqxJW47MCVOlOL+yQuKFJR6D+XowM6IPKzZ8gkxZ5+HTnwBtIWDkmJOUYGsU/CN0ZS6k2NQVQSmBHBw6/S
dsWBK0lZkfUvPvjSEmbW+bug7xMO8BfSAX5wMucvh8y53AcBg6+fQ8NmbakzsL3/4dMEzBEFGRkWYjMLIK1cH227T8C3zqSUtt1LMH4ij6Ol4NppI5vFNdRGNoa0lHdzLukm+K1sET8PkHqLhq0ipd5GFuNBgC8THyR+suid7HtvLlYyy1w/H4DnsdZ+IsVovFHXPIlNoDOvkvI6UyBPiZ9fhKVEJ0ufg91ykkUYx75BHHs0voTIN
204pGOPyOxCHHtEZpKf5RS4ul7NFdKirhPPcobZjnPM869XH53ujRa6r0G6af3zv5voA1MTrdO8fa85ZtCOLp5Ec9iTqMYPa36D5E7gcog5HaQCkuxM/RZbSOSCh7fGA2JFCwF6i/s7T2oVSlwFdTt68lTtVVraM7nzGRv77oTGOmHOsDuIc/jWTTJS6G1mRgrh3D4J53bNP0K57gGaW6w0a0MOnCsbS2zNJm1vYnZQJGmDQ2nhHy
3VPGhM3wFoVsKNXxaR3F7gXxZZ5DaJgVx+5axuk6lzu49K25bstM2w0KbxemrCfv6phOl0VW/U9crBktr0LGqHNtD6iul30RCvZllP/Z6EyeJufJAHDpIg5/sWboEx3Typ7xhfw+hgzlpmnl/BfalWzgvETv2OJsnyE8EVvxk3zHYjsrgbS8ZnC3Q4FfHkffpnhBMa4bn48lsngB8/1r+zhPUgazPbI6ozGkH63RNq1dYyWB7P4/L
vNCeRppWSjkqaNJm0ubhGAgmydvIVfs/4OfyJLsCtU7oA+oxuTwwG7XxGd+BRWlRhG99bwN2WE2B+IbOlOCx2CwDTcDnxdKfEMNG0WgAYZiv1B8YP9tu5ol0KimbP7h10Z/UOdMeA+wUL2c77dL+ggD30gj5G7OztT+XHzZ+BH8kMfuCwsWlbT/8NZnxpamb0HI0ZOi/Ue0xe3P+8Pi4zfPINU/jkG7L45Bum8sk3ZPf3N05R98Ys
dW+cqu6NFn/f+L4exso6q9++3gpsYOaXWDZeswXcYHXxN5ouPo5FGH+sI5t/T99h8odP9+vtul/vwJ1S9OvXcb9+vebXb9D8emxEO1EwwZ/fBu11TvbnTzaoAsb0IfAe+Q6FIPw/ct9BSn0r07kW4n9CjXmN60TJRPeZn9HhNnoWm73MnPvxXc1xZH/2DbktPrNHlDWfGclJFGukyPFvox/3Z0a7rJp/K5tuqxTNXUtfh1b8mH9P3
6bLjJfnvNJ8znUWn3O9xc/cYPEzSUR//qx+5nf+Qz9TZFcwuttAyeC1O7E5yIjX+AnrA8bM7XWWH89dNZ9LJhWkYQ7x9food2lz3TKevkEf6BDfqI9zl/61EMnsSv7Ko2Sys6a/90iNm+du92ent89C70N8Nv+vEHvNlMQy8z3N8JmZ+tWlfYd0jEazlPoLozcAGZylz4020hRISHLqffL1IvrnRtTdvzLtc6Nv8vmz21J/08T6TU
78h5U/mOEZPjPJM8xIIZzvT8LhKSgz3L86YbLM5k6lYwF9sKX+xozP8Ij9z09iv5XvjR2mnqzM3ubsrHoydYMvZGtQb6+u1fT1zprg651Mvt4HaED6svt6mzDZps7OY6PqPAhSf4dUI7efu3abuUO4yXAIw9whfIo7PZusDhHZ8K+a/t8m3f8r94m7+3UAP9WSms8hWuNPkre2mSYfzRvclOkN9meCGQ3yXAu4yeor9luBTYZ3ppG
iO5FIc6XpQxod1anS3MeMdiXLedA9Fv/R7IdWQsrsh/Sf9EOy9kM6ej+0NdJtQMuSDB/LMnvtMGcv0nbuSMLyrkfznHD14TTtFAKGoVLsFkuFOYapQsCwVYrpQmkT4oWTJ0T9JLOux7nszH3mWuqWo/Vhu6UPD3Hn77/dgUuO0gGd/l0XZfXtklP4X0k2ef966xS4W7P4alun8tW2ZvcDt01R97YsdW+bqu5tFj9w1OIHbrG6fgNW
IJnp+G3NBLdlgkmrW7jVCmzL9BHT0OzST/UR6ZFtD1gECVNMTr/BvcYt3Gsc0LzFJOO7wFvpKVO/Q04QuNP0HnXfcdlk33HQ6jsOIfCh4Tv+Q/cdD030HT+y+I7R/52+46DuOw6RMXwdfbN/fmbfcYXpO2J5zjHNd9xi8R0HeByHFuef5kdutfiRJMZ/flY/8q3/eL/yIDyXa/OtwXd3YhQm0n9o8+0v0GLo35Tj9rxk/aa8Q9sDl
Eml+fJRJo3mq0eZdJTvAcqkonwBKZOGkvXwHYrixE3S/CKfuC3SzCVB6nP3+EWmzbshO+07stMOftUr3HP4rxB+4RSEW/ycM883dRDaQT0h/2+pRr+U+pj7f0fnOPmE28gnHOI+4b8yfULixSe6T3jLXH2vVG+v6yjtTeTSf9jYbRnO5TuTnMuMFMJ5dxLOu9r2JdPvhuieLONjPrN+BvRRnPq36SOSxB6fJDGLj2jeDSHSWdAsND
R9Nj2bmoAnshCgt9/RM7WPOkg+6mE0VEPZfdTtR/VRT+E+6jD3UbcbPmqE+6j/w12m7UfzUbdbfdRTsvqob5I3iI1EdB91e6ZTekommNEgz7WA261u6SlWYLvFtzvlKD6q0VGdKs1HzWh3Kh/V7IdWQsrsh/Sf9EOy9kM6ej/m8n3A64GWEzP8O8ssOWDOkqT/ho9q7O45LUbOaTFyTouRc1qMnNM0chbPjrT28snzbca6P5edep6
5f3nt0ejut9D9iuGX/jeIvmpKoi3+9Mjns/qj6hR+oJrFH01PgZvO4jOmp/IZCTnjfIdI7554OTQjkhtU8lTTawwbDqGa6R+mraBk+Jiq1VNMm54ibwt0HdfhoPfcV+SPWfzh4Q8vf/hs2r1kdpvhM0r0VSt4jMQhEZxDbIHT7TIPPXqZ2gimKX0ESp1p8NHCG/qIT7+e5DDT74jkc0IGL8yOWXhydF5k8KCUu5QZvNATtTZ3ZuXJ
RGboe6xQmNxEm77XqieI8lGYI03FHG39gOc4eib6zmHj20iz71Jm36XMvkvWvkvWPnPHmfhOZjCD7/wdVW82vznRACLbyfSLhdwsLeL1VSzhZPShsxc/ZPuEWzn8rNqZYgIOzwwnOkDHBvCN6H3aPvMZ0N6qCf3VakgJArbbCOMbmqIXH2b7CnOOTYchLaGvgvcq+SFhhiUBzYJN0I5tg1mITTq2McE2FLD2jaY/gP79as0fMIhxJ
6IwryMx6A/83fAH8MJBJmueIjX6Cp/2Y5M8RX3uL5+fuVY5ybIPOUZ+m10gvy2jFfDU7FyZOJKccggZnhqRCuIw9iH1Pb41k/syd6q+BDQ8OSULhjdD3Xp+Urey7fHtE9NOwB4fszou9vGd5LDEoU7QtpFsODbCIT8EHBR856Ew9dQ8/Tig+nP0dXrCbNSWwg+I4y7sPE/dRqmLJqReQKnHmqlfD2s15NKZVv55eLslPaNmSp1UM6
VOrJnZ6NNdtSmifRBb7hL1r0fCHhkkp66ELNWTz0Yj9AWrVo7GgZO95GBsnX4mXTu9PTtfvyTJbvkaEM++etSb8o1PhBoYfShhT2lXWgRnoXe8AdeI9TyFSXSfhz0opNwoURmvZvEonvKZ6qwCNmoPeYNey8fNanuBfoaTWpBT1VCP105fTfhcnBaPQFcF+cplF/9Owml8FZqj5JQfz5zxrTjK/OrpUJtT8dNHvfTxP5em4g9rNwS
CIXwVcNJegQ7TF+rybnoarLN6oQE7OYvfK9RZLInap4+KogBP7EU6v0S64AENDSly1PVpdzw4s9zxYOANF1nw8CtrHU+74qFQw7vMirfQgleQifegFW+R7jrcMrMwE+1VK9qxJlpRJnVisYlGDNJbLc7Em2HFa7bglWQ0K+JNGr3F9IHKhZYitG+kk1BKRUJBJchLKUHLPRhK0HIRhhLUbrjgGhlyOFPH4DNT40KgsPTpjWxXvw2N
xrcw+tDVsQe/oSG9L5cVWfuYMKSEyvH+rPggqXfmEeNQLiSMYiSPqc8V67oj5lf6xYJKj1gI3cMz7dC9WSVsNBRWwmpliXZVSCgyRZOlSmn5MFObAFFxctSokqdE8RthKRRTYnTfrfr5ErrHi6681dO+DWl+0dJZLRtK0yV6SgyXDXRZJJDpjOegfWTqR1hVhDeVD8j5vKkCpYBfrSs56Ssro7J8XlmBpbKJ41qvrhDQC3l1RUwp4
tcSw4Bxp3JwUJcl5gXL4n6MTmPKNLWhVP+OY7oyvTyol1CmpQKCdhSnLK7g9PADmB7KDoenmdODhqt2lloYo6X1WtOAIt6BIksH1O2I4rgYe2CnkOxHqFjJVYqh6D5St1y+kojwRQQI2JafcMREsB18KaEU64cbJLwoCyN2um6FryK+QHyn0/z0oYF6fqm2mA6VKCX8e4MZyoxyJwBBMtmHfJNudcoFOFeD7fF1RPztpZZz7C0DfH
2P3yDgPfftjO5VpGNTeCfTuXY6P8uetPO7N2l9jfu5eAcIRL7iyLwLqg3S0xB50GG9w8lG74zX8+8TaFSoHxtUaAMEZrC6KBv1gPNwBU5fOXhtBizOQgLe4BQL2uK5At3ghEdr8UAmPHajSIjbeIVTHsr6ZX6F03TLAZCMvUj9NH931OACP/vRyCoG9LMfRWz9aeY+JV7ZtsH8LitjBpyyOx6WDgt4Id0z0FAqggKaqf7ViHtpTeq
D/uVTr8CDs8cLBDom45IVh8mDVCEJF7KLdA/Ofjg809I/F/EoJAGTJM4kmeGlzcQkOYNJkskkaSKTLJ88qKUx67cOceTJBlZ+vs6fg6zieT1eye59XeeVzPCupI30PcYE16CckQGLxMHrkwKiNRtnfJhr1ZjOVMan9Phm1H3yXIoFuhCQvrR71MDjttsdrfFEC7x78HcQfKq7jI1KfEw+ROshfm+IL+iLlxB7teuxJe2p3Y4UcpqO
fshFzg64C83fxn4prmg5IWm32brC4VQpmhjFpd+z7Io9ebt+ZQugx4xYroHq/FkqKmjZWRLD+TwtHPInqgGOx5DaQDBguadDcSmOqFvxR9as2742VUZ6gRBeBeHkd/9WPA1FaRnhZE24AcLCoSBVSEWDlqLZ22CIgzMoVggzmlmhZOUQ9CKewZPCbB3Nz5KonU2f2hDgTInfkcMM2FxKlx9xrymiRMhrKs5wmnSvJFZm+AQuzRvg7
hLMUvkR7g3kaw6ASoCMW9Bgp/N1h2lKzBhz377IxC44OrbTxCw0MAuzYSrcb0HMok/BlHVM7rUoEZopQMhieVBdmqnz4ELcCCmhPJiO7DAdTDUdhfEDIHM6suvTUZ4+HTktM5H6LlTJL8WxfCc7cY7RrOtc1lLM54OFEHwdhPh7m3U+sDMY0LivdNT5QORXw+SBEaibBtI1TKKHJapE/klyHv16hJulrrRkhqDEngklcMHPLe0YmN
JcbmlFfc+jgH6zgAymw2owE53YDt10ErWijMOjlOv/RRyxZGINWvb52qrfzi3vOdx8Wyyv+uNpxhewE+7pIB6q7Oy/mfPS3wOCcU/DmXiHoj4vAaOmWJkBl6q48XVL2cyvdvUtmd9puNRhCZfmFrs1S+yZerA6uDckTXKGgA+KlHE5Fd7bKCEv9WXeLKYWT8+yzts7XV/n0R6UItP7SBEXYqDyaIGkmTn8qsGZOQ66a3BmjkSXDc5
00CWDM8N05yBY8gnLBrrix624+LIBl50wNCYSqjhpdGmyAxV3gIo7dHmdO33Sd4B72Fv9gk/fo8E7jDd9Bt2GGTcAmvoM1hcm7zpRg+pGWx0S2mYWj/D0QsALzNDxJHWrEWfq4zOy648xFjmNRWztmP6too3e5fYDjel6unFQHIe5Alyr3fiwmeNGOiw14CV409ELnyHo+7S8/GYs36iVP8DLH6DyV1rKN00qj7pbLdB97f//1F3c
BoFW3TP1VidoqOJUGyAv5flf0K5NUFAOuYNuSwnL9/bmvtYedp6N65z+uz0DxE8yO9od1aALM5Hp/F425DtwBL8xUBi+gcJPG2yp2YQRScXpmZ+aQ08pNRee4WjA8oNKCdr6E8PivqFUOW59On0ZGucy7+RoO8G8T+b/VZsV/ytt2vBeGNyrV1i6krcppuZRG7ZwqgqrnHCZiF5HbtFnq6P6M9Uh0vnobdnqwHtEoGPqM6gotTTW6
wQ6OG9L1dO2csZ307Iz1UDTV+ZVKnyfmOaJOcxbr38jLbP2JWY/YM5mg1lpaLTQ0PQZaLCnmqcgIhsNHUvN36jKhecQ6Wd6PhIh8Ra0316y0Qfdblo3wOCM4atgv37xLJWHSZ5tJx1CCt2AZNxOiytGopbfPTihrmmZdaFMopB/CtW1QOdHfRZxGnrlCfJ+vBTrFY1fTDuT6b+YdhrErDlnGDm7GNO/8Ud/Z5jeX1TIezA94diDBd
2i5V0GfycRDehvbGW6X5Fe43gtcZ/kcsbBm5bCpi16wbBFkgtXS1LILsuWH9iIBYAA/iMbCq0k6XN7652uaPQAxjuZormWZFiMRuOWq5qcdnTOcUk3gykSXnAQL9No0RZyubP0t0csMU3Hma7haIu4000cxRnyJZjio99gAMrYDtLVhbh6hlXRIlo6R4q0SH5EixToWYUFPOKewFoP3Smlvg0t0Y+SeaF3sMKWfLITl4LIIWBFKbH
CXuFyiaQrCRkiqIDmClGRXaRtikSPcPxYQbsdWTS1ENGc8ULuoWQslCR7arGgfwEM6x+iSpqtUWWu7IyY3Yg59RhfNIEK4714uM5WQEAjNJ4KK11igWVHH5gbm51lKoVJtlKfSsOTp1Kfa8IafNJEypfj587Wl+Pa3HvZ7E/dCznqRKv+DCpQZ8SBHzjHap/jt9A2hp77hWy5TpxZ1T9ly3LhhR1rFNeakDveigmhYIgv/0FF6W7c
7RtC3j0eHLka5NNWmbDqn3z9cihXydXWZbnWdVmu4qF7OfniLNdYcgJ6fjZ0tXUOUPsRX48Zy84psbut2NrCL4cv/PzBvMN5MJrFYF54+3g74AfzFPd4B494xzt5xDd+HFaVFwqoe+dkE4CiPpM1PYjMVRRt7YjxoB7Pv6SAc8a6nrQuJCV9IanoC0k/LSSRPVSmgJcpnIgf1PED+B44wQvhFe6T/SR+3Y8UX08a551rccmNtSeeG
WqHyB9E69rTyfJg0KYm7FHBwKk8iqMJg+czjQ56B4Sjgw+n1XM/fWzYpxobjvD2kMTVF9xBrr5O0llY1ujvmCJkdEN43yr/cVQwW9tDMkucwRT7UYaWV8/NOrR8eMFb9qGVo3gV3xolZw2MTqc+eJyKS4+6+KLar/ibo7h5E8w9nJePepqrOMePR63MpT6Md5GOg2LeOjerYiIJhgJCPPNdBSVb7GxQCe5xWg4aaKD++1O0OagD3J
iGFHumJmtaGda00jFJiwN4W3giU5Uj2QtlEquVD2UodNMg6igRFsoTcU8/VKwUR9Z22LWtdPQ5crW/RBF1JxROlOxx8UjuHjePeNSP5k54wahvlWUasVKlVDNipVY7U6qEuf0qNewXYOZnw1RnJQyLVDrpPaNlC07J43tw3GiJhaARUSVafirTCMufSFj25jZkNPdpxJ1uxeYtGxtl+cGYZi9jisTtZUyRub2MgWZ28oiL28tYqED
9fCKbWhaqP8yaXkTqWmiqq1Kkx7Payyz7b4bCFeoKk5/VbIqRSlshzPUTixXpxQomW8+JP9Kj7Q3o9jNYns1+4j7GNqDvT5bf45iWcQ+Oje5bHCU/xLYHfxE4vgZtorquHJm0MXOzEG8H5Q7K9ZDN76ibq703+Aq0ceoEm2xd/GfxWDIW/1mscj/jHideKwVovyg3Xxusxn0Bbre9FlPKr1C1y/GEYHmBm8Vmy9q4dao1Fbh/lQez
cdblurqyAi8WtCScBgnOqQuQ8Qwr4fISJvNDyhN/ewF/fLKZdiVhlJcrVjTMKmUy/RgvlwZdsWXNn2KucYPD5A6KkzY8YHLBDY98Jd/crMukfdJmnce6FeKl/hQoBc0v0psUr3oN9D/lgjw6+4UnNWL4M920wODXyRs95bfKFALGwaNiFClFxq8xVOi/xhAsjrfRq4dipADfk4MO3F+h/7op0FJoFJqlF6KftQrH23GiK4ExA33+0
CiilCjFI9E5mzfR+1e6jt3HEg0kCjRuEeweHU2wdI8l8jC5d2IypM2vNLaIJjJf8Vq2iCyzHDinisuY4iCuTWk5itOSqq8acvhE5/9MFfgsqb7MCgJ4N+iaStpD3QSPkCKW25wJwR4KqoMAK4oStOhSSH1ycmIu9lEJaTYR47l6PKt91K2bW7duoSl8yanwc41Ze6IbKYMdNO52sx6HwvMSmeM/w0iG51nfm9dxezgk0p21bJ/mYw
a09+boez4GerrZYjsrcf9F2os/SmcesV1po1/DUTfP0+6gBFrM3AabuHsvui6YM3e1cSLtLLx9Nt5OxKxmIl1GG+8gAxLv0LZZwa4K5Dzwf2K8Fnt1yCniqDHvAaeTds4M275V1PaB8XWGzfI+xCRsj6ht9XKUie9D5rb2nACeK//FezxXcFpNZVVlfVVjTSOmOOic73O1jE0HbjQBL18BB3Z6z5g6NLINPxdjATDRw/MgbVUPO+s
84iubftyqLjyfcDHAj4MrNr11OLVZ7x00fdKRW4514Y8OfizU4g9LYetYWQv84d1ITZBwv8AdK2AS/d47ogvaH5h0uk8U50v8XaqElg5ipLuJ87Q8gXrA5YpxRXsCVUH+dLO2nJ8WSOwXFM7yY5ifM7MgxN4vwDp8/mdyJfZADoarKUxT+AGF5RQ+lPtykcSuzcHwsO+eMok9GKoNSWxrCYZPU7wycp5DYg9T+CcPppzrvg/aej+I
KaNCTO5jY/jrl6wf4hJLuhGngOKe0HmOlJYbcmH65VTnW76fFrjZOgHj06HmHJYqfSmYw/ZGMPyGC8N49KUg1Jb/t6I+9gqo2Je1ej7Ow1LnASVBdl0kWSyxF/Iw7g1j/JFYuSCxr7mPL4SeMqTtXSj7I62sB6hys7sL3opJ7EAIw9YIhr+k8G6GoZKP4Z0UXyFieLwfW5xZjBwWYxi/hPr4TgBDJYR8+BeFfYELo/hj8rUh6J37L
fypUS/iPEr4ySDy7U0PhltKMeVzxOe5xJPWXAwvpd7NJj7/nuLTPFhz2oXhumIMHV4Mw8S3Bjfyqr0UeSVHEb+XuHpbHuI8F8F4F6U8lo9c+lUxcikUxpTbnfUBCfiG8RHCv7isXJgnrI8gr8rLMGWPguFBkHiYnUk4jxFVItU5n3h4hQvD8ylcRikfED8HKF5J/PyNrZbu0/wWKjrDUYu32M7KzXcvJOhsMBTnFue7W2CEcKg3ip
APRh1CAxpkJ2hMg1wEdWqQm6DbijjkJeiKCIdCUGuArSkb97awHLBYCP1KQigIY+5mgC73jntxIVRAeZ1hzMtl04jO00KXOhbCWK6kvH+5LnW0sJgG5QUQmsmqCJpOUAWrJeiGGELzWCPR8mUFoUWsnaCrihA6lm0nTFbCoTS19y9PwrsQoDOYCzDviyS8J0IpDn2doOMBwnLvKAmg8wSAsA/t3oQXv+U6l9MSxLxudhXUGWA1YYR
WAR7m/ZnKrWMPUN7bEkInsycp7ynK28J+QXkfiggNsjeJso+Ish3s7+xswPwRYZ4KEJb7B9RyPhtjRwg6Kcwhm4DQb/2IOcZkAft+TTBQ3MJOYzkEXVvCoQBBd/s4pBDkdnMoSNCdGmaIoK8VcSiXoO9o5fIIukmD8jlUdGUYoQKCFpdwaCZBXw0jdDqbRdD9Sl0xQnGi+jENmkN5ITuHEjTpPGNDq386qxBsZQFWLCO0ByHAjNKM
sJdVAcTYL+149+HZrIagHxN0EUAewPzEgd8PfQnzoL1bo1juGsIM4F27AF3L6gk6gaADrFHIE/hvU5/IrmPNBLVlQM4MCGcLE7pa1CFJOk260bd67xHpZghtNgy/RuEyP4Zbwzf7GtgvlNsgbPdhuJLCTRS+HL0DwpD9Ll+YHRO9xyexEz13QZiTi+EL0m0QvujU02dByn2+arbJ8SiEuY4bIXRRWEXhx3YM73XcBuHTEAqspPBbv
jJW7PmeT6fzXuFZCL9hexbq/KD0RginuTC8j9r1RDB0u7DFdiemt+VhSkkYw8uCGP6F6DkzhDWECp+HMO78kmMW2138IrR1ctHr0HpAugviP4PelTGvcgfgvBzG2nYEMXywDFNOcOn1zKLWZ1Hrs6jFWdTWLKpZYC3yXdCX84S7gFdF9i85sC+PQi+etb8D4Uc2DP9C8W873oE6R8NYf0zA8EIKi6jFCzxmnHkRs6voUcLH8KkYcn
uv/zaD85NxzFyBvV14G/TuBekPEB5yfw/C1tybIazIu2dC2cmlzi/6CEKlDEs5KJxcaiI9ZlmWk6WsxpMCyZmzem/UgWEPxCX2LQ+G1trOL/LlcGob2JkO1MM5UH+t0G8L59QKq8UiCHMofFSIQfhNNhPCB8S5OQ3sEdu8nDDrY3VQZ3PsLkOvBh2LoMVKCcO77Rj+D4WLKeV3lPtTCpdTWArpetmn7G2Qsk7C8ByKL6F4ksJWRxu
0tQM0QWJPFiNnRjwYhkownENyuSX3DtCWl90XII73+BweduOrSLY//7z8pTkCe4+gq9jfQ90AFZdx6PzASTk21l2m552c42Cna9DKwMk5MtunQTcHkjkudr8G/UtI5njZGxr0t8IdOX5mn8ahT6JjOQE2rEHPFp6Vo7AvadBLhefkBMnz3Muuih22XZSTa0D+vEsBeljDvC9wRU4ee0ODngjcawsz53QOzRIO5ETYWRr0N++V9nx2
vwYtyD2Yk8/aZ3Bon6dZyGdJgr6Q/7l8AWbmUQ6xb/hvwm+WcFEEdvVR/4UAPTNTx7yQFbK3ZprlijT//RnHo34r9I0MqK3sthwTKiz8Wk6xAS0tu85WYkBbAIoa0FjZfTllBtRQ9kjOdAMaL3siZwb7iGj5rYCtz2abZnPoGwSdn+AQtj6bXaNB2Hqc3a5B2PocVl7OIWw9wV7QIGy9gm2q4BC2Po/dr0HYehVbW6lzIgBeybmVP
O80GJV17PpKU8/qmH0e5+6Pi74PUOU8k4P1rGke57W38Lmcevachrky9iJAM6qsmFUcYu7AryBvaT2HHi56A8ZgbgOHVhT9KqeJndtglmtmt3LIKRXdBNBLGXlvGNA7Oc3svUZeyx1KnnAsK2/i0AXOD3KOZe9p0B9tmBeYz6FxAaGLj+HQZcJN4FvhbwZSLQTh5cQI/cuJmN5FHPqB9E+o8xOCnmHPBfKExWxsscmzxZqk98deCz
G/CY34FsgtFN8L0H675G81IJvP5283oGJfof8EA7okd5p/qQHtKKn1rzSgW+U2/1oDekde5t9gQIXRk/ybjNZX5g75txp5/QW7/MMG9EDJOf5RA1KhvVMNqNG3y7/LpDp2vn+3Ad1Qerl/D9tLXQT7Yr/efzZb08KhufZb/eewWzVo1H6n/1yW28qhBfZ7/eexNRr0zeKlOeezAQ1a73nEfz77hgZ9sfQR/wXsIw2qd94Jo3qwjUN
S7hP+i9hzGrROvtN/MVvQzqFTALqEPa5B+4pv9e9jAx0cOtX9hP9S9qQGXRC81X8Zq+rk0Hfyv+ffzw5qUFPBc/7LWd1xHLo89rL/Cna6Bp0Se91/FXtBg8Zjj/ivZrnHc6ii5BH/NeyK402duJbdruXd6PiN/1pWdwKHvgLQATa4hEO3x/7gv459pEFzlD8D5FzGoZMAup6VL+fQQ96/+29goxp0k/ffYPsu06Cve+2Bg2xwBYfK
vL7AraaeefICX2UfUN5+9rIrFrjbyHszODtwD5vRzcsNBv7gf5jt1SCppCHwMHuTID7+HmHvccgpF+QJjzDXiRzKLQhAXr4G/S4/T3iU1WvQR2BtHmXtGpRX+pDwGNusQTNK3wVoTIOeh3KPs/0a9Gso9zg7qEH/LHlI+Bb7tgbJUO5b7PkTTcq+ren8M455wWMCVqg18KQBfax0Bb5jQGcWrQh814Cagk/kPG2B1gW+b4H6Az+0Q
IOB5y3QaOAFC7Qr8HMDsgWvs71kgfYEXjEgnLl+ZUA4c5nQ3dGb2K8N6MHohRbo3KJzA69aoEsDr7E3LJw/xP5t4fwh5l1pcv51NnelyfnX2YKVJuffYGtXmpx/gw2uNDn/JvvCSpPzb7JrOMR+5DoQ+B/mxE93QV8edh0MvMXGe0ypvM3OJwjnuJsAuquXQ9jbt9nFqziEUvkNm7GaQyiV37IxDUJpvsPKT9Kh1sDv2BsahBL7A+
teo0ODgT+xRw1oXeB99pwB9Qc+YIcMaDTwD/YXA9oV+JjZ13IIJfZvdtCA9gSOsKZ1eo++GhCEu9bxPJw37ULxeg6hxOzCBg1CidmF+zUIJeYQnt6gQ5cGJOGFjabEZOGPG02JycInG02JOYXCk02JOYXyk02JuYSuk02JuYQ1J5sScwunnWxKzC2cT9A5JDGP8C5Bl4PE7gl4hWV9psR8wpo+U2I+4dU+U2I+YcEmU2I5wsWbTIn
5hVc3mRILCBf3mxILCgs2mxLLFa43oMFARPjIgNYFCgX3FlNiJUKxAY0GYkKlAe0KTBcWbzElNku434D2BOLCjAG9Rw8G5gp3DZgSKxc2JU2JlQvXJ02JlQvxrabEKoT3DOjSQKVw1zaNn2D55gnPahBavnnCK9tMaVYJf99mSrNKsA+a0qwWpg2a0qwW6gZNadYIJw6a0qwRNg2a0qwV9gya0qwVLhs0pVkneId0aT4eqBcuGjKl
2SBcMWRKs0HI325Ks0E4fbspzUbhF9tNaTYJM04xpdksvGFArYFjhOuHTWkuFLw7TGkuFs4woHWBNuEiA+oPdAo3GNBooEu4x4B2BZYKT+8wpblCOH7ElOaJwg9GTGn2CN0pU5qrBPuoKc1VwuJRU5qrhOdGTWmuFs491ZTmScIC1ZTmGmGtakpzjTComtJcK5ynmtJcK1yhmtJcJ9ynmtJcxzfjwSajVNYb0MOu7wY2GNAHtoeEj
cJTVO5cktFG4TmCniFpbhSa0hzCcicL39AgLNcnPJ82ZdsnvJI2y/UJS8fMcpuEF8bMcv1Cx06zXL/QTRBfLfULT/I8WkltFtacxqF5wWcDm4WnNagp+EJgizBjF4dswQBLCtfs0ut8ObBVeNyAXg8MCq8QtJ+VFv0mMCT84HSErmLO2B8DpwiBz3HonpIPAyPCcxr0E9+HgVHho70cUtx/DKhC7DwTc6cw8AUOPV3078Au4ZMvcm
hh0YeBPcLB83l7f/V7lL3CGxr0b39Q+bwQu4BjfkH+Y+BcYfRCDi2OCd4vCtdo0O9KC5TzBe9FHPo5QBcKezXoBwBdLDytQYcA2ic4L+bQ26EC5TLhYg16yTtN+ZIQuIRD70HelUKVBr0Sm6ZcLXRr0Ncg74Bwlgb9EPKuF67XoKBSrtwkvEIQ9yMPCoF9PK/HW6scFJou5dAgQF8WNl3Goat8fwx8Rbj+chO6Q3j1GlPudwnvXsP
58lrJQuUuoepaE/NuIf9Gs717hRk3muXuFSoIOocNsnblXqHVknefsETL28Nus98nrLXkfVNIEcRH6jeF8wl6mv3Yj9DDGZhPabVcxLoC3xR+bcm7X3hby7se8u6nXcxj8GQNezpsxn8Wwvj3LOk8/ktLelkBvlt7/igpAntRwnB+kR6KWsqHuWYultLjX/eYcR5+oQzDmYUYrvZgDXdGPy1uTbH9b64nqWC4h3iy1Inha2HEGQti
fBGlYFxkT5RhqZV43oudG8J3jpV4PQ6zuxHnhFx8d/uujRnhImprr19PEZkawhpeD2ANt+Dvu7EH8I5GNuY0cazxtBPx53tEwH8MQgfr84uAP2ipM0k4eySs8zKqc28Y61yWj29Q/dGJmE/LE1O+J9O3QpZ2f+HB9AN4xI09Q+12FWC7qwpMnCE74iQJ53jC+WYp4vyg2Fq/CDjjBUj/JVT29PDE1o/euyUy1vAbN+J84J5YdreF5
pWUcqWsS01krztNmZqhyF6REbPAkr5oEmaHbMY/Z4lfbqnnC/7MsqKW+72YiclzT8idOhRZU162FBtbrCBva5Vs6QKbR9p1QjGmnEU6eWMhSn8N3ovALihE6eeQzre56HMNend4jEuAUusgtLGhCPjn7HI/cn6MPmy72Y/fVzzsFJiT/YAo/7iUxpr/aOEzMZMb1ngLjaBLizLT9XH3fyIlM261Qkwxw6n6xS3eMRa7l71HU8X/v+
vpqGJqywm5/7f0epfR6/+kv/+39dra06niZouT2+W5YhY7xu2e1VItdWamTBU/OibP1efc12h2wxlZphk5s9STXow7AhPjk9ving/vi7VfPD47Zvo2nx63sd95TV5Z5WXN/U2JmWvGbeyxkMlzTsPEkZuZcjS+2TJmupOnyJ1OczH3zbietwS9bIj5WBX8DbFC+CsGb7YYnqXwLIVnDJ4xeM6HPxdDz1OB0MEKKF4GoZtVM3xz0kx
hC4VdFJ5I4VoKhyDMY6dSKUHA8GzyeN8X3ovG2AXsm4VzIRwtqmIu8XP5deCNfxJcxBRxSV4VhMcF21mZ+ISrG9KfKFwN8RcDGwDz5ZLN7FrCrBaXlmyHkMXOgpTXfBcCzixHN4R/K7wMMM9RrmJvMha7iTWLz7nvZV3iy/5H2R3sGPkpCNeV/BBS7sr/McR/BrPkfqDzVWj3HAVb36e8BeFrvnehnn2hv0DYUfIhWyu2uX2CS6wt
zYPwyrICYa2YnztHGBKrcucJp4r5rqvYGSL2/WwR39SdTX1/k8JrqX6k04G3peafLBSz3aWjwgwWiX0ewlX+L0LK2dGLhZ8yXCVgqQuBqm7hKsAvC10n5FI9+9kC4SHhAmqlnN3v/I6Adb4rlLM7Sq+ClPzQHwVF/LLzb0K1ON39LwifD2PYUZIjlrO/umZDeGr+IrEOWv88lLrYvxzi2G451V8tPlWaI1aLddFTALMsdIO4X3w9d
KuoiKNA1QJq5UQBW28H/BcB0+/9tfhPKvtPdl7UbVtANGDcb1vKfly0XLyXqC0gHSgQ7nF+0VYgxN37bGWQcgWEla7rIGVF6c22OcJNrq/aysRbbN1sjnBVNE94VtwVuBfSWeFDtl5qZQOFA1p4v/M6oVo4Nf81W7Owu/Qt20/Fs33v2AaAhvcAH/kGcoDebWB9seXiAq0GTHeJG/PzIB0xFxAn3ye93cBO9f/NNkz4vVoc8ZcSzj
ALFUXtY8DDevtZwMMvCguIn+cSP88lTp5F4S+p10sp92LKvZjSh4mGpVw3QFcH7KjVI/az6V3aFSSj90n6a8VpZVdCbk/Jtfb94s3FByH+46LbIH5W4Z326zX+/77kYTtqaZ7wU/G5wJt2DFE/peLf2udo8Z6SP9irxS/6/m3HFv0O1JlSx1rhiWgdhB+Fr2JrhT9D+D57I3oT+yeNd5f4p8DJDtT8AQhZ9BTH++Jl4Qsg/FHJxY7
32QtlX4LwyrKrHF3iQ+F3IWRlHzv+KRzy26R+0pB+4fbiUyVsfZck2H7ryhOGtPSfhQUY+zcUzIX4X4vHJZft++EvSIqN9MTGcT4oBWtjO+i5UzpDqIzdA+GOwgehtmuU2+xrxS7leanaNlD4Cwk58GupzDbmf1daK1YU/llqtl3j+RDo/0HZQeDVS4V+eb/4bOG9trOh9Wlyl7g0WANhu78RwrXBBXKLDXW7S+wWlshviscJ3fKt
bEbJlfJdpO13gQTvlu8nCd5K2vI4pT9Okn2a0p8myd5P4eMk2VtJZx4nnbmVdOk5wP+H/AvCf5zGyOM0vh6nMXgrt7TiS76LhVcp/iqVfZtaeY9KvUf1v62lYw1vUw1vEz1vUz1vU1mXOMv1c+cHVPYTKvsJlf2Ayn5AZT+gsh9Q2Q+o7AdUtov4fwVhXkE12AWswU7j6AoqewWVvYLKXkFlr+Czg23c/6RrmEbN++xm0I0TqbZc4
qdXQE7mUm25VCqX6twv/sTXDL3Gtoopt5jSZ5DFmCEgJTMEzC2n3Fe5HSMcl3gz2mHhTE8VWNfjghe4Ubf3u99nAddVFH+LCURDnYDj5VX2UeB19z/ZJ4UXsjuES31Fnn5bNHYh67dtd5VBvDMQhzACs0a/7fr8eZ57BX+wGVIuhvgjRM8jQo58IYQvlZ4AKe9B+BSkb/acbesPBdizUOeQ5wJbiZKClGe8Kc9PKXc/5e63/dJ7nu
eXAo7uanF38ErPm4D/qGcB1bxAQGuGI1TwLhBQ094UbxYS3rXC92Gc/k7c47vT+6Z4jXCv91rbM/6HvU5Yvf0EQi/7BYQB9ksIc9khCPPZWxCeTrlnQS4sG4WfQGgXMO4UfgmhVzgE4cOU8jilPClgKadIdYpUp0h1ilSniLnF4rsQxsQ/QjhD/CuEcfEfEFZRqToq1USlFlCpxVSqHUrNxtOT3krmoTDETlIqWRHbBOF09jkIE+x
8CGvZNRAew74MYRv7BoRLKL0HwsVUdhOFeyk8h8KDFH6Zwicp/C6Fb1D4FoVMwDBG4WIKN1F4jnQKlqXwuxRukTE8h8I+4XqfE7zQT7x82zrC+DMfnrMYHpAQGG7KLWIC/WrjsQzfhDG2GJ54M0EL9HA+2PoDYA9eZJ8A56NCvbBIuEz4svADoUbsFc8SLxKvFL8pfizm2Rz2lfbt9p328+0/tf/VnueY7pjvON5xquNGx1cc9zke
cTzt+KHjZccfHT6pSJojtUlLpfXSRdKN0mPSB9JhyS6H5WI5LrfIJ8lJ+UX5LdnlLHEmnIuc7c4lzj3Oi5y3O+9xPuH8vvOXzg+cdleZa56r0dXm2uAadI24znBd7rrV9XXXY67vu3Ldde4+93Xu+9w/dP/U/Xv3X9wOT46n1bPSc5rnEs/tnvs8T3p+7ZG9jd6093RvkOEpJLznRmYlwOso87Np9P2Du+gEWJvkF6yA8JN8DOOlP
RC+TnEPxf/T9KPXNjEXbxe0MbxV2gFUngmhyHbTaeqzIBTZOHi4AtsDocg+B7QLDPVKBE/VB/HP00nrq6A/ArsaQpFdA74w+nIKxA/Q+enrIBTZ9SwP4jdAKLIHSEsehFBkD9HJ6YeJP48AhwT2KIQieww4JcAMUoJ7cMAx8P4hFNlL4F8L7GUIRfYKjAtYvUAosl+xmRD/NYQizAuzIf4ahCL7O5sD8Q8hFNk/YAQJ7CMIRZjBKy
D+MYTz2aBYwr4avD/4o+Dd7CSYgXcLjwnHid8TnxP32p6yPWt70faJLWFvsS+xb7TvtX/DfoF8s/yo/H35x/KfZcG5y3nAebMz5Cp0XeSyu73uCnePe637Zfc/gVkF7DAe3hWKmD8P9f4C9lpIhOdFbMSHz0vYfjs+L2U2gvezYnpezi7JxeeVbEeJDZ5Xs1tlhK9l79DzOlYYxecNbCXhgS3GnUXhZvZACT6/zFRKv401Un1fZft
j+LyD3VAqsk7hHWbzCPD8A3szKLDLGgWwhKc3CaAFL8xHLYgvFEALuheiFvwFwnFm38u0ka3/y3fzbzH1f9/yOvAzFdAmhyUtDz+xmYD3UnBi2jPeZPFkPH72vx7sdgMLgp6GWBP8NcPffPg7Bnz5BfC3kNWBdakDy1IHVqUOLEod2Z8QK5caoV/N8Hc1/F0Lf9fB3x1sq/g1+HuE/R2efxebheftxwmnsyH4uxTiX2Nx9y7xdGix
BkbuCNi1EzlBfX09Y/1jQ1taVLX/jK6RobHeM0aTPUNnJhfWNFSxBYu29PW1D6VHh/vPaBvuT6drqvuypGZNrKHE5r6+JowclxzrPiV5xsr+kW3J9KLNZuqy7jYEAWhPDifHkp3D/du0hJ7kmAkdv6ylref4lmrWWtfaUdPc3t5UV93W1NrZ3NLZVt/UVN1U09bW3FjVWdPRWtfc2lBd29Le0FZfVVXXUdNQ01LT0llV19Te0N5Rz
bo6RnbuSKr9m4eTm6pZy5axodTIJjN5LKUCtHQoPQaP3qEdyWrWtrKttoYtG9qiptKprWOVJw2NALwy2T+wqmtkDKK9KS2CaTzWuXNky6YatiR5xur+4Z3J7v4hFcD2IWquXz0DAOTJ0EANG8UAW9KTarUKG+ogwp88o451L+lYW1NVVc+aWjpbqjpbm2rrWhuqmlvqGxvrm6vq69vaO5pbq6qrWhsbq1o6azvbqprr6xobOzrb69
s765obO6trG2sbqhrr2UnqEHB76PTkAP8OrLqB1be3ttTXtDQ3NLVXN3dWAdPamuvra5qr2qqb6muagOcd9VWNzR1QeX1rTX1dczvwu7Glsb6ptr6htbaBgYBq6qGe+tamppr2ls6G9va21vaOzo7aprbGuvqGpo6q6s7mxurqzrqm2vaahtbWpqrW5rqa2ubGWmigsaW1tbm5qeEoWlnf3MBAuk3QmYaqNiCktaMWZN/UAd1uamz
rbKmr6mzqbGipq2usranqbGxoqW7qrKup6mipaWhsbWjvbGlrYN2DZ6SHtvQP94CskyDMxqMNg5qmo+TWHi2zur6J1dV0NLbWNtbXdta2NTZW1zfXV9W117W1VdfX17Y31jY1t0BOdWd7c21VY21LdWNzbXttWwsIqQ44Ud3exLYlx/pW9XY2MaCzSRd/M44stmBZamDncHIRW9CtDp3WP5bs2jE6nNyRHEF6UiPtybH+oeH0InZc
GxvsWdrG+GhDbWbLW5Z1tGNCzxnpseSO9uTW/p3DY0vbutrZuqSawudJXcvbV5zU09fS3d3XRbhdI+mx/uFhqhxS2pOjqfTQWFtqZOuQukNPBTytNhxZp+nJoy2joxm1JAfQHkBSz9K+9pbelr72k1asRAhQoKsDqV3prpGtKa1iPRMo6Vva1daxvKejr7NraYdRevmK5QhgvHdtN0a72rWIpQxr6e1d2dW6qreDtS5d0bakr7ulv
a+na50OUrRjee/KtTzaA9jLjyMZtPS0dXVRXldHT193x8o+KmIQ0LNqmdZWT++KlR19vSuWdCxnqztW9nStWK7lACuBkJZeTOleuaJ9VRtFuQwqu1aA1dnc2wOd3pas7OnuZkuGhofxuTIJLFPHMNq2YnlvT9/xHS3tHStZb9cyCHlS54oVvQBoDS1dmsGmnsnplMTj0EUguqV3VQ9rWdp9fEtrRy9b1bW8V+ddS08v6+3o0WGN8r
6eJav0FNBKgxGtXctbVppgzzojumzV0t4uTDgNLWJfH9uyGbSiZzS5ZWjr0Jb2/rF+NnraxJQtm7vBhmYiTU5C8ziYGkkSMIBBb+qU5MgyGAKZo3012PV+HAKtw6ktp3BoR3pLSh0e2sxg/KTUsbb0KH3pCjOaLpq2FCgsWe505XHJkaQ6tIW1DEMNbMfoFjY8tKVrgI0uHdqSHEmDSR1OAggUTUpAjafhsk1L28offOZbNTJ06k4
EcaxAnXzoDNCQGMGJKbli69bhoZFkxjgE9NFd6TMnpA1lgjAw+GDVasgYs1ADVDAhaUsmaBnL1BMczQOsn8Lj1NROgraMaXV1nAY2SKMCk7pVMFRbxnpO2UkQCM+SyiGNO5iuPU7cmVQxglMq6x1U8bE0BUHLwAAbHm09YyyZXpkc26mOJBFecVpSHQaCAOhOje6ErieRgC3DOweSGvWQAP7HQGoHGGdqseP0seTIAFiioQEGszSE
y5O7jtsJTxzxrTuHhgdYxwiSAF7NliS2vLx/RzI9isBge/I0EDAb4I9Vo9vU/oEk26k9B3Z1pYCnY2pquC0FcBpqXIYRFD1FBnb1DParPN7dPzAAczDF24ZGB5MqRXuSqHY9kDOcXI4Ja3YM07M9uQUfNDmMDFG8Y4QenWoSqgBujZHi9fRv5WjLkul0/zbqAzlh6JnwiMrBZT3Hp9JjbUASQKYhYr39p/AasOu96DURFQaAfBw5b
UhNjeDMs7pfHaJk08liXegWptI8nqZxqkmEV9B2PEgFIit3joyBF9Q5lBwe0JKQfEsUe5SJjJOtlgKEINSppnZoKb09WICNbtlsGYowXjJAk1dssDcJM6gOkQVJcxwY+Cl4Do8iiH0nPSfPzoBWDm0bHCNoBIOVya1qMj3Yq+4EEzKA7h1I/DgVVIfivSmsiqJgtHiEXLKlMD6hwR2b8bk0BYZrWf+WQQRw5LIOUG3sJhslY0fRJB
8HXQMc0kYOATpzCSB6KaYbQAJIT1AV2UmgeEnT6KlJGnFkOK1zU4ZFZV2ZIKimesboWGYiKOfkREuNxGutOkscRWpC7Tt3jBrpPJKmkIuwZ2jbSD/wAVjf07IabPTWM8yktBFD66UCQ8dgZCEMngI3lv9Pe18CH2V19X1nssxMQobMYDAIgSCiUMlOFigUskFSEhKYhKUNhUlmkoyZTMZZCFGoE18oWHfrWhWXWu2rtYqWulUtrVZ
qW5VXLWBFRcXKq75o3RXx+59z7zPzTDIJar/fr9/v+75J8jx3Pffcc8492zOZgT7q62zqbA6j1xmkDhytkbpi6p1OzvrZMNH+Pq1WGlcri9bghHn7cJfnATIQGGh2BoIkK9BeQW0jmraFUlEmQRoIOrI4nzitEIse1dbi7PWDaS6KlIKqjU5rtdPH4kSi5AeDA5oRcVWG4O+3hxn8eiITH1hSUrGeGnd7uKuL2mNtlcGgu7fdO9Di
CembWYkGYRmGjyTBAiMSd+q8O6d32CiHuyMM9Aea3YFeTzAxBGlKwwGGEeuWG+bG5W6vcwOXgsOnK/uTCG6v3+kbiHUoXcPtIU+7xwvEdL2wTGSNyEOvwgFj8vNRI82jCn5VAMshOrLs0ArsDwFOb996KI96X1W4s9MdoBhC+JrCIV3VAX7BUJ1FHApGy46w3w9dA13lUw24NHWKehi3DbhrSrnK2SViUbZQ8bXopAsddElQoQij1
ZZoTot0Cro0/SBtMmwT2zZlwaQO0ypsk6hQH3T4MQ2E9FGVdHQVDlLZbBl7Mg2Xhr3eFmK3j6RUdQyNUpXlUxVp81SlpU8VWDtwidQy+4qy6gi3B2VpUV+gFlpVUt7hduJci55uKHAVwtY5g90sSGAwl8k/cTQ7Q93CDVVGgs2VTq2A/kV9Xpc7oNWk9eBaSFeUN3/A0+ukw48ySUuD29eFIhiilcjfD670ULGh0u9hreXt6msNeE
TlisbK2T2kWnCl6JU1eVSlk9IgbeL01q2sr5FNzQ55Z39XFuEHyIIUCFlugS8QpGPJkiTbyBEJ+GQZWMiCQyu0q6q7RzrEdYvhOju97IZo5UbouG7cpfAKKbeoQbX5Oty1Z4ZRI/oq9eZzU9XHbqJUv6IHGLi9JcX5LlSC3g6+68yHanZvCHFRCSjcFCGdtKgrJm1dCILbK308CKGqNuL4BQZ0ffWAwaLNhSY/aU/IjgSONXp73RC
mDmILhLS7F/pjeBsIRfITa9BEMtbijJZaIBbKRRX11WQw+6Icgf/jDUE4HeFe9q1ER7e7oyeIArkODigs0Q7hEb3ODXTz4s/RAKR9ZA3JDsoMGhUqvXQlnjUFPF0eH04npKHPF1PlvP8mh9LKEB+txKpNlWvcZEK12np115lGIlYIRlcfyMt+XUAwrIvZHms8s589c2jc2g1+T0CNVNZBJu80fsPjUlGa9HRiURtbzlhtZV9/2exF
wVofKcXlbpcnoO+QzWqMvldhTUV/rFgL3DTSNFOMRRVXP5tyylywrZet9U21Gzrcfln2rad9kQ8Xa1zaFyJdjiDU7Yq1ss/ZB/0S9uladUHiMKhKWPU9i5iiuumBrjA57LEWkqO+sK4BJqYj4JHl7gBUdJCIoHfhpG4QMR9NNWi6SFWhpFSp1dfj6+v3ibC6+3WBJZjOySf9wZaHgBdl+Fo9FNC0fWUYdYfX7fYLR48Hl1CfX4ako
ouvSjjgVp/JPFoNbc+FGudAUyfXKOhBCBYILQ33trsDQkImm4RKC7SKKlZ5KHOrKgF5w+mSSEG7kaqBkKz3UAfnJ5xeaRUQOWhmnWJVzaZrkRRHlI1OHwK0ACxxF90UPKW44MBJ7U1c0jBh4xgQ/fJWxbk4nMOQRKt5SbWjKOoBS/5TV0xNJegcNq/G3TnaTH03q7ZA34YBQp0o19fQ14+7LrMuo8VoLb9DXvkmnV8VPkTrKnLoY6
6E2WVv6QP/IeohulFS0x1yolMxNeSsDFItGFeL+mSxTl2VekknR/tiFfwpCarxOLt8CJE9HUE2x7qUSFD4fVoMhrI/VmadFkt56lIeNGdI3R9fJy+p0eP1eoLweXxoqHQHo7pOuqT5oAKOjF8Jy7BuzfmP9kvHXqUagirBsJTLcY9oyD+oheR5UHSrOxQwbFOCYD849NlIfixuZ7ikwbgADwybY5Fnnw8+A8W7QShMDmAqfbHwJIi
TElX0sUZJFR+XNdc7CkxW+FxEa80Bdx2fVVklH4YLS3GwZUmxP1Zh0VBwiCb0xGW5uwvnLzCg+jqDynOSARhjz0401pXuMvBHVea5tRYC3uKB3Y76X9iQx6cV2+XN0dzcGvJ4g0JqFlmGJ1FfXwMt5ewFvZ2hjm5VRocqka5wImTVpECjXn4sigomSGnKeBE6MKhXvRAQhIaw6lr4U+f2+t3xY9QZ6AsQA2EuYCpdlR2QsyAbLVWM
YqMpSG5Vss5Y43j4QkFdzpR24qam2g0gusRQ+hJaXkUNVI1+/xCXY7j6VO0rnR5YUq3maAZyQg3iEAUbaenDaeVMDUxEVDqCIpoOqOSMgDqpPB12mLKEUFjK0BJ/A02dzR64s66m9jNAavLkVWCvZosEZ6mF8m8hwcuDbZ4+13JEegTdGeiVRUcDkQxKVD0n4cST6POvxQGFS+DBCNxD2gMagVAAaHkCwVBTQD2b0elKaBCdrqSaT
ldqnbpqS1+rH3JAngYwRgNsWK187CSh9nVIx0K16fZIQ7VuKXThQIDKQI456ZbpDRcnkLFPapdlHg0HKAStKXkna9JbIbOlDIeorHVoRbQq80GtWpFjK8FPVGBEEI2EhLKbop/NVzP8L6m46SkSPQnW8q5chlmjWx2sPAw5IkRdUAEPOs5LiNWlreY61Aw/LKRKI0J+UkTRoJrKHH1AcAJcY3aHqEQwlzv7pV6iAqdl++S9NdRBxR
4vLuwkNDo3ANfoaoKeTcqEgaxXO4OIUrU+FmwVdmkir5lCgWiSbhROSA1Ozz3opiWVZNAiW0KxiqaQqBzLsqmDI/TpNa3N0QB1psRC1yxjDdVODZo2pjI9MdDCI5n341hHFYfqQqlTuwJOfzch6B8QLQ4HG1hwCeVmGZsLDjckKdRDUg4EECNqPgfZxwHNUA4ocyDL7BHrm1t9/j6/bGAXiAoOreDmq7YlPskUFANbKtf73FptyF7
AH1WoD1L2pClQ2+tHTcgPUc1rFstFk6gWtcKBnybU1opKXKtFnagXLWivxrUVLbVCpFeKRlEjyuidJqZV8l7bKnzCKdqFV7hFroCSwdUpwlzKEy60hvDXgWuuWI8SHCbhQZ+P/5fAJzpRNgRrMCeEv1yGg1AJtW41QkLt4fYgah08O8T1EI8JqpGyJ8gtsf5+1CU02RIQAyKf3tZj2iB66XNvc5Yy1rTCAO4B4EEYuAEF4yIvO4Sf
t+ABsh6UXBhUyVvyYEtOvssN1YM8GkJhXGOEoX4vg6cNB3BfySi7UOvn8ZWoDTCsXp7RilW7GBkiYj5amhmWE6PdCr6biZ2LmQQ/DzDpQyuPh51PkYcg5wtDSoC+EKsyjLV8Yi5Wp9126UrFogi1YlGInxKUClHPY5Fo4HueWArhMSQFhEgJ0ZcFLesGfOhhjC3ATz//5KPHA7wCwCaIv06MyGeW9WJMDeA04r4K/Y2AW4xyC7esp
6+2izxRIAKMlJeBSFlwi8UMLoylqH9or2zrY+6T5NUreSsQhObcqPy1RBkVHNbXoKRpaHsVl74vFrL8E8vmi5OBh5SiaiY5iUuX0GT7ZPoe3iS/EF3fnDzNYgnIvhol/QphFhON0QUgWD6YJAYIOq3SzFBdGEdisWQYhkPn05yR+4PHHSHc/8rKctRy3SlM3C48/8oqzWhtV/IiZwRH7BHlvegljswFJOKHE/1dfJClbunluZL3Be
qolH7DeXOEODFf4RKT73r6NsEpWnvlMDjcP13rXw6InUoN6CnBo8ZpoxwslwFcxVitrZaVkpgQq4exlhNnZIDVgcjJj9JJzl2KEb2gGJ2wGOb12PkK3q+H4FlI74Zpvm4PCbHLid/DEApMjOHl4r1LnnJfXn5CeahhGepgWvljMjo98WjJ8ehuI4OLsAkPKwdX1MB1Kt2di0H6ybkgBAlaB1jiYTHNxdKEvJ8J4U44RzM8fiaoVCY
hZSphgAq+nhCJsWSSe9gm9NNGLVGxskQFs8jBODWrWVVqPxLnRAQReaPNaGQl2RFVdaJgtNHDhVekl9KHIcKhKEKZMJyNw1DGZXIzClV7CWpFZA8mnI22TaINUPpY9NrE2ejZBOEOMvWI5qQ+O8m2JX1bCJucka/GzYcL0wQhaoTNqgFcUST781Q/3YtBcXJ3NqFcotpmc1spaoaMFVjby8IPQTlHP18bE4OizS+JwoxBK1a1Uq7N
VrWyaC2fuUY/1F4ehXe2qIiOMdSXYQZRqxzwasUijC1HP/E9DyOq0VKDUgVjNpvbisCXcrTTtQQ9c/BXAUhVuFJLEUbOwV8eOFaMcWU8qwQwq7itHL0EnSAs4msF5lTyGjTfMLMO41ehVCNGL4mkpfjLE4aiKmBaA1iL0ftdyF4jZGgZVEELlMlKjF4NTEowr4x3R6qyhRWL9GhcGCf9J7F46Klxs/vpY1OudxOkTAZZbqWr2h01M
aQsSX34eawLo5roRJ2WyMw3xLkerJCWxbcNdV01Z5YUrEt5caQP2nlsgOU4wFpjPeMCXVAU21UQswrA6VasTI5BHXBbijqVW8GLBuBQDW1QrfbjAww4u/V00jpAuWLm0Wx20stAy2Lmrgut5N2RLJRghuwlqpRg3SKWMZKKTsh/kM94ENh14HQSPqqclzgo6GBaBHnf8rTMpc+lmOLgEQRL05naWaUf4VnJetGnemnO8Bl6XEg/x3
T2LB0tB9R48qZruE2OC0pMpifS9UG1loaVKJH3WI9fjQ+yxtT22Ml89cpgY3or+/997HPrcQ6y46F2mpdo/bBupn6OmBMrx486LjZFx+dPjJtMmWkxVyGGvTZCYd+VmE8jzfrGXDp9JC7JlfRriHL9erExx6VQlgOaxsEBcCNsy0qcqUrYENJsFBIXoraIbFJSM1yEHYkQ0mLg+AhYM/Uh5V/MUizVwkvpBnQzU0l1kKnXBC3AzNI
gxKLagqhDkatCywJeMcgrOjlukkZKKh2Kaa8qh4YoxjkuY71dyF/CUI5aFWuBOSjT2a9iy1vM+qAa7WSja5XdKGENkie+Jegf8srRW8H6pJTtBFmMCmV7SnB3se0pYpuSx1qEdAnBqFE+SSV9KURkZ52KcNZCgVFmohL3tWBCpcpJkIpr41zFIrBnJWcrqKVxWPTUNizEXooZbYBD8UBA0WNFXE6CIMvZ/Uw5t3KGNA7KUc3sEYdU
KA/3JaslmqFwRHklbC7lDuULWSLnhNRFm46jYuLwtjYtgssZ3rc2ylsxfbTeKIzKRNJJqqJDGbzRJQ7SYpsOShLla3BdTt+uFLnDwWRbr+ybJFKnWiaIxZey2PczkB4RP7oNTCPENW+xDUD72O+V5z4xM4cyRm9btXn6RFGU6JGH//3IfhUpGgH9rISt3z4+V2PzhvCzKSajuXw63Hw6NPfDLTaonEcuw5ItfoW7FsI4lfY5TRhST
qM00vx4qGGVPhpN0Wp4A8YE/WyNN9wz7bTjYIm1FzQMMX2JYI2i7ie0gfr5zDc/mxyN+8KUhzOEFXAvovscyiGtj8a1udAmlC3VMpXrmd8enXFtR5lMmXCuVAGPZgoJvy61hwBTQ9MXIycJE4eOygCf8+/VnWJcfODILvDUGnaOPbwvr0gwYtrxRszGET7vf+fW6pUPHmCfmMhYywLuVUIT4EOuZ44utTVBH/VREswBMjQAOxG5L4
ZkK5prAcTBSOWxS02GjwLw/9Osl2HiEkFhRR2vHp+REf0tnMoIsky6eV5YnSxP3HnU0hx9OgdLpp2H7mOFIqsTfoqma90s7TI9UcEeypbRcti9KuLTYiW9C6VlWbQj1MWkcisujp6B0XLjTlYNQCNnNCxESWz7nRzHyZyQVAXNCRKRgNhRH7eGpgy+Dpb6+EMyREZUlHdYRRHKskTGIX5vX2dFYP19x4gqnJSun0XHE4XztWA7l4i
hD1404dLS3VreitzlDhY/p06RUhzRE+ccxxwvVownxp/ZxdqJ7VoUnam1DcU99qjqmwl7Oa0/bfTcWTPF6dNHz8iRsSn+SqNKvtIoKNWp8aPi8wSsmkfN4iVIwJbGj28GxD6Gl+gURXOFJfGzHDyL6FrJIVS3UnUe5dpQn8hYpFwwkkGxeqhplRI/eiDlVKd1JDeJJce0Fko7Txgsa1VWVtTrMzB+fvAUg1DAYVmM/wVDpF7ukOhf
ABcufizpiV6WKZ/acTyFNfowped8vbkOzA3LmfNHx1/TWjS2lanaCErJHAfoPtavw2It+KCviyx9TXtwJnIcgNrMdrKa87Qyc6vytVM6OPPQza52rBx1dJd9Pc0T0wUj6ps5Q6UlPoMY78bG6ZGJQ7Nv2tNaUCY8Mp4BbnMrh1rTvgHeq14S3cqxDMdpHkl5jwrwYytyIH96Im7KEeR4BnlHBThJVV95LOVfhWP03fQCm/VR69Idp
3v1+VMtJOkhXBfLx+zO6NOQDp2b7BzRzgbjrCuFL0uFfNo9kif2Ve27zKkashLJpzhdaqV4nRefz41qsGXDKdvDLlUB6zL5+FiG4wU6HVOgsr+aN0rj1er11XCDFnF2ZhFnmvI4205v1Mjj5yGU0af8TBHnZCgHP0fl44tUZreG5xmWOJTkSb4EFF9iK2vaMuZVjBgm1Zfz2pTdp2sFZ3Jmc+aHsGrHyp2cKyrk3E4efyxJOX80SR
k/uyErXg2MDU1roT2m4SfmKNeCB/JdBbJlBa41PIbGnoIf6qvkB+F5gNKEueQSU4+h8eudPulBkPObO4wH5KMl8p+6FIyRZGt48DayTMN3TMI6lSNjrWFcr8aP8GywnjJ2taA/PS8r5exdLShdzc9/ZmNchcrGlXHGkoKQCuZFLUtINWbIp0aG1m/KkWrFlxbuJUlsQG2x5Mu/ALWJe5YngjoKtzvUe2QCQ7RTiGnnV4FG7GkP6dC
lyltIzNc43TMz3ldp5Wz3mfxgu56fPmmWVLi/ugbVQ9HkQ5OhkbBSUmRxIGyrpEx0dSKZdXFUFOBkc+g4HtFIcr9e2R+ZnK5TMbd8P9Jo/pX0mDu4HmB/mVI1ouf4a0gPgKxGkLX7N15rai/btaCytuuVX0F2Nhe6Gp7yBKlDlrN8tvBfk3yzW0cl5I/2mjvkTUVBkavkKxYPOPmMeziw1iyaxsFQNICO5yXwS1+B9eitEpXQBTGr
prV9TTu2LPFZo5Y2Pjdrh506ed4oAUpv7aO+ZuZuLZ9F4fwmp3cxZ2iqOEOTp9MO9fx8Mo9LtBaf5K5/fYUWfs65RGcR8nBvjl/H8U3WaeURGpw8fvbTgHqlhJmhSchsiiULCtkqz1GpntgTe61UxHqYNDH9GGqH+wweTom0K4+jgBOOQz0GaaULNO/5a0CJeY7DoNTHx2fyZIajeXV6P6G2057RPYTGxL7Z4m/mmTlG9rcLGKLM2
3lE/Nu7VkASGsC9Rn4aPmSv/Gw6UfwuPUB9Og37Kf0q773p5qiPaD1bPnKZOLLeEZYyfuo2J+4dCkO9xhj3EnmNQ3b0teCMIgWLjycF9G4Mx/FloLImLi4bnqWpVtZraP6qUMtflY9ky2JQh8PDymtiGYehWjv2rlzfN9XWU0bOBcpn5PGZvYRjpjYPkX8t9xUdMVGLwKtYhmgP2ttWRSXJu3z3iCsqtZKW3TxaniP94wktyeuUe6
jW1kvkc3xFGDnxPtAKPn8hjlq9QpjK5Rkwlcn7yph0xufGYvIX4xpFn1oGgKS2Tp2sqmgcGZXW1n8FbizLob0hWEFdcrwz8D0+O306GR7xHJjku7Hxqv18/KRg25dLH/jommd2HjkpVyTlCkNyrsFgTsHFlkVFKxeLkk0GW61FGA32yBe2QUOKQDUDw9NSco2GJHOSieYI+6DFlGtMS7MNZqDFmiLQYgOAnBSCaM1JQW+ONSfJnJF
pMGbZI48bJovJwpyUZkhBiyFnslCNtGhOCs+0YhUzls9JSc4VOSkWU7I5J8XWmpNixExhsA/m2AanpgqDGSWzMNpaJ9kGZ2JOdqpIMkzKNqaajPb6nJRUQAR6tKU0U24SoSRxSkoRRqvVmm4yWwhNs9FoSTahxUTNtsEigMJGjKhYTKlmow0DjLyxUt7wHGzUmCxAqGyTyd6Yk5Jlc2Jsls2Na04K/aRm2degkpYrqG+cGGdIlYO4
xa210ARscZygiwHLGtMAsd5sNlutRhDOQOPGmcZa7PVGs8VosQBfowXYYKgFa/Qa7DOIbuPEFNM4+5m0sr3R3oj5ZvsMI36N1GQENYgIFgwdJ8wghZlIYY8xRN3M2cOa1C0N07k4TqSbkrJsYSwM8GbaTRiNqbIJC2BrNlOyRC06LjkN98xMgtEbA2o1pURHAFmwGcVZRvssExhObamggHmcsIpk+2rwpdE2uMw22GrDNAI/z2hUd
0mJeWbA3WJEnQR0UvaERJvZAhFidOaN1cDYN2GqvQ4UIvEwgnZnmKZbbQNWoz1ynj1yoT1yqT1yBf9Gq9fIX+Ky2VbBzJbAuGirsEeuxwSz3SMLViClSrYBs4Y9hi1k1G0DLKqR81i81ki5XUO7sFq5yWnJNTKYyKU4hjggXL+G6iaFQ7oOCZPCguZGroesTIK0mq2AO44EINcIJmWOM5hpmG3AvnCCyZRli/ycy/aFRmbKPEJ5YX
ouEe0mllcLl2gMtdJ42arNlDIwL83EAGwD2JUsMMrpODQWYEC6IM2UZI9cbo9cYhswMcaRbWNMZntkH4m9FdIthBVH2WqdRIgbcURwISg4osxDq/EEMHcYX6FUrGNNGei2WsFGo9lqTsJcOmNQWKl0unMmpUHMGuUptWUqqY4pIULVYgZ+jbYBUj8GQ3qmaQxBs+DPFrkTegOqAIUME52yRqsxHYAGskw2q32T0ZxkNPLhgsowA+d
cI6byVqyyYj3RNMYeedOSPdYWeR3wXrcN4DjTJTUbi481ZCelgiqC2nAnQr1JmiqVJ1nQSsoNZdpG5E1b5BVLdooJFHxzjByDFgzLJHLKXguA2wZAR2v2GJOcmw2dYDWLZEM2oWoBKc05pJUzoHy0WUarrCmA1gkM0ZIt5ZWxN8qymZG0DVjUeSbEaUNZpgx7ZAfYaY/sNNPFSDSBTNoGN7ECngRJNKBiqyVlarab0jBqh3487/vh
HJDNaEymIgQIV9KZOVabKR3a2mxDJ4SKxsAkQE1cAUZDUqxjwN0oY8GDSViRyAClnszz7N0p0Pr2wjRTKlCzrwZVMJVsFtqN1IvFdtExzDZaTCkoZ4OtAJFtxiUlm7DO1jrM1GaGBTKSTYFwWCysrqGRvdNAu0ack7+qA+pVtxyp/7xU0p1frzx1f+LzNYZLug4CIzt0AFO1G8PLMKXZ6y1mi9VClivdRGpwj8HusrtMTA67y8Ir7
IE2MKm+cUodejWUjHZXhtZmRtVo12rG6BCiE4ydic3M6Sap2VwJdhqdodaX+LogkBacK6ZSyEoHkweG7CE2oRgSklsKpZqSzDCCY5XJwAgj74csRYj2mBRtp3NmtZ5kStWwiY5Xi4/FonSapRKwb4wtvNG+UVt4o1x4YwaMmeoyqvU2xtaj1mxFF1e0Ra2TTruTMkCUsjfi0KZgF1B3ON6QG7loZBs1wFFStUy1omzHn5kWpTkZal
XZA5cFWgMeD+R6nmm6vQbKuw6KOHI52S6rUisWOk+XQJrthaCKfRb9otc+S3IJZaNJipjVpJogCvZuq25PIDSZTJckiWuyCcezm/p1g8j/kUOZGlbmk3WmaQIUBChtTVPUbiS8InfCZA0YCQxZWTIF5ESa4USSyk1JhoYdGI9T0y0XMBo14EbjiaYMqV9oMpowu87KejHJ3g0/jQ7t29jS4J2YIP0WFMcJ7nj3BFP6kNlG1mDAbFN
OyhhSqs/bI/sJVfL4Is+TMbYN7pS3B9jucq85N4lvZtapB6SfS5weSwrhgD1yECAjhzQv9GGGdogMIAZZ1ZjDPIY8PZ7LoN5BGzTyENfFQkr2UHTQewq9904yQV2Rs6v/we4Inol1ik0T9NgP2T+T6mOLZ55mGs9EIaqkpaWl4wXSwLC1QcVG7iRT3QbVBiaaIQm2tjLTVI2INJYYimlG2zorwbat41WiAEjXQgZtbTR3HeTWYiwi
AFZtTaYJc0Mihxp6VTcUdjpLOoqZFtzSCQvo3knm+85qWzFh9ivnme9esPYc2/Npc5MpxqFvtxDJ9En2yfSfxcnUmEwfiZ+cShf6jPxkMy6R7fmGyOZRPn4if5QP9puVq30S76xc9bFS84vzC+lnVm512Euf/TLf5w6HAk7vrNzmcLvXQ/+Ezv9rPb+9vNxZ2lFaVjSnZLa7sGJOlqHFmEmfCMT/Bq4+KMkAIUg1wx3AH5mmdGMqT
JzRpGILY6pFqbgZSan21RhXoerzLKmaZ2dS/iV6V41J1ZkYNTSk7huTU22RzeZU5Y1R7Sgug8lU+oAun1BVkBF+jsBLR5s6XqTLK0Chm75olgwoAhjyteTNgHDEBCUFTwlVA/HXRHFfCtlkqq420SAYX0y3kLuHUIttsDBAdZIm4NDUPoMOUg7dECuQN2WAJqOwjmIu8hDNFI3w/uEe2Os4iB2g0QvN5jG5qQZzOnvc3M0eN6STxN
+QyVbbmmkeI1It2RC3nJRM9sEs2bhnUiPu1kxsM9OSmT1WmLhBniWrySKS5ECrRSTLoVYbTQJtUKErZmWIVAP1ZVuplq5GUhl7tljSNCDQRlS0SgxYVxE9gLBgzwq0tNAKhDi71qT6QG20pQmD5LZEnu5ERJCCxprpm2kZFPiBM4eoFiDthdABODGoUfybxIU0Ycq2WuAEWrJpSGSX1SrII9tlyTZnmzPNhLKZojO7y2qVNwvzyBW
NE2EsmDVWebMwoyykDekuWy0WDnEsmKTmWGNFCbCR1vfa63k61BVVQ/Z6nsfob6QKBtazZ7iNsFFJB8leEgLaL672OrPcHxOMChnCJOu2CrM5nYW12ypvFrMwSgaDvarE8soNrGRtLN6gO0W9kKoZAjI8Q1jxZ+FvraXXZAN/zc74lQGnf6nuI85augN9/UEDxplIW4mxBpGm+xxjkWYQKfzxR0KMwZgiqVlke5Es8mvB4+MOCUNj
M2k7P/5uLDOIG7MN0e/woBJ9icdp+MssN4jMCbE+emWK+NdyR43DfOeHV7uOvN6w+X9W3H3y7QuP0ozquW2tQai5tkpXr8dHH/1An6TTVuMO9oT6/G0K77xeJ5RpoC22k7a+9jPaeCNtPneopFTXle93tWtfwqCWvK5GLYltuX/d+cQHget2P/bKXa8/vrY8hvYAlXNFwldPuX57a6v7AjVeb6PT45Ofm+6Wn77Iry+nA0gmfYvnI
1d+mtxy4oK7XjM3v3Xyg45H/3nG2X9Kydk54eWrXz2zUTgPX5/0edGnU/LXrX4iuPvN3xw8fc4fS63dZ93eNGOaPfu12zcP+s59d8F+z3++/ODaJ4tb7ln+7e/saXP/9jurM7JuKH+78Lq/TJyTMbV45s0Hntjl+Wdggbh68ic/HahZMz1y9ocHN3ZPvz2j6+pDq69N3jWtpO7zGc+sf9mw4h9vP3rSzSfPeHLHrxsKT+j7r3zDt5
Jfe/i2yoI/HXH8zl/33j2/+e9/jD0ra8+tx6btfv+gcfuNSx/+8L8doYtCN9308COdjwUvPuW2bxW8tv+DGfs/+dlPkrbPvIN2ayIBuYX4W1kskkkuDGLsI/33H2gpO9D13Imdj43bs2Dy+DHjS+/onT972TsLVp7wm/vMh/efFbl37bVzv9hePtcR6Lps3R+O7Lxo8tPXX/fsJYcOfPD39//mvnfXw56D66/YX37/D56cf/XR5ra
rf/XaxobT/vDMUxtSl3VPe8P/ycZflT1SufLVP+TdNXXHvVmDE07tybz38J7aqf3XfXTwwG82XJ9T7Pzt6X//0eemUzInNFl6ky557geFWx5f9cM1v7rB9ZPkcy3WSZ2/uOLSZfe889Nw8tbmX/4lN7X2gbOrHD/dM/PokQcWjw97Urae/ueW66bmNV9kf+nZnrcvu2nH4SWP9vy04olxn224ad7khyqKHhpzg/+kIrH3ez/ffMp5
kQ+3/b4o+0VHyprPBl88+NQttz9oemFGk8u6+drUl3Zv6Cw4cfovrrvm6G83Gar2lj464aMFufuvvnbNgTmPDIr0l/pOePKHn/zu1F/k7Bm/zbW1rLa8+QXvW1t2Vs/c1ldw7EL7+YH7vvfnzt/n52yquvWDY6euadnen3PV79//Yt29J2978rRrXt69Y+8fW25tfqDlw5eOHRy8+ZHBG+q+LLj/lntP3LfrgTVT59/8zqQrO/9ny
uKn2z/7266t33/s0H5zxcmfTX34n9teePWU6VPeS8/7VfIjt54TvmD/VQefLH3gaJ+h2/Zsd/Ezuzw/e/razNc9tz198Ni3TNt3lW/uPvT4HdPf3rQpdMae5xv3Htz0UuGSN9b89dLVH0W++OO8A5efk3X9kQLRvveFB+7df+Gbe+ddWbtmcvPnt1c/u7h/8HDX68derhr48213rqn78L7QlfZpqf6q7rNqjt5YdE73kzefsOZnT1
dNu2PxR/cc7X1vJLmaufXBBcsvWbnPfmpPxT3f/rTL3HTg/A9fs93vnFtStcyd8qPJovKlxw/UrFsx/4Q591W7D398+s/f/Zm7+/Dr57cl5ZUdm9GwZ978XZeEP/UZX1l11RlPRoxVC7xZWxr/Y9oZV2yvWL664oxr3t35V8cPzRt3Lnv24p9l3PjZhVvnHV09dV/+/qvOX7hux97T03zrdjb/Zd6Ola/f9+L3Gg+2vXJ5ww9mfPl
Z5IxxjuV/fz/5suqKBybu39Jy9glPnDf+x0vOvclsvGZa3YHwdbt3PXX33on7Ps+7LX/xbdlLPprpqSksefC2KU9duX3hwep3X8lIK/71/9z0hx9c+8Q5H16/759j9198ZzhNPD+9+uNfLTvnvpfuu/Pzp/7j4OCXB27uP/bWaVMyPzu3/IMf/uXVm1btvivnpMEi3wfnd8x+P2Xswb9kvXjLjLO2v9W+b98FW/aatl5S8PGkFVsK
jhSXm+64+42dxgmld/39uZuvK4v88cVzza/8bu281bcvPTVp5r3tqypXzy2vLn3thtmv3pR8lf36C+78+PMLbrr58OtH9j9+6GXro9995azJmc2rOpYdfO7Yyru3733hgnc2nfvLgumr0la9ccsHK5fcMtH9wHe3LnrrgrE/rbvk0xvWe5IC/W/vqmrY+vf0ec+Fjhya/Upx7d2f3PH8qVP3/tfVLRe7tuWefsJr5z7/rSUXLy3NP
feHE499NmvA6+u8/KG0tx7c73ceXrzz3KPZ8zrnWvKnOENP/vmjs5aX5/zywg7P5oue8K8+kHfp5I93rHjnrNTrv1+SdaDomTfGm679+eWpm3Yd/tvuu349OW9b6m0d9z+9+2bf5nsvPLT4jXEdF+0557nBmopHSa5OZR09KbGWl5ZNfd9dsmjHNfaP+vIxdzG/lSiP/7WviN8cVirkP/bLESXcR/cSfpuYfFt3ftzDcppTzI/LS7
DCSxOMT08pvWrpjy++37Tjsp07r6p6e+76zc8bitG3AX/rYGIfm3z7+QfG3NF6xlN3/fKctQ8fJvxSRcuzC83v/zXpyO6srdufzN/y+RsfBTs/f+Ghs3f89m+ftlXeeOxg6LGHLj30Uu9c2/NHu3939rn3nLJny4O1j7536mc//6PT7/H4xqavu2/+m+8tTnd/cVvh5I9ueWbgsVUXDn5x2z8c73VteHfsuot3jy89+fK6P4+96J6
cj78zo6q1x/Tam8ue/+zkMT9yZyw4cOG1E//07P1z337PNmH6x5u/25C2s+jy8vVP/eOO//S8fMufTvZO+7Ln6Asb9j12ceihU1PE1dceevXOjJVXRDovqg5t/cmUD+6Zlbt233UNK+5dWdPefeHtC23Xb263Vv84591J9ftWHGl41vVgxpGtO2dtez/7y7kXfHjrhrb217Y3/KYoLzVy2W/zL7t1xZWjMPH/8ZeB/a9shKJD20m2
CxO006sOf6sWGsRzui9re85I37m2QjjEWvVmNYd6m8ta/pekRSjT6+HkI8ckHEMczAWqRrGy/jvg6FXDo1bwW40WqYfh0QfBeJ3Cs1rUP00E4x44y9fdybONBIPe0BxQDzCHQ8rkMYXRH3obJ/m5Zfyth9oby2mNAexIvgGRXvRW2HZ+y5R8PNyl2r/D87R1RvjslVHmF9LDxuj8If9hhpd8O4v2R+vRtzDq/6WLHkPHME20Dr0Zg
x7T0msGKE/fukz/7kUzacd+7JUw7hL0SU3S713E6zSpdo9aR8PT95XXk3SNfxvAV6FrIUXuQ+YNpU6Rji4VTMdKfizt5s/nkW8+HHmOnPd/5avQIOgLGS8o/3cj8v9f/47X/wJFtkDlACgBAA==
#>
## END ##