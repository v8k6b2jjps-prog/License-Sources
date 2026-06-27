# Sync mode type
enum SyncSource {
    U8 = 8
    U16 = 16
    U32 = 32
    U64 = 64
}

# Define the wrapping value and mask
$crc32_table = (
    0x0,
    0x04c11db7, 0x09823b6e, 0x0d4326d9, 0x130476dc, 0x17c56b6b,
    0x1a864db2, 0x1e475005, 0x2608edb8, 0x22c9f00f, 0x2f8ad6d6,
    0x2b4bcb61, 0x350c9b64, 0x31cd86d3, 0x3c8ea00a, 0x384fbdbd,
    0x4c11db70, 0x48d0c6c7, 0x4593e01e, 0x4152fda9, 0x5f15adac,
    0x5bd4b01b, 0x569796c2, 0x52568b75, 0x6a1936c8, 0x6ed82b7f,
    0x639b0da6, 0x675a1011, 0x791d4014, 0x7ddc5da3, 0x709f7b7a,
    0x745e66cd, 0x9823b6e0, 0x9ce2ab57, 0x91a18d8e, 0x95609039,
    0x8b27c03c, 0x8fe6dd8b, 0x82a5fb52, 0x8664e6e5, 0xbe2b5b58,
    0xbaea46ef, 0xb7a96036, 0xb3687d81, 0xad2f2d84, 0xa9ee3033,
    0xa4ad16ea, 0xa06c0b5d, 0xd4326d90, 0xd0f37027, 0xddb056fe,
    0xd9714b49, 0xc7361b4c, 0xc3f706fb, 0xceb42022, 0xca753d95,
    0xf23a8028, 0xf6fb9d9f, 0xfbb8bb46, 0xff79a6f1, 0xe13ef6f4,
    0xe5ffeb43, 0xe8bccd9a, 0xec7dd02d, 0x34867077, 0x30476dc0,
    0x3d044b19, 0x39c556ae, 0x278206ab, 0x23431b1c, 0x2e003dc5,
    0x2ac12072, 0x128e9dcf, 0x164f8078, 0x1b0ca6a1, 0x1fcdbb16,
    0x018aeb13, 0x054bf6a4, 0x0808d07d, 0x0cc9cdca, 0x7897ab07,
    0x7c56b6b0, 0x71159069, 0x75d48dde, 0x6b93dddb, 0x6f52c06c,
    0x6211e6b5, 0x66d0fb02, 0x5e9f46bf, 0x5a5e5b08, 0x571d7dd1,
    0x53dc6066, 0x4d9b3063, 0x495a2dd4, 0x44190b0d, 0x40d816ba,
    0xaca5c697, 0xa864db20, 0xa527fdf9, 0xa1e6e04e, 0xbfa1b04b,
    0xbb60adfc, 0xb6238b25, 0xb2e29692, 0x8aad2b2f, 0x8e6c3698,
    0x832f1041, 0x87ee0df6, 0x99a95df3, 0x9d684044, 0x902b669d,
    0x94ea7b2a, 0xe0b41de7, 0xe4750050, 0xe9362689, 0xedf73b3e,
    0xf3b06b3b, 0xf771768c, 0xfa325055, 0xfef34de2, 0xc6bcf05f,
    0xc27dede8, 0xcf3ecb31, 0xcbffd686, 0xd5b88683, 0xd1799b34,
    0xdc3abded, 0xd8fba05a, 0x690ce0ee, 0x6dcdfd59, 0x608edb80,
    0x644fc637, 0x7a089632, 0x7ec98b85, 0x738aad5c, 0x774bb0eb,
    0x4f040d56, 0x4bc510e1, 0x46863638, 0x42472b8f, 0x5c007b8a,
    0x58c1663d, 0x558240e4, 0x51435d53, 0x251d3b9e, 0x21dc2629,
    0x2c9f00f0, 0x285e1d47, 0x36194d42, 0x32d850f5, 0x3f9b762c,
    0x3b5a6b9b, 0x0315d626, 0x07d4cb91, 0x0a97ed48, 0x0e56f0ff,
    0x1011a0fa, 0x14d0bd4d, 0x19939b94, 0x1d528623, 0xf12f560e,
    0xf5ee4bb9, 0xf8ad6d60, 0xfc6c70d7, 0xe22b20d2, 0xe6ea3d65,
    0xeba91bbc, 0xef68060b, 0xd727bbb6, 0xd3e6a601, 0xdea580d8,
    0xda649d6f, 0xc423cd6a, 0xc0e2d0dd, 0xcda1f604, 0xc960ebb3,
    0xbd3e8d7e, 0xb9ff90c9, 0xb4bcb610, 0xb07daba7, 0xae3afba2,
    0xaafbe615, 0xa7b8c0cc, 0xa379dd7b, 0x9b3660c6, 0x9ff77d71,
    0x92b45ba8, 0x9675461f, 0x8832161a, 0x8cf30bad, 0x81b02d74,
    0x857130c3, 0x5d8a9099, 0x594b8d2e, 0x5408abf7, 0x50c9b640,
    0x4e8ee645, 0x4a4ffbf2, 0x470cdd2b, 0x43cdc09c, 0x7b827d21,
    0x7f436096, 0x7200464f, 0x76c15bf8, 0x68860bfd, 0x6c47164a,
    0x61043093, 0x65c52d24, 0x119b4be9, 0x155a565e, 0x18197087,
    0x1cd86d30, 0x029f3d35, 0x065e2082, 0x0b1d065b, 0x0fdc1bec,
    0x3793a651, 0x3352bbe6, 0x3e119d3f, 0x3ad08088, 0x2497d08d,
    0x2056cd3a, 0x2d15ebe3, 0x29d4f654, 0xc5a92679, 0xc1683bce,
    0xcc2b1d17, 0xc8ea00a0, 0xd6ad50a5, 0xd26c4d12, 0xdf2f6bcb,
    0xdbee767c, 0xe3a1cbc1, 0xe760d676, 0xea23f0af, 0xeee2ed18,
    0xf0a5bd1d, 0xf464a0aa, 0xf9278673, 0xfde69bc4, 0x89b8fd09,
    0x8d79e0be, 0x803ac667, 0x84fbdbd0, 0x9abc8bd5, 0x9e7d9662,
    0x933eb0bb, 0x97ffad0c, 0xafb010b1, 0xab710d06, 0xa6322bdf,
    0xa2f33668, 0xbcb4666d, 0xb8757bda, 0xb5365d03, 0xb1f740b4
);

