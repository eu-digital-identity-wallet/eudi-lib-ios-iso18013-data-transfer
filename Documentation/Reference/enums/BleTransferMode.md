**ENUM**

# `BleTransferMode`

**Contents**

- [Cases](#cases)
  - `server`
  - `client`
- [Properties](#properties)
  - `BASE_UUID_SUFFIX_SERVICE`
  - `QRHandover`

```swift
public enum BleTransferMode
```

The enum BleTransferMode defines the two roles in the communication, which can be a server or a client.

The four static variables are used to signal the start and the end of the communication. This is done by sending the bytes 0x01 and 0x02 for the start and end of the communication, respectively. For the start and end of the data transmission, the bytes 0x01 and 0x00 are used.

## Cases
### `server`

```swift
case server
```

### `client`

```swift
case client
```

## Properties
### `BASE_UUID_SUFFIX_SERVICE`

```swift
public static let BASE_UUID_SUFFIX_SERVICE = "-0000-1000-8000-00805F9B34FB"
```

### `QRHandover`

```swift
public static let QRHandover = CBOR.null
```
