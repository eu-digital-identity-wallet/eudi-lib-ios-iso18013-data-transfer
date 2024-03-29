# Sample Data

The SampleData CBOR structure encoded in Base64:

```json
{
  "Data": "<SampleData CBOR structure encoded in Base64>"
}
```

The SampleData shall be CBOR encoded and formatted as follows:

``` 
SampleData = {
 "version" : tstr, ; Version of the SamplaData structure
 "documents" : [+Document], ;  Documents
 "status" : uint ; Status code
}

Document = {
 "docType" : DocType, ; Document type
 "issuerSigned" : IssuerSigned
}

IssuerSigned = {
 "nameSpaces" : IssuerNameSpaces, ; Data elements
}
    
IssuerNameSpaces = {
 NameSpace => [ + IssuerSignedItemBytes ]
}
    
IssuerSignedItemBytes = #6.24(bstr .cbor IssuerSignedItem)

IssuerSignedItem = {
 "digestID" : uint, ; Digest ID for issuer data authentication
 "random" : bstr, ; Random value for issuer data authentication
 "elementIdentifier" : DataElementIdentifier, ; Data element identifier
 "elementValue" : DataElementValue ; Data element value
}
```

Note that the SampleData structure is similar to the **DeviceResponse** structure as defined in
**ISO 18013-5 clause 8.3.2.1.2.2 "Device retrieval mdoc response"**, except that the "issuerAuth"
field that contains the mobile security object (MSO) doesn't exist. At the present time the MSO is
generated and signed by the library.

You can replace the `sample_data.json` file with your own data.
