**CLASS**

# `MdocHelpers`

**Contents**

- [Methods](#methods)
  - `initializeData(parameters:)`
  - `makeError(code:str:)`
  - `getSessionDataToSend(sessionEncryption:status:docToSend:)`
  - `decodeRequestAndInformUser(deviceEngagement:docs:iaca:requestData:devicePrivateKey:readerKeyRawData:handOver:)`
  - `getDeviceResponseToSend(deviceRequest:deviceResponses:selectedItems:sessionEncryption:eReaderKey:devicePrivateKey:)`
  - `CountNumBlocks(dataLength:maxBlockSize:)`
  - `CreateBlockCommand(data:blockId:maxBlockSize:)`
  - `checkBleAccess(_:action:)`
  - `checkCameraAccess(_:action:)`
  - `presentSettings(_:msg:)`
  - `getTopViewController(base:)`
  - `getCN(from:)`

```swift
public class MdocHelpers
```

Helper methods

## Methods
### `initializeData(parameters:)`

```swift
public static func initializeData(parameters: [String: Any]) -> (docs: [DeviceResponse], devicePrivateKeys: [CoseKeyPrivate], iaca: [SecCertificate]?, dauthMethod: DeviceAuthMethod)?
```

### `makeError(code:str:)`

```swift
public static func makeError(code: ErrorCode, str: String? = nil) -> NSError
```

### `getSessionDataToSend(sessionEncryption:status:docToSend:)`

```swift
public static func getSessionDataToSend(sessionEncryption: SessionEncryption?, status: TransferStatus, docToSend: DeviceResponse) -> Result<Data, Error>
```

### `decodeRequestAndInformUser(deviceEngagement:docs:iaca:requestData:devicePrivateKeys:dauthMethod:readerKeyRawData:handOver:)`

```swift
public static func decodeRequestAndInformUser(deviceEngagement: DeviceEngagement?, docs: [DeviceResponse], iaca: [SecCertificate], requestData: Data, devicePrivateKeys: [CoseKeyPrivate], dauthMethod: DeviceAuthMethod, readerKeyRawData: [UInt8]?, handOver: CBOR) -> Result<(sessionEncryption: SessionEncryption, deviceRequest: DeviceRequest, params: [String: Any], isValidRequest: Bool), Error>
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

### `getDeviceResponseToSend(deviceRequest:deviceResponses:selectedItems:sessionEncryption:eReaderKey:devicePrivateKeys:dauthMethod:)`

```swift
public static func getDeviceResponseToSend(deviceRequest: DeviceRequest?, deviceResponses: [DeviceResponse], selectedItems: RequestItems? = nil, sessionEncryption: SessionEncryption? = nil, eReaderKey: CoseKey? = nil, devicePrivateKeys: [CoseKeyPrivate], dauthMethod: DeviceAuthMethod) throws -> (response: DeviceResponse, validRequestItems: RequestItems, errorRequestItems: RequestItems)?
```

### `CountNumBlocks(dataLength:maxBlockSize:)`

```swift
public static func CountNumBlocks(dataLength: Int, maxBlockSize: Int) -> Int
```

Returns the number of blocks that dataLength bytes of data can be split into, given a maximum block size of maxBlockSize bytes.
- Parameters:
  - dataLength: Length of data to be split
  - maxBlockSize: The maximum block size
- Returns: Number of blocks

#### Parameters

| Name | Description |
| ---- | ----------- |
| dataLength | Length of data to be split |
| maxBlockSize | The maximum block size |

### `CreateBlockCommand(data:blockId:maxBlockSize:)`

```swift
public static func CreateBlockCommand(data: Data, blockId: Int, maxBlockSize: Int) -> (Data, Bool)
```

Creates a block for a given block id from a data object. The block size is limited to maxBlockSize bytes.
- Parameters:
  - data: The data object to be sent
  - blockId: The id (number) of the block to be sent
  - maxBlockSize: The maximum block size
- Returns: (chunk:The data block, bEnd: True if this is the last block, false otherwise)

#### Parameters

| Name | Description |
| ---- | ----------- |
| data | The data object to be sent |
| blockId | The id (number) of the block to be sent |
| maxBlockSize | The maximum block size |

### `checkBleAccess(_:action:)`

Check if BLE access is allowed, and if not, present a dialog that opens settings
- Parameters:
  - vc: The view controller that will present the settings
  - action: The action to perform

### `checkCameraAccess(_:action:)`

Check if the user has given permission to access the camera. If not, ask them to go to the settings app to give permission.
- Parameters:
  - vc:  The view controller that will present the settings
  - action: The action to perform

### `presentSettings(_:msg:)`

Present an alert controller with a message, and two actions, one to cancel, and one to go to the settings page.
- Parameters:
  - vc: The view controller that will present the settings
  - msg: The message to show

### `getTopViewController(base:)`

Finds the top view controller in the view hierarchy of the app. It is used to present a new view controller on top of any existing view controllers.

### `getCN(from:)`

```swift
public static func getCN(from dn: String) -> String
```

Get the common name (CN) from the certificate distringuished name (DN)
