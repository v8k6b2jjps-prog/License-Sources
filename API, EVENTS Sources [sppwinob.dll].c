// Original Name: sub_180030064 (SppNotificationBiosPropertyDispatcher)
// DLL: sppwinob.dll
// Role: Routes Property requests to specific BIOS-reading functions
// Called by `SLGetServiceInformation` -> Slc.dll -> Sppc.dll -> sppsvc.exe -> sppwinob.dll

NTSTATUS Dispatcher(Request, Response) {
    // 1. Get the name of the property the user requested in PowerShell
    RequestedName = Request->GetProperty("SppNotificationPropertyName");

    // 2. Logic Route: Compare string and call the "Producer"
    if (RequestedName == L"BiosProductKey") {
        // Calls the low-level reader (sppobjs logic)
        Status = ReadBiosMsdmTable(&DataBuffer); 
    }
    else if (RequestedName == L"BiosSlicState") {
        // Checks for SLIC 2.1 tables
        Status = CheckSlicVersion(&DataInt);
        DataType = REG_DWORD;
    }
    else if (RequestedName == L"BiosProductKeyDescription") {
        Status = FetchKeyChannelInfo(&DataBuffer);
    }
    else {
        return E_INVALID_PROPERTY;
    }

    // 3. Packaging: Wrap the raw data for the PowerShell script to receive
    Response->SetProperty("SppNotificationPropertyValue", DataBuffer);
    
    return Status;
}

// Original Name: sub_180030274
// DLL: sppwinob.dll
// Role: Validates license binding and key type before triggering the mirror

NTSTATUS ProcessLicenseBindingAndMirror(Context* ctx, GUID* licenseGuid) 
{
    // 1. Fetch the PKey (Product Key) Binding ID
    Status = ctx->GetBindingId(licenseGuid, &bindingId);
    if (FAILED(Status)) return Status;

    // 2. Load the PKey properties (SppBindingPkeyId, ProductSkuId, etc.)
    Status = ctx->LoadBindingProperties(L"SppBindingPkeyId", ...);
    
    // 3. Extract the "DigitalProductId4" blob from the SPP Store
    // Offset +508 in the struct is checked to identify the key type
    Status = ctx->GetProperty(L"SppPkeyBindingPid4", &pid4Buffer, &bufferSize);
    
    if (SUCCEEDED(Status) && bufferSize == 1272) {
        DigitalProductId4* structPtr = (DigitalProductId4*)pid4Buffer;

        // Check if this is a Volume key (CSVLK/MAK) or Enterprise OEM
        bool isVolumeKey = (wcscmp(structPtr->m_partNumber, L"Volume:CSVLK") == 0 || 
                            wcscmp(structPtr->m_partNumber, L"Volume:MAK") == 0);
        
        // 4. Extract the other required blobs (Pid2 and Pid3)
        ctx->GetProperty(L"SppPkeyBindingPid2", &pid2); // Legacy Id
        ctx->GetProperty(L"SppPkeyBindingPid3", &pid3); // DigitalProductId

        // 5. Final Step: Trigger the actual Registry Mirroring
        return MirrorLicenseToSystemLocations(48, pid2, 164, pid3, 1272, pid4Buffer);
    }

    return E_FAIL;
}

// Original Name: sub_18003CA0C
// DLL: sppwinob.dll
// Role: Orchestrates mirroring across Windows NT and Internet Explorer keys

NTSTATUS MirrorLicenseToSystemLocations(int idLen, BYTE* id, 
                                        int digIdLen, BYTE* digId, 
                                        int digId4Len, BYTE* digId4) 
{
    // 1. Sanity Check: Ensure pointers exist and sizes match the expected 1272-byte struct
    if (!id || !digId || !digId4) return E_INVALIDARG;
    if (idLen != 48 || digIdLen != 164 || digId4Len != 1272) return E_UNEXPECTED;

    // 2. Mirror to Windows NT CurrentVersion (Standard location)
    Status = WriteLicenseBlobsToRegistry(L"Software\\Microsoft\\Windows NT\\CurrentVersion\\", 
                                         0x30, id, 0xA4, digId, 0x4F8, digId4);
    if (FAILED(Status)) return Status;

    // 3. Mirror to IE Registration (Legacy/Compatibility location)
    Status = WriteLicenseBlobsToRegistry(L"Software\\Microsoft\\Internet Explorer\\Registration", 
                                         0x30, id, 0xA4, digId, 0x4F8, digId4);

    return Status;
}

// Original Name: sub_18003E8D8
// DLL: sppwinob.dll
// Role: Low-level Registry Value Setter for License Blobs

NTSTATUS WriteLicenseBlobsToRegistry(LPCWSTR subKeyPath, 
                                     DWORD productIdSize, BYTE* productIdData, 
                                     DWORD digitalIdSize, BYTE* digitalIdData, 
                                     DWORD digitalId4Size, BYTE* digitalId4Data) 
{
    HKEY hKey = NULL;
    
    // 1. Open/Create the target key (HKLM\...)
    Status = RegCreateKeyExW(HKEY_LOCAL_MACHINE, subKeyPath, ..., &hKey);
    if (FAILED(Status)) return Status;

    // 2. Write the legacy ProductId (REG_SZ)
    Status = RegSetValueExW(hKey, L"ProductId", REG_SZ, productIdData, productIdSize);
    if (FAILED(Status)) goto Cleanup;

    // 3. Write the DigitalProductId (REG_BINARY) - 164 bytes
    Status = RegSetValueExW(hKey, L"DigitalProductId", REG_BINARY, digitalIdData, digitalIdSize);
    if (FAILED(Status)) goto Cleanup;

    // 4. Write the DigitalProductId4 (REG_BINARY) - 1272 bytes
    Status = RegSetValueExW(hKey, L"DigitalProductId4", REG_BINARY, digitalId4Data, digitalId4Size);

Cleanup:
    RegCloseKey(hKey);
    return Status;
}

