
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

typedef struct _BASE_PKEY_DATA
{
    GUID     ActivationId;   // 0x00
    DWORD    GroupId;        // 0x10
    DWORD    SerialHigh;     // 0x14
    DWORD    SerialLow;      // 0x18
    DWORD    Upgrade;        // 0x1C
    ULONGLONG Security;      // 0x20
} BASE_PKEY_DATA;

# Sppobjs.dll, 7600

# Sppobjs.dll, 7850
// positive sp value has been detected, the output may be wrong!
void __fastcall CSppPKeyBinding::ValidatePhoneActivationData(CSppPKeyBinding *this, const struct BASE_PKEY_DATA *a2)
{
  _QWORD *v2; // rbx
  WARBIRD *v4; // rcx

  v2 = (_QWORD *)((char *)this + 1552);
  SP<CAuthenticatedProductKey,SP_COM<CAuthenticatedProductKey>>::Reset((char *)this + 1552);
  if ( a2 && v2 )
  {
    CProductKeyAuthenticatorClientT<CEmptyType>::AuthenticatePkeyData((unsigned int *)a2, v2);
    WARBIRD::Stub_VerifyVerifierCheckSum4(v4);
    JUMPOUT(0x180088C2Ci64);
  }
  WARBIRD::Stub_VerifyVerifierCheckSum1((WARBIRD *)0x80070057i64);
  JUMPOUT(0x180088C42i64);
}
__int64 __fastcall CProductKeyAuthenticatorClientT<CEmptyType>::AuthenticatePkeyData(unsigned int *a1, _QWORD *a2)
{
  _QWORD *v2; // rbx
  int v3; // edi
  unsigned int v6; // edi
  __int64 v7; // rcx
  __int64 v8; // r8
  int v9; // eax
  HANDLE ProcessHeap; // rax
  int v12[4]; // [rsp+20h] [rbp-98h] BYREF
  int v13[24]; // [rsp+30h] [rbp-88h] BYREF

  v2 = 0i64;
  v3 = 0;
  if ( dword_180131390 == 1 )
  {
    EnterCriticalSection(&CConfigCacheSingletonT<CEmptyType>::g_csCache);
    v2 = (_QWORD *)CConfigCacheSingletonT<CEmptyType>::g_pConfigCache;
    _InterlockedIncrement((volatile signed __int32 *)CConfigCacheSingletonT<CEmptyType>::g_pConfigCache);
    LeaveCriticalSection(&CConfigCacheSingletonT<CEmptyType>::g_csCache);
  }
  else
  {
    v3 = -2147418113;
    CBreakOnFailureT<CEmptyType>::CheckToBreakOnFailure(2147549183i64);
  }
  if ( v3 < 0 )
    goto LABEL_11;
  v6 = a1[6] + 1000000 * a1[5];
  memcpy(v13, &`CBinaryTool<DECODED_PKEY_DATA>::ZeroMem'::`2'::g_buffer, 0x58ui64);
  memcpy(&v13[2], &`CBinaryTool<BASE_PKEY_DATA>::ZeroMem'::`2'::g_buffer, 0x28ui64);
  if ( (unsigned __int8)CSortedArray<DP_COM<CPublicKeyInfo>,unsigned long,CAdaptorDefault,CPoliciesDefaultSpecialize>::Find(
                          v2 + 16,
                          a1[4],
                          v12) )
  {
    v8 = *(_QWORD *)(v2[17] + 8i64 * v12[0]);
    v13[7] = v6 / 0xF4240;
    v13[8] = v6 % 0xF4240;
    v9 = CConfigCacheT<CEmptyType>::VerifyConfiguration((__int64)v2, (__int64)v13, v8, a2);
    v3 = v9;
    if ( v9 >= 0 )
      goto LABEL_10;
    v7 = (unsigned int)v9;
  }
  else
  {
    v3 = -2147217388;
    v7 = 2147749908i64;
  }
  CBreakOnFailureT<CEmptyType>::CheckToBreakOnFailure(v7);
LABEL_10:
  if ( v3 < 0 )
LABEL_11:
    CBreakOnFailureT<CEmptyType>::CheckToBreakOnFailure((unsigned int)v3);
  if ( v2 && !_InterlockedDecrement((volatile signed __int32 *)v2) )
  {
    CConfigCacheT<CEmptyType>::~CConfigCacheT<CEmptyType>(v2);
    ProcessHeap = GetProcessHeap();
    HeapFree(ProcessHeap, 0, v2);
  }
  return (unsigned int)v3;
}
__int64 __fastcall CConfigCacheT<CEmptyType>::VerifyConfiguration(__int64 a1, __int64 a2, __int64 a3, __int64 *a4)
{
  int v4; // edi
  int v8; // edi
  int Range; // eax
  unsigned int v11; // ebx
  __int64 v12; // rcx
  struct CRangeInfo *v13; // r12
  struct CConfigurationInfo *v14; // rsi
  HANDLE ProcessHeap; // rax
  void *v16; // rax
  __int64 v17; // rdi
  char v19; // [rsp+70h] [rbp+40h] BYREF
  int v20; // [rsp+78h] [rbp+48h] BYREF
  __int64 v21; // [rsp+80h] [rbp+50h] BYREF

  v4 = *(_DWORD *)(a2 + 28);
  v21 = 0i64;
  v8 = *(_DWORD *)(a2 + 32) + 1000000 * v4;
  Range = CConfigCacheT<CEmptyType>::FindRange((int)a1 + 144, *(_DWORD *)(a3 + 4), 0, v8, (__int64)&v19, (__int64)&v20);
  v11 = Range;
  if ( Range < 0 )
    goto LABEL_2;
  if ( v19 )
  {
    v11 = -2147217371;
    goto LABEL_6;
  }
  Range = CConfigCacheT<CEmptyType>::FindRange((int)a1 + 144, *(_DWORD *)(a3 + 4), 1, v8, (__int64)&v19, (__int64)&v20);
  v11 = Range;
  if ( Range >= 0 )
  {
    if ( v19 )
    {
      v13 = *(struct CRangeInfo **)(*(_QWORD *)(a1 + 152) + 8i64 * v20);
      if ( (unsigned __int8)CSortedArray<DP_COM<CConfigurationInfo>,_GUID,CAdaptorDefault,CPoliciesDefaultSpecialize>::Find(
                              a1 + 112,
                              (char *)v13 + 4,
                              &v20) )
      {
        v14 = *(struct CConfigurationInfo **)(*(_QWORD *)(a1 + 120) + 8i64 * v20);
        ProcessHeap = GetProcessHeap();
        v16 = HeapAlloc(ProcessHeap, 0, 0x98ui64);
        v17 = (__int64)v16;
        if ( v16 )
        {
          memcpy(v16, &`CBinaryTool<CAuthenticatedProductKey>::ZeroMem'::`2'::g_buffer, 0x98ui64);
          *(_DWORD *)v17 = 1;
          *(_QWORD *)(v17 + 8) = 0i64;
          memcpy((void *)(v17 + 32), &`CBinaryTool<DECODED_PKEY_DATA>::ZeroMem'::`2'::g_buffer, 0x58ui64);
          memcpy((void *)(v17 + 40), &`CBinaryTool<BASE_PKEY_DATA>::ZeroMem'::`2'::g_buffer, 0x28ui64);
          *(_QWORD *)(v17 + 120) = 0i64;
          *(_QWORD *)(v17 + 128) = 0i64;
          *(_QWORD *)(v17 + 136) = 0i64;
        }
        else
        {
          v17 = 0i64;
        }
        SP<CAuthenticatedProductKey,SP_COM<CAuthenticatedProductKey>>::Reset(&v21);
        if ( v17 )
        {
          v21 = v17;
          Range = CAuthenticatedProductKey::Init(
                    (BYTE *)v17,
                    (const struct DECODED_PKEY_DATA *)a2,
                    v14,
                    v13,
                    (struct CPublicKeyInfo *)a3);
          v11 = Range;
          if ( Range >= 0 )
          {
            v21 = 0i64;
            *a4 = v17;
            goto LABEL_19;
          }
          goto LABEL_2;
        }
        v21 = 0i64;
        v11 = -2147024882;
      }
      else
      {
        v11 = -2147418113;
      }
    }
    else
    {
      v11 = -2147217372;
    }
LABEL_6:
    v12 = v11;
    goto LABEL_3;
  }
LABEL_2:
  v12 = (unsigned int)Range;
LABEL_3:
  CBreakOnFailureT<CEmptyType>::CheckToBreakOnFailure(v12);
LABEL_19:
  SP<CAuthenticatedProductKey,SP_COM<CAuthenticatedProductKey>>::Reset(&v21);
  return v11;
}