# Convert values to UInt32
$g_hash_table = $crc32_table | % {
    $value = $_
    if ($value -lt 0) {
        $value += 0x100000000
    }
    [uint32]($value -band 0xFFFFFFFF)
}

# Define a structure for UINT32u
class UINT32u {
    [UInt32]   $u32
    [UInt16[]] $u16 = @(0, 0)
    [Byte[]]   $u8  = @(0, 0, 0, 0)

    [void] Sync([SyncSource]$source) {
        switch ($source.value__) {
            8 {
                if ($this.u8.Length -lt 4) { throw "u8 array must have at least 4 bytes." }
                $this.u16 = 0..1 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = [BitConverter]::ToUInt32($this.u8, 0)
            }
            16 {
                $this.u8 = $this.u16 | % { [BitConverter]::GetBytes($_) } | % { $_ }
                $this.u32 = [BitConverter]::ToUInt32($this.u8, 0)
            }
            32 {
                $this.u8 = [BitConverter]::GetBytes($this.u32)
                $this.u16 = 0..1 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
            }
            default {
                throw "Unsupported sync source. [UINT32u]"
            }
        }
    }
}
 
# Define a structure for UINT64u
class UINT64u {
    [UInt64]   $u64
    [UInt32[]] $u32 = @(0, 0)
    [UInt16[]] $u16 = @(0, 0, 0, 0)
    [Byte[]]   $u8  = @(0, 0, 0, 0, 0, 0, 0, 0)

