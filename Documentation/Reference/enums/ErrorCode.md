**ENUM**

# `ErrorCode`

**Contents**

- [Cases](#cases)
  - `documents_not_provided`
  - `invalidInputDocument`
  - `invalidUrl`
  - `device_private_key_not_provided`
  - `noDocumentToReturn`
  - `userRejected`
  - `requestDecodeError`
  - `bleNotAuthorized`
  - `bleNotSupported`
  - `unexpected_error`
  - `sessionEncryptionNotInitialized`
  - `deviceEngagementMissing`
  - `readerKeyMissing`
- [Properties](#properties)
  - `description`

```swift
public enum ErrorCode: Int, CustomStringConvertible
```

Possible error codes

## Cases
### `documents_not_provided`

```swift
case documents_not_provided
```

### `invalidInputDocument`

```swift
case invalidInputDocument
```

### `invalidUrl`

```swift
case invalidUrl
```

### `device_private_key_not_provided`

```swift
case device_private_key_not_provided
```

### `noDocumentToReturn`

```swift
case noDocumentToReturn
```

### `userRejected`

```swift
case userRejected
```

### `requestDecodeError`

```swift
case requestDecodeError
```

### `bleNotAuthorized`

```swift
case bleNotAuthorized
```

### `bleNotSupported`

```swift
case bleNotSupported
```

### `unexpected_error`

```swift
case unexpected_error
```

### `sessionEncryptionNotInitialized`

```swift
case sessionEncryptionNotInitialized
```

### `deviceEngagementMissing`

```swift
case deviceEngagementMissing
```

### `readerKeyMissing`

```swift
case readerKeyMissing
```

## Properties
### `description`

```swift
public var description: String
```
