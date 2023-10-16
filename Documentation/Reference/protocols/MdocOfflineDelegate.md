**PROTOCOL**

# `MdocOfflineDelegate`

```swift
public protocol MdocOfflineDelegate: AnyObject
```

delegate protocol for clients of the mdoc offline transfer manager

## Methods
### `didChangeStatus(_:)`

```swift
func didChangeStatus(_ newStatus: TransferStatus)
```

### `didFinishedWithError(_:)`

```swift
func didFinishedWithError(_ error: Error)
```

### `didReceiveRequest(_:handleSelected:)`

```swift
func didReceiveRequest(_ request: [String: Any], handleSelected: @escaping (Bool, RequestItems?) -> Void)
```
