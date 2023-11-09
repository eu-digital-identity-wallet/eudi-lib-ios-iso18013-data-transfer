**CLASS**

# `MdocGattServer`

**Contents**

- [Properties](#properties)
  - `peripheralManager`
  - `bleDelegate`
  - `remoteCentral`
  - `stateCharacteristic`
  - `server2ClientCharacteristic`
  - `deviceEngagement`
  - `deviceRequest`
  - `sessionEncryption`
  - `docs`
  - `iaca`
  - `devicePrivateKey`
  - `readerName`
  - `qrCodeImageData`
  - `delegate`
  - `advertising`
  - `error`
  - `status`
  - `readBuffer`
  - `sendBuffer`
  - `numBlocks`
  - `subscribeCount`
  - `isBlePoweredOn`
  - `isBlePermissionDenied`
  - `isPreview`
  - `isInErrorState`
- [Methods](#methods)
  - `init(parameters:)`
  - `performDeviceEngagement()`
  - `buildServices(uuid:)`
  - `start()`
  - `stop()`
  - `handleStatusChange(_:)`
  - `userSelected(_:_:)`
  - `handleErrorSet(_:)`
  - `prepareDataToSend(_:)`
  - `sendDataWithUpdates()`
  - `getSessionDataToSend(docToSend:)`
  - `decodeRequestAndInformUser(requestData:devicePrivateKey:readerKeyRawData:handOver:handler:)`
  - `makeError(code:str:)`

```swift
public class MdocGattServer: ObservableObject
```

BLE Gatt server implementation of mdoc transfer manager

## Properties
### `peripheralManager`

```swift
var peripheralManager: CBPeripheralManager!
```

### `bleDelegate`

```swift
var bleDelegate: Delegate!
```

### `remoteCentral`

```swift
var remoteCentral: CBCentral!
```

### `stateCharacteristic`

```swift
var stateCharacteristic: CBMutableCharacteristic!
```

### `server2ClientCharacteristic`

```swift
var server2ClientCharacteristic: CBMutableCharacteristic!
```

### `deviceEngagement`

```swift
public var deviceEngagement: DeviceEngagement?
```

### `deviceRequest`

```swift
public var deviceRequest: DeviceRequest?
```

### `sessionEncryption`

```swift
public var sessionEncryption: SessionEncryption?
```

### `docs`

```swift
public var docs: [DeviceResponse]!
```

### `iaca`

```swift
public var iaca: [SecCertificate]!
```

### `devicePrivateKey`

```swift
public var devicePrivateKey: CoseKeyPrivate!
```

### `readerName`

```swift
public var readerName: String?
```

### `qrCodeImageData`

```swift
public var qrCodeImageData: Data?
```

### `delegate`

```swift
public weak var delegate: (any MdocOfflineDelegate)?
```

### `advertising`

```swift
public var advertising: Bool = false
```

### `error`

```swift
public var error: Error? = nil
```

### `status`

```swift
public var status: TransferStatus = .initializing
```

### `readBuffer`

```swift
var readBuffer = Data()
```

### `sendBuffer`

```swift
var sendBuffer = [Data]()
```

### `numBlocks`

```swift
var numBlocks: Int = 0
```

### `subscribeCount`

```swift
var subscribeCount: Int = 0
```

### `isBlePoweredOn`

```swift
public var isBlePoweredOn: Bool
```

Returns true if the peripheralManager state is poweredOn

### `isBlePermissionDenied`

```swift
public var isBlePermissionDenied: Bool
```

Returns true if the peripheralManager state is unauthorized

### `isPreview`

```swift
var isPreview: Bool
```

### `isInErrorState`

```swift
var isInErrorState: Bool
```

## Methods
### `init(parameters:)`

```swift
public init(parameters: [String: Any]) throws
```

### `performDeviceEngagement()`

```swift
public func performDeviceEngagement()
```

``qrCodeImageData`` is set to QR code image data corresponding to the device engagement.

### `buildServices(uuid:)`

```swift
func buildServices(uuid: String)
```

### `start()`

```swift
func start()
```

### `stop()`

```swift
public func stop()
```

### `handleStatusChange(_:)`

```swift
func handleStatusChange(_ newValue: TransferStatus)
```

### `userSelected(_:_:)`

```swift
public func userSelected(_ b: Bool, _ items: RequestItems?)
```

### `handleErrorSet(_:)`

```swift
func handleErrorSet(_ newValue: Error?)
```

### `prepareDataToSend(_:)`

```swift
func prepareDataToSend(_ msg: Data)
```

### `sendDataWithUpdates()`

```swift
func sendDataWithUpdates()
```

### `getSessionDataToSend(docToSend:)`

```swift
public func getSessionDataToSend(docToSend: DeviceResponse) -> Data?
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

### `makeError(code:str:)`

```swift
public static func makeError(code: ErrorCode, str: String? = nil) -> NSError
```
