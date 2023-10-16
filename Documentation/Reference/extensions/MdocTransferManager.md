**EXTENSION**

# `MdocTransferManager`
```swift
extension MdocTransferManager
```

## Methods
### `initialize(parameters:)`

```swift
public func initialize(parameters: [String: Any])
```

### `decodeRequestAndInformUser(requestData:devicePrivateKey:readerKeyRawData:handOver:handler:)`

```swift
public func decodeRequestAndInformUser(requestData: Data, devicePrivateKey: CoseKeyPrivate, readerKeyRawData: [UInt8]?, handOver: CBOR, handler: @escaping (Bool, RequestItems?) -> Void) -> DeviceRequest?
```

Decrypt the contents of a data object and return a ``DeviceRequest`` object if the data represents a valid device request. If the data does not represent a valid device request, the function returns nil.
- Parameters:
  - requestData: Request data passed to the mdoc holder
  - handler: Handler to call with the accept/reject flag
  - devicePrivateKey: Device private key
  - readerKeyRawData: reader key cbor data (if reader engagement is used)
- Returns: A ``DeviceRequest`` object

#### Parameters

| Name | Description |
| ---- | ----------- |
| requestData | Request data passed to the mdoc holder |
| handler | Handler to call with the accept/reject flag |
| devicePrivateKey | Device private key |
| readerKeyRawData | reader key cbor data (if reader engagement is used) |

### `getDeviceResponseToSend(_:selectedItems:eReaderKey:devicePrivateKey:)`

```swift
@discardableResult public func getDeviceResponseToSend(_ deviceRequest: DeviceRequest?, selectedItems: RequestItems?, eReaderKey: CoseKey?, devicePrivateKey: CoseKeyPrivate) throws -> DeviceResponse?
```

### `getSessionDataToSend(_:eReaderKey:)`

```swift
public func getSessionDataToSend(_ deviceRequest: DeviceRequest, eReaderKey: CoseKey) -> Data?
```

### `makeError(code:str:)`

```swift
public static func makeError(code: ErrorCode, str: String? = nil) -> NSError
```
