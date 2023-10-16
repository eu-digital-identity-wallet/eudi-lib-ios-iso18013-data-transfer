**PROTOCOL**

# `MdocTransferManager`

```swift
public protocol MdocTransferManager: AnyObject
```

Protocol for a transfer manager object used to transfer data to and from the Mdoc holder.

## Properties
### `status`

```swift
var status: TransferStatus
```

### `deviceEngagement`

```swift
var deviceEngagement: DeviceEngagement?
```

### `requireUserAccept`

```swift
var requireUserAccept: Bool
```

### `sessionEncryption`

```swift
var sessionEncryption: SessionEncryption?
```

### `deviceRequest`

```swift
var deviceRequest: DeviceRequest?
```

### `deviceResponseToSend`

```swift
var deviceResponseToSend: DeviceResponse?
```

### `validRequestItems`

```swift
var validRequestItems: RequestItems?
```

### `errorRequestItems`

```swift
var errorRequestItems: RequestItems?
```

### `delegate`

```swift
var delegate: MdocOfflineDelegate?
```

### `docs`

```swift
var docs: [DeviceResponse]!
```

### `devicePrivateKey`

```swift
var devicePrivateKey: CoseKeyPrivate!
```

### `iaca`

```swift
var iaca: [SecCertificate]!
```

### `error`

```swift
var error: Error?
```

### `readerName`

```swift
var readerName: String?
```

## Methods
### `initialize(parameters:)`

```swift
func initialize(parameters: [String: Any])
```

### `performDeviceEngagement()`

```swift
func performDeviceEngagement()
```

### `stop()`

```swift
func stop()
```