    [void] Sync([SyncSource]$source) {
        switch ($source.value__) {
            8 {
                $this.u16 = 0..3 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = 0..1 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                $this.u64 = [BitConverter]::ToUInt64($this.u8, 0)
            }
            16 {
                $this.u8 = $this.u16 | % { [BitConverter]::GetBytes($_) } | % { $_ }
                $this.u32 = 0..1 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                $this.u64 = [BitConverter]::ToUInt64($this.u8, 0)
            }
            32 {
                $this.u8 = $this.u32 | % { [BitConverter]::GetBytes($_) } | % { $_ }
                $this.u16 = 0..3 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u64 = [BitConverter]::ToUInt64($this.u8, 0)
            }
            64 {
                $this.u8 = [BitConverter]::GetBytes($this.u64)
                $this.u16 = 0..3 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = 0..1 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
            }
            default {
                throw "Unsupported sync source. [UINT64u]"
            }
        }
    }
}
 
# Define a structure for UINT128u
class UINT128u {
    [UInt64[]] $u64 = @(0, 0)
    [UInt32[]] $u32 = @(0, 0, 0, 0)
    [UInt16[]] $u16 = @(0, 0, 0, 0, 0, 0, 0, 0)
    [Byte[]]   $u8  = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    [void] Sync([SyncSource]$source) {
        switch ($source.value__) {
            8 {
                $this.u32 = @(0..3 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) })
                $this.u16 = @(0..7 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) })
                $this.u64 = @(0..1 | % { [BitConverter]::ToUInt64($this.u8, $_ * 8) })
            }
            16 {
                $this.u8 = $this.u16 | % { [BitConverter]::GetBytes($_) } | % { $_ }
                $this.u32 = @(0..3 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) })
                $this.u64 = @(0..1 | % { [BitConverter]::ToUInt64($this.u8, $_ * 8) })
            }
            32 {
                $this.u8 = $this.u32 | % { [BitConverter]::GetBytes($_) } | % { $_ }
                $this.u16 = @(0..7 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) })
                $this.u64 = @(0..1 | % { [BitConverter]::ToUInt64($this.u8, $_ * 8) })
            }
            64 {
                $this.u8 = @([BitConverter]::GetBytes($this.u64[0]) + [BitConverter]::GetBytes($this.u64[1]))
                $this.u16 = @(0..7 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) })
                $this.u32 = @(0..3 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) })
            }
            default {
                throw "Unsupported sync source. [UINT128u]"
            }
        }
    }
}

