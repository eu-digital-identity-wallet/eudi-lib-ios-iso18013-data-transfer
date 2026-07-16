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

public protocol MdocBleTransport {
    init()
    /// Start BLE advertising. This should be called when the transport is ready to accept connections.
    func startBleAdvertising()
    /// Stop BLE advertising.
    func stopBleAdvertising()
    /// Stop the transport and clean up any resources. After calling this method, the transport should not be used again.
    func stop()
    /// Whether the transport is powered on and ready to send/receive data. This may depend on BLE state, permissions, etc.
	var isBlePoweredOn: Bool { get }
    /// Whether the transport is authorized to send and receive data. This may depend on BLE permissions, connection state, etc.
	var isAuthorized: Bool { get }
    /// Send data to the connected peer. The transport implementation is responsible for splitting the data into chunks and sending them over BLE.
    func sendData(_ data: Data)
    /// Delegate to receive data and events from the transport.
	var delegate: (any MdocOfflineDelegate)? { get set }
   	/// awaitPsmChannel is called by the wallet to get the PSM channel number for L2CAP mode. If your transport does not support L2CAP, return nil.
	func awaitPsmChannel() async -> UInt16?

}
