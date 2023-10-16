**CLASS**

# `DefaultTransferDelegate`

**Contents**

- [Properties](#properties)
  - `readerCertIsserMessage`
  - `readerCertValidationMessage`
  - `hasError`
  - `errorMessage`
  - `selectedRequestItems`
  - `status`
  - `handleSelected`
- [Methods](#methods)
  - `init(readerCertIsserMessage:readerCertValidationMessage:hasError:errorMessage:selectedRequestItems:handleSelected:)`
  - `didChangeStatus(_:)`
  - `didReceiveRequest(_:handleSelected:)`
  - `didFinishedWithError(_:)`

```swift
public class DefaultTransferDelegate: ObservableObject, MdocOfflineDelegate
```

## Properties
### `readerCertIsserMessage`

```swift
@Published public var readerCertIsserMessage: String?
```

### `readerCertValidationMessage`

```swift
@Published public var readerCertValidationMessage: String?
```

### `hasError`

```swift
@Published public var hasError: Bool = false
```

### `errorMessage`

```swift
@Published public var errorMessage: String = ""
```

### `selectedRequestItems`

```swift
@Published public var selectedRequestItems: [DocElementsViewModel] = []
```

### `status`

```swift
@Published public var status: TransferStatus = .initializing
```

### `handleSelected`

```swift
public var handleSelected: (Bool, RequestItems?) -> Void = { _,_ in }
```

## Methods
### `init(readerCertIsserMessage:readerCertValidationMessage:hasError:errorMessage:selectedRequestItems:handleSelected:)`

```swift
public init(readerCertIsserMessage: String? = nil, readerCertValidationMessage: String? = nil, hasError: Bool = false, errorMessage: String = "", selectedRequestItems: [DocElementsViewModel] = [], handleSelected: @escaping (Bool, RequestItems?) -> Void = { _,_ in })
```

### `didChangeStatus(_:)`

```swift
public func didChangeStatus(_ newStatus: TransferStatus)
```

### `didReceiveRequest(_:handleSelected:)`

```swift
public func didReceiveRequest(_ request: [String: Any], handleSelected: @escaping (Bool, RequestItems?) -> Void)
```

### `didFinishedWithError(_:)`

```swift
public func didFinishedWithError(_ error: Error)
```
