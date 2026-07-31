/*
Copyright (c) 2026 European Commission

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

		http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import Foundation

/// Factory protocol for creating BLE transport instances.
///
/// Conform to this protocol to supply custom BLE implementations
/// (e.g., L2CAP mode, BLE client mdoc) to the wallet's proximity presentation layer.
///
/// The wallet calls ``createServer()`` or ``createClient()`` depending on the
/// configured ``BleTransferMode``. When the mode is `.both`, both methods are called.
public protocol BleTransportFactory: Sendable {
	#if !os(watchOS)
	/// Create a transport for the peripheral server role (GATT server).
	func createServer() -> any MdocBleTransport
	#endif
	/// Create a transport for the central client role (GATT central).
	func createClient() -> any MdocBleTransport
}

/// Default factory that creates standard GATT server and central transports.
public struct DefaultBleTransportFactory: BleTransportFactory {
	public init() {}
	#if !os(watchOS)
	public func createServer() -> any MdocBleTransport { MdocGattServer() }
	#endif
	public func createClient() -> any MdocBleTransport { MdocGattCentral() }
}


