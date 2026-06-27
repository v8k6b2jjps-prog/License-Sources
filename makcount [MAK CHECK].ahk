
// SimplePidX - Simple, yet powerful product key checker - My Digital Life Forums
// https://forums.mydigitallife.net/threads/simplepidx-simple-yet-powerful-product-key-checker.80300/

#Include %A_ScriptDir%\libs\libcrypt.ahk

GetMAKActivationCount(Pid) {
    Response := GetActivationServerResponse(CreateMAKCheckXml(Pid))

    XmlDoc := ComObjCreate("MSXML2.DOMDocument.6.0")
    XmlDoc.async := false
    XmlDoc.loadXML(Response)

    XmlDoc.setProperty("SelectionNamespaces", "xmlns:r='http://www.microsoft.com/BatchActivationService' xmlns:soap='http://schemas.xmlsoap.org/soap/envelope/'")
    Node := XmlDoc.selectSingleNode("//soap:Envelope/soap:Body/r:BatchActivateResponse/r:BatchActivateResult/r:ResponseXml")
    ResponseXml := Node.text

    If(ResponseXml == "")
    {
        Return -2
    }

    XmlDoc := ComObjCreate("MSXML2.DOMDocument.6.0")
    XmlDoc.async := false
    XmlDoc.loadXML(ResponseXml)

    XmlDoc.setProperty("SelectionNamespaces", "xmlns:r='http://www.microsoft.com/DRM/SL/BatchActivationResponse/1.0'")
    CountNode := XmlDoc.selectSingleNode("//r:ActivationResponse/r:Responses/r:Response/r:ActivationRemaining")
    ErrorNode := XmlDoc.selectSingleNode("//r:ActivationResponse/r:Responses/r:Response/r:ErrorInfo/r:ErrorCode")

    MAKCount := CountNode.text
    ErrorCode := ErrorNode.text

    If(ErrorCode == "0x67")
    {
        Return -3
    }
    Else If(ErrorCode == "0x86")
    {
        Return -4
    }
    Else If(MAKCount == "")
    {
        Return -2
    }
    Else
    {
        Return MAKCount
    }
}

CreateMAKCheckXml(Pid) {
    Key := "fe319875fb4884869cf3f1ce99a89064ab571fca470450583024e214628779a0"
    ActData := "
(
<ActivationRequest xmlns=""http://www.microsoft.com/DRM/SL/BatchActivationRequest/1.0"">
    <VersionNumber>2.0</VersionNumber>
    <RequestType>2</RequestType>
    <Requests>
        <Request>
            <PID>" Pid "</PID>
        </Request>
    </Requests>
</ActivationRequest>
)"

    Len := StrPutVar(ActData, ActDataUtf16, "utf-16")
    Len := (Len*2)-2
    LC_Base64_Encode(ActData_Base64, ActDataUtf16, Len)

    LC_Hex2Bin(TrueKey, Key)
    HMAC := bcrypt_sha256_hmac(ActDataUtf16, TrueKey, Len, 32)
    HMAC_Len := StrLen(HMAC)

    LC_Hex2Bin(HMAC_Dec, HMAC)
    LC_Base64_Encode(HMAC_Base64, HMAC_Dec, HMAC_Len/2)

    FinalXml := "
(
<?xml version=""1.0"" encoding=""utf-8""?>
<soap:Envelope xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns:xsd=""http://www.w3.org/2001/XMLSchema"">
    <soap:Body>
        <BatchActivate xmlns=""http://www.microsoft.com/BatchActivationService"">
            <request>
                <Digest>" HMAC_Base64 "</Digest>
                <RequestXml>" ActData_Base64 "</RequestXml>
            </request>
        </BatchActivate>
    </soap:Body>
</soap:Envelope>
)"

    return FinalXml
}

GetActivationServerResponse(Data) {
    URL := "https://activation.sls.microsoft.com/BatchActivation/BatchActivation.asmx"
    WebRequest := ComObjCreate("MSXML2.ServerXMLHTTP")
    WebRequest.open("POST", URL, true)
    WebRequest.setRequestHeader("User-Agent", "Mozilla/4.0 (compatible; MSIE 6.0; MS Web Services Client Protocol 2.0.50727.5420)")
    WebRequest.setRequestHeader("Content-Type", "text/xml; charset=utf-8")
    WebRequest.setRequestHeader("SOAPAction", """http://www.microsoft.com/BatchActivationService/BatchActivate""")
    WebRequest.setRequestHeader("Expect", "100-continue")
    WebRequest.send(Data)

    StartTime := A_TickCount

    while(WebRequest.readyState != 4) {
        Sleep, 10

        If((A_TickCount - StartTime) > 20000) {
            WebRequest.abort()
            return ""
        }
    }

    return WebRequest.ResponseText
}

