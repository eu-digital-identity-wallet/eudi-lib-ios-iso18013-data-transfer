**CLASS**

# `MdocGattServer.Delegate`

**Contents**

- [Properties](#properties)
  - `server`
- [Methods](#methods)
  - `init(server:)`
  - `peripheralManagerIsReady(toUpdateSubscribers:)`
  - `peripheralManagerDidUpdateState(_:)`
  - `peripheralManager(_:didReceiveWrite:)`
  - `peripheralManager(_:central:didSubscribeTo:)`
  - `peripheralManager(_:central:didUnsubscribeFrom:)`

```swift
class Delegate: NSObject, CBPeripheralManagerDelegate
```

## Properties
### `server`

```swift
unowned var server: MdocGattServer
```

## Methods
### `init(server:)`

```swift
init(server: MdocGattServer)
```

### `peripheralManagerIsReady(toUpdateSubscribers:)`

```swift
func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager)
```

### `peripheralManagerDidUpdateState(_:)`

```swift
func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager)
```

### `peripheralManager(_:didReceiveWrite:)`

```swift
func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest])
```

### `peripheralManager(_:central:didSubscribeTo:)`

```swift
public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic)
```

### `peripheralManager(_:central:didUnsubscribeFrom:)`

```swift
public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic)
```
