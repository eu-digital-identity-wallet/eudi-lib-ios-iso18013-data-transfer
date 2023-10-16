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
  - `deviceResponseToSend`
  - `validRequestItems`
  - `errorRequestItems`
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
  - `requireUserAccept`
  - `readBuffer`
  - `sendBuffer`
  - `numBlocks`
  - `subscribeCount`
  - `isBlePoweredOn`
  - `isBlePermissionDenied`
  - `isPreview`
  - `isInErrorState`
- [Methods](#methods)
  - `init(status:)`
  - `performDeviceEngagement()`
  - `buildServices(uuid:)`
  - `start()`
  - `stop()`
  - `handleStatusChange(_:)`
  - `userSelected(_:_:)`
  - `handleErrorSet(_:)`
  - `prepareDataToSend(_:)`
  - `sendDataWithUpdates()`

```swift
public class MdocGattServer: ObservableObject, MdocTransferManager
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

### `deviceResponseToSend`

```swift
public var deviceResponseToSend: DeviceResponse?
```

### `validRequestItems`

```swift
public var validRequestItems: RequestItems?
```

### `errorRequestItems`

```swift
public var errorRequestItems: RequestItems?
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
@Published public var qrCodeImageData: Data?
```

### `delegate`

```swift
public weak var delegate: (any MdocOfflineDelegate)?
```

### `advertising`

```swift
@Published public var advertising: Bool = false
```

### `error`

```swift
@Published public var error: Error? = nil
```

### `status`

```swift
@Published public var status: TransferStatus = .initializing
```

### `requireUserAccept`

```swift
public var requireUserAccept = false
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
### `init(status:)`

```swift
public init(status: TransferStatus = .initializing)
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
