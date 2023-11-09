**CLASS**

# `MdocHelpers`

**Contents**

- [Methods](#methods)
  - `initializeData(parameters:)`
  - `getDeviceResponseToSend(deviceRequest:deviceResponses:selectedItems:sessionEncryption:eReaderKey:devicePrivateKey:)`
  - `CountNumBlocks(dataLength:maxBlockSize:)`
  - `CreateBlockCommand(data:blockId:maxBlockSize:)`
  - `checkBleAccess(_:action:)`
  - `checkCameraAccess(_:action:)`
  - `presentSettings(_:msg:)`
  - `getTopViewController(base:)`

```swift
public class MdocHelpers
```

Helper methods

## Methods
### `initializeData(parameters:)`

```swift
public static func initializeData(parameters: [String: Any]) -> (docs: [DeviceResponse], devicePrivateKey: CoseKeyPrivate?, iaca: [SecCertificate]?)?
```

### `getDeviceResponseToSend(deviceRequest:deviceResponses:selectedItems:sessionEncryption:eReaderKey:devicePrivateKey:)`

```swift
public static func getDeviceResponseToSend(deviceRequest: DeviceRequest?, deviceResponses: [DeviceResponse], selectedItems: RequestItems? = nil, sessionEncryption: SessionEncryption? = nil, eReaderKey: CoseKey? = nil, devicePrivateKey: CoseKeyPrivate? = nil) throws -> (response: DeviceResponse, validRequestItems: RequestItems, errorRequestItems: RequestItems)?
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
