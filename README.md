# EUDI Wallet Data Transfer library ISO/IEC 18013-5 for iOS

:heavy_exclamation_mark: **Important!** Before you proceed, please read
the [EUDI Wallet Reference Implementation project description](https://github.com/eu-digital-identity-wallet/.github/blob/main/profile/reference-implementation.md)

----

# EUDI ISO 18013-5 iOS Data Transfer library (ver 0.9.0)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![Swift](https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-data-transfer/actions/workflows/swift.yml/badge.svg)](https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-data-transfer/actions/workflows/swift.yml)
[![Lines of Code](https://sonarcloud.io/api/project_badges/measure?project=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer&metric=ncloc&token=51e16407ebdedc85d6e978d8bc40b0ad3cf61216)](https://sonarcloud.io/summary/new_code?id=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer)
[![Duplicated Lines (%)](https://sonarcloud.io/api/project_badges/measure?project=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer&metric=duplicated_lines_density&token=51e16407ebdedc85d6e978d8bc40b0ad3cf61216)](https://sonarcloud.io/summary/new_code?id=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer&metric=reliability_rating&token=51e16407ebdedc85d6e978d8bc40b0ad3cf61216)](https://sonarcloud.io/summary/new_code?id=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer)
[![Vulnerabilities](https://sonarcloud.io/api/project_badges/measure?project=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer&metric=vulnerabilities&token=51e16407ebdedc85d6e978d8bc40b0ad3cf61216)](https://sonarcloud.io/summary/new_code?id=eu-digital-identity-wallet_eudi-lib-ios-iso18013-data-transfer)

Implementation of mDoc Data retrieval using Bluetooth® low energy (BLE) according to [ISO/IEC 18013-5](https://www.iso.org/standard/69084.html) standard. At the present time, device engagement is available only using QR code.

## Overview
The ``MdocGattServer`` provides the BLE transfer implementation. To begin, create an instance of the class and keep the referenence in the view.

```swift
var bleServerTransfer =	MdocGattServer()
```	

## Initialization
The BLE server needs to be initialized with a dictionary. The parameters are:
|Key | Value|
|--- | ---|
|document_data|Array of documents Base64-serialized as described [here](wiki/SAMPLE_DATA.md) |
|trusted_certificates|Array of trusted certificates of reader authentication|
|require_user_accept|True if holder acceptance is required to send the requested data|

```swift
func initialize() {
	bleServerTransfer.initialize(parameters: [
		InitializeKeys.document_data.rawValue: [Data(name: "sample_data")!],
		InitializeKeys.trusted_certificates.rawValue: [Data(name: "scytales_root_ca", ext: "der")!],
		InitializeKeys.require_user_accept.rawValue: true
		]
	)
	bleServerTransfer.delegate = this
}
```
The delegate object must be an instance of a class conforming to the ``MdocOfflineDelegate`` protocol

```swift
public protocol MdocOfflineDelegate: AnyObject {
  func didChangeStatus(_ newStatus: TransferStatus)
  func didFinishedWithError(_ error: Error)
  func didReceiveRequest(_ request: [String: Any], handleAccept: @escaping (Bool) -> Void)
}
```

## Create device engagement QR code
To initiate the device engagement method, use the following method:

```swift
bleServerTransfer.performDeviceEngagement()
```
The QR code image is available as PNG image data from the property ``qrCodeImageData`` when the ``status`` has the value ``TransferStatus.qrEngagementReady``.
When user (holder) acceptance is required, the app should show the request items and the reader certificate details (if reader auth is used).
The request dictionary in ``didReceiveRequest`` delegate method has the following parameters:

|Key | Value|
|--- | ---|
|items_requested|A dictionary of mdoc-types to array of requested items|
|reader_certificate_issuer|Reader certificate issuer|
|reader_auth_validated|Reader auth signature validated|
|reader_certificate_validation_message|Validation message for the reader certificate|

The BLE server will send the requested if the user accepts. In the case the client app must call the `handleAccept` callback with `true`.

### Disclaimer
The released software is a initial development release version: 
-  The initial development release is an early endeavor reflecting the efforts of a short timeboxed period, and by no means can be considered as the final product.  
-  The initial development release may be changed substantially over time, might introduce new features but also may change or remove existing ones, potentially breaking compatibility with your existing code.
-  The initial development release is limited in functional scope.
-  The initial development release may contain errors or design flaws and other problems that could cause system or other failures and data loss.
-  The initial development release has reduced security, privacy, availability, and reliability standards relative to future releases. This could make the software slower, less reliable, or more vulnerable to attacks than mature software.
-  The initial development release is not yet comprehensively documented. 
-  Users of the software must perform sufficient engineering and additional testing in order to properly evaluate their application and determine whether any of the open-sourced components is suitable for use in that application.
-  We strongly recommend to not put this version of the software into production use.
-  Only the latest version of the software will be supported

### License details

Copyright (c) 2023 European Commission

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