function Hash([UINT128u]$key) {
    $hash = -1
    for ($i = 0; $i -lt 16; $i++) {
        $index = (($hash -shr 24) -bxor $key.u8[$i]) -band 0xff
        $hash  = (($hash -shl 8) -bxor $crc32_table[$index]) -band 0xFFFFFFFF
    }
    return (-bnot $hash) -band 0x3ff
}
function SetHash {
    param (
        [UINT128u]$key3,
        [ref]$key2,
        [ref]$check
    )

    # Copy $key3 to $key2
    $key2.Value = [UINT128u]::new()
    [Array]::Copy($key3.u8, $key2.Value.u8, 16)

    # Compute the hash and set it in $check
    $check.Value.u32 = [UINT32](Hash($key2.Value))
    $check.Value.Sync([SyncSource]::U32)

    # Update $key2 with values from $check
    $key2.Value.u8[12] = [Byte]($key2.Value.u8[12] -bor ($check.Value.u8[0] -shl 7))
    $key2.Value.u8[13] = [Byte](($check.Value.u8[0] -shr 1) -bor ($check.Value.u8[1] -shl 7))
    $key2.Value.u8[14] = [Byte]($key2.Value.u8[14] -bor (($check.Value.u8[1] -shr 1) -band 0x1))

    # Sync $key2 to ensure all values are updated correctly
    $key2.Value.Sync([SyncSource]::U8)
}
function SetInfo {
    param (
        [UINT32u]$groupid,
        [UINT32u]$keyid,
        [UINT64u]$secret,
        [ref]$key3
    )

    # Initialize the 64-bit fields of key3
    $key3.Value.u64[0] = [UINT64]0
    $key3.Value.u64[1] = [UINT64]0

    # Sync the key3 object to ensure it is up-to-date
    $key3.Value.Sync([SyncSource]::U64)

    # Set bytes using groupid
    $key3.Value.u8[0] = [BYTE]($groupid.u8[0])
    $key3.Value.u8[1] = [BYTE]($groupid.u8[1])
    $key3.Value.u8[2] = [BYTE]($key3.Value.u8[2] -bor ($groupid.u8[2] -band 0x0F))

    # Set bytes using keyid
    $key3.Value.u8[2] = [BYTE]($key3.Value.u8[2] -bor ($keyid.u8[0] -shl 4))
    $key3.Value.u8[3] = [BYTE]((($keyid.u8[1] -shl 4) -bor ($keyid.u8[0] -shr 4)) -band 0xFF)
    $key3.Value.u8[4] = [BYTE]((($keyid.u8[2] -shl 4) -bor ($keyid.u8[1] -shr 4)) -band 0xFF)
    $key3.Value.u8[5] = [BYTE]((($keyid.u8[3] -shl 4) -bor ($keyid.u8[2] -shr 4)) -band 0xFF)
    $key3.Value.u8[6] = [BYTE]($key3.Value.u8[6] -bor (($keyid.u8[3] -shr 4) -band 0x03))

    # Set bytes using secret
    $key3.Value.u8[6] = [BYTE]($key3.Value.u8[6] -bor ($secret.u8[0] -shl 2))
    $key3.Value.u8[7] = [BYTE](($secret.u8[1] -shl 2) -bor ($secret.u8[0] -shr 6))
    $key3.Value.u8[8] = [BYTE](($secret.u8[2] -shl 2) -bor ($secret.u8[1] -shr 6))
    $key3.Value.u8[9] = [BYTE](($secret.u8[3] -shl 2) -bor ($secret.u8[2] -shr 6))
    $key3.Value.u8[10] = [BYTE](($secret.u8[4] -shl 2) -bor ($secret.u8[3] -shr 6))
    $key3.Value.u8[11] = [BYTE](($secret.u8[5] -shl 2) -bor ($secret.u8[4] -shr 6))
    $key3.Value.u8[12] = [BYTE](($key3.Value.u8[12] -bor (($secret.u8[6] -shl 2) -bor ($secret.u8[5] -shr 6))) -band 0x7F)

    # Sync the key3 object to finalize changes
    $key3.Value.Sync([SyncSource]::U8)
}
function Encode {
    param (
        [UINT128u]$key2,
        [ref]$key1
    )

    # Initialize res and rem objects
    $res = [UINT64u]::new()
    $rem = [UINT32u]::new()

    # Initialize a copy of key2
    $cur = [UINT128u]::new()
    [Array]::Copy($key2.u8, $cur.u8, 16)
    $cur.Sync([SyncSource]::U8)

    $i = 25
    do {
        # Set res.u64 from cur.u32[3]
        $res.u64 = [UINT64]($cur.u32[3])
        $cur.u32[3] = [math]::floor($res.u64 / 24)
        $rem.u32 = [UInt32]($res.u64 % 24)

        # Sync res from u64
        $res.Sync([SyncSource]::U64)

        # Update cur.u32[2] and sync res from u32
        $res.u32[0] = [UInt32]($cur.u32[2])
        $res.u32[1] = [UInt32]($rem.u32)
        $res.Sync([SyncSource]::U32)
        $cur.u32[2] = [math]::floor($res.u64 / 24)
        $rem.u32 = [UInt32]($res.u64 % 24)

        # Update cur.u32[1] and sync res from u32
        $res.u32[0] = [UInt32]($cur.u32[1])
        $res.u32[1] = [UInt32]($rem.u32)
        $res.Sync([SyncSource]::U32)
        $cur.u32[1] = [math]::floor($res.u64 / 24)
        $rem.u32 = [UInt32]($res.u64 % 24)

        # Update cur.u32[0] and sync res from u32
        $res.u32[0] = [UInt32]($cur.u32[0])
        $res.u32[1] = [UInt32]($rem.u32)
        $res.Sync([SyncSource]::U32)
        $cur.u32[0] = [math]::floor($res.u64 / 24)
        $rem.u32 = [UInt32]($res.u64 % 24)
        $rem.Sync([SyncSource]::U32)

        $key1.Value[--$i] = [Byte]($rem.u8[0])

    } while ($i -gt 0)
}
function UnconvertChars([byte[]]$key1, [ref]$key0) {
    $n = $key1[0]
    $n += [math]::Floor($n / 5)

    $j = 1
    for ($i = 0; $i -lt 29; $i++) {
        if ($i -eq $n) {
            $key0.Value[$i] = 'N'
        }
        elseif ($i -eq 5 -or $i -eq 11 -or $i -eq 17 -or $i -eq 23) {
            $key0.Value[$i] = '-'
        }
        else {
            switch ($key1[$j++]) {
                0x00 { $key0.Value[$i] = 'B' }
                0x01 { $key0.Value[$i] = 'C' }
                0x02 { $key0.Value[$i] = 'D' }
                0x03 { $key0.Value[$i] = 'F' }
                0x04 { $key0.Value[$i] = 'G' }
                0x05 { $key0.Value[$i] = 'H' }
                0x06 { $key0.Value[$i] = 'J' }
                0x07 { $key0.Value[$i] = 'K' }
                0x08 { $key0.Value[$i] = 'M' }
                0x09 { $key0.Value[$i] = 'P' }
                0x0A { $key0.Value[$i] = 'Q' }
                0x0B { $key0.Value[$i] = 'R' }
                0x0C { $key0.Value[$i] = 'T' }
                0x0D { $key0.Value[$i] = 'V' }
                0x0E { $key0.Value[$i] = 'W' }
                0x0F { $key0.Value[$i] = 'X' }
                0x10 { $key0.Value[$i] = 'Y' }
                0x11 { $key0.Value[$i] = '2' }
                0x12 { $key0.Value[$i] = '3' }
                0x13 { $key0.Value[$i] = '4' }
                0x14 { $key0.Value[$i] = '6' }
                0x15 { $key0.Value[$i] = '7' }
                0x16 { $key0.Value[$i] = '8' }
                0x17 { $key0.Value[$i] = '9' }
                default { $key0.Value[$i] = '?' }
            }
        }
    }
}
function KeyEncode {
    param (
        [string]$sgroupid,
        [UInt32]$skeyid,
        [UInt64]$sunk
    )
   
    # Step 1: Convert hexadecimal strings to numeric values
    $sgroupid_f = [Convert]::ToUInt32($sgroupid, 16)

    # Step 2: Validate ranges
    if ($sgroupid_f -gt 0xffffff) {
        Write-Host "GroupId must be in the range 0-ffffff"
        return -1
    }
    if ($skeyid -gt 0x3fffffff) {
        Write-Host "KeyId must be in the range 0-3fffffff"
        return -1
    }
    if ($sunk -gt 0x1fffffffffffff) {
        Write-Host "Secret must be in the range 0-1fffffffffffff"
        return -1
    }

    # Convert to byte arrays
    $groupid     = [UINT32u]::new()
    $groupid.u8  = [BitConverter]::GetBytes($sgroupid_f)
    $groupid.Sync([SyncSource]::U8)

    $keyid     = [UINT32u]::new()
    $keyid.u8  = [BitConverter]::GetBytes($skeyid)
    $keyid.Sync([SyncSource]::U8)

    $secret     = [UINT64u]::new()
    $secret.u8  = [BitConverter]::GetBytes($sunk)
    $secret.Sync([SyncSource]::U8)

    $key3 = [UINT128u]::new()
    SetInfo -groupid $groupid -keyid $keyid -secret $secret -key3 ([ref]$key3)

    $key2 = [UINT128u]::new()
    $check = [UINT32u]::new()
    SetHash -key3 $key3 -key2 ([ref]$key2) -check ([ref]$check)

    $key1 = New-Object Byte[] 25
    Encode -key2 $key2 -key1 ([ref]$key1)

    $key0 = New-Object Char[] 30
    UnconvertChars -key1 $key1 -key0 ([ref]$key0)
   
    # Show result
    return (-join $key0)
}

cls
Write-Host
$info = KeyInfo 128a 0 0
"KeyInfo Results: $($info)"

$info = KeyEncode 128a 0 0
"Powersh Results: $($info)"