;https://www.autohotkey.com/docs/commands/StrPutGet.htm
StrPutVar(string, ByRef var, encoding)
{
    ; Ensure capacity.
    VarSetCapacity( var, StrPut(string, encoding)
        ; StrPut returns char count, but VarSetCapacity needs bytes.
        * ((encoding="utf-16"||encoding="cp1200") ? 2 : 1) )
    ; Copy or convert the string.
    return StrPut(string, &var, encoding)
}

/*
The following function is a modified version of bcrypt_sha256_hmac function
created by jNizM on GitHub.

Original version:
https://github.com/jNizM/AHK_CNG/blob/master/src/hash/func/bcrypt_sha256_hmac.ahk
*/
bcrypt_sha256_hmac(Byref string, Byref hmac, stringLen, hmacLen)
{
    static BCRYPT_SHA256_ALGORITHM     := "SHA256"
    static BCRYPT_ALG_HANDLE_HMAC_FLAG := 0x00000008
    static BCRYPT_OBJECT_LENGTH        := "ObjectLength"
    static BCRYPT_HASH_LENGTH          := "HashDigestLength"

    try
    {
        ; loads the specified module into the address space of the calling process
        if !(hBCRYPT := DllCall("LoadLibrary", "str", "bcrypt.dll", "ptr"))
            throw Exception("Failed to load bcrypt.dll", -1)

        ; open an algorithm handle
        if (NT_STATUS := DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", hAlg, "ptr", &BCRYPT_SHA256_ALGORITHM, "ptr", 0, "uint", BCRYPT_ALG_HANDLE_HMAC_FLAG) != 0)
            throw Exception("BCryptOpenAlgorithmProvider: " NT_STATUS, -1)

        ; calculate the size of the buffer to hold the hash object
        if (NT_STATUS := DllCall("bcrypt\BCryptGetProperty", "ptr", hAlg, "ptr", &BCRYPT_OBJECT_LENGTH, "uint*", cbHashObject, "uint", 4, "uint*", cbData, "uint", 0) != 0)
            throw Exception("BCryptGetProperty: " NT_STATUS, -1)

        ; allocate the hash object
        VarSetCapacity(pbHashObject, cbHashObject, 0)
        ;    throw Exception("Memory allocation failed", -1)

        ; calculate the length of the hash
        if (NT_STATUS := DllCall("bcrypt\BCryptGetProperty", "ptr", hAlg, "ptr", &BCRYPT_HASH_LENGTH, "uint*", cbHash, "uint", 4, "uint*", cbData, "uint", 0) != 0)
            throw Exception("BCryptGetProperty: " NT_STATUS, -1)

        ; allocate the hash buffer
        VarSetCapacity(pbHash, cbHash, 0)
        ;    throw Exception("Memory allocation failed", -1)

        ; create a hash
        if (NT_STATUS := DllCall("bcrypt\BCryptCreateHash", "ptr", hAlg, "ptr*", hHash, "ptr", &pbHashObject, "uint", cbHashObject, "ptr", &hmac, "uint", hmacLen, "uint", 0) != 0)
            throw Exception("BCryptCreateHash: " NT_STATUS, -1)

        ; hash some data
        if (NT_STATUS := DllCall("bcrypt\BCryptHashData", "ptr", hHash, "ptr", &string, "uint", stringLen, "uint", 0) != 0)
            throw Exception("BCryptHashData: " NT_STATUS, -1)

        ; close the hash
        if (NT_STATUS := DllCall("bcrypt\BCryptFinishHash", "ptr", hHash, "ptr", &pbHash, "uint", cbHash, "uint", 0) != 0)
            throw Exception("BCryptFinishHash: " NT_STATUS, -1)

        loop % cbHash
            hash .= Format("{:02x}", NumGet(pbHash, A_Index - 1, "uchar"))
    }
    catch exception
    {
        ; represents errors that occur during application execution
        throw Exception
    }
    finally
    {
        ; cleaning up resources
        if (pbInput)
            VarSetCapacity(pbInput, 0)
        if (hHash)
            DllCall("bcrypt\BCryptDestroyHash", "ptr", hHash)
        if (pbHash)
            VarSetCapacity(pbHash, 0)
        if (pbHashObject)
            VarSetCapacity(pbHashObject, 0)
        if (hAlg)
            DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
        if (hBCRYPT)
            DllCall("FreeLibrary", "ptr", hBCRYPT)
    }

    return hash
}
