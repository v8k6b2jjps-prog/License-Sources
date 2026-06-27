
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

# Sppobjs.dll, 7600
__int64 __fastcall CConfigCacheT<CEmptyType>::ParseUniqueIdToken(
        unsigned __int16 *a1,
        UUID *Uuid,
        __int64 a3,
        _DWORD *a4)
{
  unsigned int v4; // edi
  wchar_t *v9; // rax
  wchar_t *v10; // r11
  bool v11; // cf
  unsigned __int64 v12; // rdx
  unsigned __int16 v13; // dx
  int v14; // eax
  _BYTE *v15; // r13
  wchar_t *v16; // rax
  wchar_t *v17; // rbp
  unsigned __int64 v18; // rbx
  unsigned __int64 v19; // rbx
  unsigned __int64 v20; // rbp
  unsigned __int16 *v21; // rbx
  unsigned __int64 v23; // [rsp+20h] [rbp-278h] BYREF
  unsigned __int16 StringUuid[264]; // [rsp+30h] [rbp-268h] BYREF

  v4 = 0;
  if ( !a1 )
    DebugBreak();
  if ( !Uuid )
    DebugBreak();
  if ( (int)StringCchLengthW(a1, 0x7FFFFFFFui64, &v23) < 0 )
    return (unsigned int)-2147217375;
  v9 = wcschr(a1, 0x3Au);
  v10 = v9;
  if ( !v9 )
  {
    if ( !UuidFromStringW(a1, Uuid) )
    {
      if ( a4 )
        *a4 = 0;
      return v4;
    }
    return (unsigned int)-2147217375;
  }
  if ( (((char *)v9 - (char *)a1) & 0xFFFFFFFFFFFFFFFEui64) != 16 )
    return (unsigned int)-2147217375;
  v11 = *(_QWORD *)L"msft2005:" < *(_QWORD *)a1;
  if ( *(_QWORD *)L"msft2005:" == *(_QWORD *)a1
    && (v12 = *(_QWORD *)L"2005:", v11 = v12 < *((_QWORD *)a1 + 1), v12 == *((_QWORD *)a1 + 1))
    && (v13 = aMsft2005[8], v11 = v13 < a1[8], v13 == a1[8]) )
  {
    v14 = 0;
  }
  else
  {
    v14 = -v11 - (v11 - 1);
  }
  if ( v14 )
    return (unsigned int)-2147217375;
  v15 = v10 + 1;
  v16 = wcschr(v10 + 1, 0x26u);
  v17 = v16;
  if ( !v16 )
    return (unsigned int)-2147217375;
  v18 = ((char *)v16 - v15) >> 1;
  if ( v18 >= 0x103 )
    return (unsigned int)-2147217375;
  v19 = v18;
  memcpy(StringUuid, v15, v19 * 2);
  StringUuid[v19] = 0;
  if ( UuidFromStringW(StringUuid, Uuid) )
    return (unsigned int)-2147217375;
  v20 = (unsigned __int64)(v17 + 1);
  v21 = &a1[v23];
  if ( (unsigned __int64)v21 <= v20 )
    return (unsigned int)-2147217375;
  if ( a3 )
  {
    if ( !a4 )
      DebugBreak();
    if ( v20 )
      return (unsigned int)CStringConvertT<unsigned long>::Base64Decode(
                             v20,
                             (unsigned int)((__int64)((__int64)v21 - v20) >> 1),
                             a3,
                             a4);
    else
      return (unsigned int)-2147024809;
  }
  return v4;
}
__int64 __fastcall CConfigCacheT<CEmptyType>::PhoneGetPkeyAuthBits(
        __int64 a1,
        unsigned __int16 *a2,
        unsigned __int64 *a3,
        _DWORD *a4)
{
  int v8; // edi
  __int64 v9; // rbx
  __int64 v10; // rbp
  __int64 v11; // rsi
  int v13; // [rsp+20h] [rbp-68h] BYREF
  UUID Uuid; // [rsp+28h] [rbp-60h] BYREF
  __int64 v15; // [rsp+38h] [rbp-50h]

  if ( !a2 )
    DebugBreak();
  if ( !a3 )
    DebugBreak();
  if ( !a4 )
    DebugBreak();
  v13 = 12;
  v8 = CConfigCacheT<CEmptyType>::ParseUniqueIdToken(a2, &Uuid);
  if ( v8 >= 0 )
  {
    v9 = a1 + 8;
    if ( a1 != -8 && !(unsigned int)CRWLock2T<CEmptyType>::AcquireSharedEx(a1 + 8, 1i64) )
      DebugBreak();
    v10 = a1 + 112;
    if ( (unsigned __int8)CSortedArray<DP_COM<CConfigurationInfo>,_GUID,CAdaptorDefault,CPoliciesDefaultSpecialize>::Find(
                            a1 + 112,
                            &Uuid,
                            &v13) )
    {
      v11 = v13;
      if ( v13 < 0 || v13 >= *(_DWORD *)(v10 + 4) )
        DebugBreak();
      *a3 = v15 & 0x1FFFFFFFFFFi64 | ((unsigned __int64)(*(_DWORD *)(*(_QWORD *)(*(_QWORD *)(v10 + 8) + 8 * v11) + 20i64) & 0x3FF) << 41);
      *a4 = 51;
    }
    else
    {
      v8 = -2147217389;
    }
    if ( v9 )
      CRWLock2T<CEmptyType>::ReleaseLockEx(v9);
  }
  return (unsigned int)v8;
}

