**CLASS**

# `MdocGattServer`

**Contents**

- [Properties](#properties)
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
  - `isBlePoweredOn`
  - `isBlePermissionDenied`
- [Methods](#methods)
  - `init(parameters:)`
  - `performDeviceEngagement(rfus:)`
  - `stop()`
  - `userSelected(_:_:)`

```swift
public class MdocGattServer: ObservableObject
```

BLE Gatt server implementation of mdoc transfer manager

## Properties
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

### `devicePrivateKeys`

```swift
public var devicePrivateKeys: [CoseKeyPrivate]!
```

### `dauthMethod`

```swift
public var dauthMethod: DeviceAuthMethod
```

### `readerName`

```swift
public var readerName: String?
```

### `qrCodePayload`

```swift
public var qrCodePayload: String?
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

## Methods
### `init(parameters:)`

```swift
public init(parameters: [String: Any]) throws
```

### `performDeviceEngagement(rfus:)`

```swift
public func performDeviceEngagement(rfus: [String]? = nil)
```

``qrCodePayload`` is set to QR code data corresponding to the device engagement.

### `stop()`

```swift
public func stop()
```

### `userSelected(_:_:)`

```swift
public func userSelected(_ b: Bool, _ items: RequestItems?)
```