# Sppobjs.dll, 7850
__int64 __fastcall CConfigCacheT<CEmptyType>::PhoneGetPkeyActivationData<CAlgorithmsFactoryClient>(
        __int64 a1,
        unsigned __int16 *a2,
        void *a3)
{
  __int64 v3; // rbx
  int v7; // r14d
  int v8; // eax
  unsigned int v9; // edi
  __int64 v10; // rcx
  unsigned int v11; // r13d
  unsigned __int16 *v12; // r8
  int v13; // ecx
  int v14; // eax
  int PkeyAlgorithm; // eax
  int v16; // eax
  int v18; // [rsp+30h] [rbp-49h] BYREF
  __int64 v19; // [rsp+38h] [rbp-41h]
  __int64 v20[2]; // [rsp+40h] [rbp-39h] BYREF
  _BYTE Src[40]; // [rsp+50h] [rbp-29h] BYREF
  UUID Uuid; // [rsp+78h] [rbp-1h] BYREF
  __int64 v23; // [rsp+88h] [rbp+Fh] BYREF
  int v24; // [rsp+90h] [rbp+17h]
  char v25; // [rsp+94h] [rbp+1Bh]

  v3 = 0i64;
  v19 = 0i64;
  memcpy(Src, &`CBinaryTool<BASE_PKEY_DATA>::ZeroMem'::`2'::g_buffer, sizeof(Src));
  v23 = 0i64;
  v24 = 0;
  v25 = 0;
  v7 = 0;
  v18 = 13;
  v8 = CConfigCacheT<CEmptyType>::ParseUniqueIdToken(a2, &Uuid, (__int64)&v23, &v18, (const wchar_t **)v20);
  v9 = v8;
  if ( v8 < 0 )
  {
    CBreakOnFailureT<CEmptyType>::CheckToBreakOnFailure((unsigned int)v8);
    return v9;
  }
  if ( a1 != -8 )
  {
    CRWLock2T<CEmptyType>::AcquireShared(a1 + 8);
    v7 = 1;
  }
  if ( !(unsigned __int8)CSortedArray<DP_COM<CConfigurationInfo>,_GUID,CAdaptorDefault,CPoliciesDefaultSpecialize>::Find(
                           a1 + 112,
                           &Uuid,
                           &v18) )
  {
    v9 = -2147217389;
LABEL_7:
    v10 = v9;
LABEL_8:
    CBreakOnFailureT<CEmptyType>::CheckToBreakOnFailure(v10);
    goto LABEL_25;
  }
  v11 = *(_DWORD *)(*(_QWORD *)(*(_QWORD *)(a1 + 120) + 8i64 * v18) + 20i64);
  if ( !(unsigned __int8)CSortedArray<DP_COM<CPublicKeyInfo>,unsigned long,CAdaptorDefault,CPoliciesDefaultSpecialize>::Find(
                           a1 + 128,
                           v11,
                           &v18) )
  {
    v9 = -2147418113;
    goto LABEL_7;
  }
  v12 = (unsigned __int16 *)v20[0];
  if ( v20[0] )
  {
    do
    {
      v13 = *(unsigned __int16 *)((char *)v12
                                + *(_QWORD *)(*(_QWORD *)(*(_QWORD *)(a1 + 136) + 8i64 * v18) + 8i64)
                                - v20[0]);
      v14 = *v12 - v13;
      if ( v14 )
        break;
      ++v12;
    }
    while ( v13 );
    if ( v14 )
    {
LABEL_15:
      v10 = 2147749921i64;
      v9 = -2147217375;
      goto LABEL_8;
    }
  }
  PkeyAlgorithm = CConfigCacheUtil::CreatePkeyAlgorithmObject<CAlgorithmsFactoryClient>(*(unsigned __int16 **)(*(_QWORD *)(*(_QWORD *)(a1 + 136) + 8i64 * v18) + 8i64));
  v9 = PkeyAlgorithm;
  if ( PkeyAlgorithm >= 0 )
  {
    v3 = v19;
    v16 = (*(__int64 (__fastcall **)(__int64, __int64 *, _BYTE *))(*(_QWORD *)v19 + 40i64))(v19, &v23, Src);
    v9 = v16;
    if ( v16 < 0 )
    {
      v10 = (unsigned int)v16;
      goto LABEL_8;
    }
    if ( *(_DWORD *)&Src[16] )
    {
      if ( v11 != *(_DWORD *)&Src[16] )
        goto LABEL_15;
    }
    else
    {
      *(_DWORD *)&Src[16] = v11;
    }
    *(_OWORD *)Src = *(_OWORD *)v20;
    memcpy(a3, Src, 0x28ui64);
  }
  else
  {
    CBreakOnFailureT<CEmptyType>::CheckToBreakOnFailure((unsigned int)PkeyAlgorithm);
    v3 = v19;
  }
LABEL_25:
  if ( a1 != -8 && v7 )
    CRWLock2T<CEmptyType>::ReleaseLockEx(a1 + 8);
  if ( v3 )
    (*(void (__fastcall **)(__int64))(*(_QWORD *)v3 + 16i64))(v3);
  return v9;
}