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
import SwiftCBOR
import CoreBluetooth
#if canImport(UIKit)
import UIKit
#endif
import Logging
import MdocDataModel18013
import MdocSecurity18013

/// BLE Gatt server implementation of mdoc transfer manager
public class MdocGattServer: @unchecked Sendable, MdocBleTransport {
	var peripheralManager: CBPeripheralManager!
	var bleDelegate: Delegate!
	var remoteCentral: CBCentral!
	var stateCharacteristic: CBMutableCharacteristic!
	var server2ClientCharacteristic: CBMutableCharacteristic!
	public weak var delegate: (any MdocOfflineDelegate)?

	private var sessionDelegate: any MdocOfflineDelegate {
		guard let delegate else {
			fatalError("MdocOfflineDelegate must be set before using MdocGattServer")
		}
		return delegate
	}
	public var advertising: Bool = false
	public var error: Error? = nil {
		didSet {
			handleErrorSet(error)
		}
	}
	public var status: TransferStatus = .initializing {
		didSet {
			delegate?.didChangeStatus(status)
		}
	}
	var readBuffer = Data()
	var sendBuffer = [Data]()
	var subscribeCount: Int = 0
	var initSuccess:Bool = false

	required public init() {
		status = .initialized
		initPeripheralManager()
	}
	
	@objc(CBPeripheralManagerDelegate)
	class Delegate: NSObject, CBPeripheralManagerDelegate {
		unowned var server: MdocGattServer

		init(server: MdocGattServer) {
			self.server = server
		}

		func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
			if !server.sendBuffer.isEmpty {
				self.server.sendDataWithUpdates()
			}
		}

		func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
			logger.info("CBPeripheralManager didUpdateState: \(peripheral.state == .poweredOn ? "Powered on" : peripheral.state == .unauthorized ? "Unauthorized" : peripheral.state == .unsupported ? "Unsupported" : "Powered off")")
			if peripheral.state == .poweredOn { 
				server.delegate?.didPoweredOn(isPeripheralManager: true)
				server.status = .poweredOn
			}
		}

		func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
			if requests[0].characteristic.uuid == MdocServiceCharacteristic.state.uuid, let h = requests[0].value?.first {
				if h == BleTransferMode.START_REQUEST.first! {
					logger.info("Start request received to state characteristic") // --> start
					server.status = .started
					server.readBuffer.removeAll()
				} else if h == BleTransferMode.END_REQUEST.first! {
					logger.info("End received to state characteristic (status: \(server.status))") // --> end
					server.status = .disconnected
				}
			} else if requests[0].characteristic.uuid == MdocServiceCharacteristic.client2Server.uuid {
				for r in requests {
					guard let data = r.value, let h = data.first else {
						continue
					}
					let bStart = h == BleTransferMode.START_DATA.first!
					let bEnd = (h == BleTransferMode.END_DATA.first!)
					if !bStart && !bEnd {
						logger.warning("Not a valid request block: \(data)")
						peripheral.respond(to: requests[0], withResult: .unlikelyError)
						return
					}
					if data.count > 1 {
						server.readBuffer.append(data.advanced(by: 1))
					}
					if bEnd {
						server.delegate?.didReceiveRequest(server.readBuffer)
						server.status = .requestReceived
					}
				}
			} else {
				peripheral.respond(to: requests[0], withResult: .requestNotSupported)
				return
			}
			peripheral.respond(to: requests[0], withResult: .success)
		}

		public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
			guard server.status == .qrEngagementReady else {
				return
			}
			let mdocCbc = MdocServiceCharacteristic(uuid: characteristic.uuid)
			logger.info("Remote central \(central.identifier) connected for \(mdocCbc?.rawValue ?? "") characteristic")
			server.remoteCentral = central
			if characteristic.uuid == MdocServiceCharacteristic.state.uuid || characteristic.uuid == MdocServiceCharacteristic.server2Client.uuid {
				server.subscribeCount += 1
			}
			if server.subscribeCount > 1 {
				server.delegate?.didConnected(isPeripheral: false, deviceName: central.identifier.uuidString)
				server.status = .connected
			}
		}

		public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
			let mdocCbc = MdocServiceCharacteristic(uuid: characteristic.uuid)
			logger.info("Remote central \(central.identifier) disconnected for \(mdocCbc?.rawValue ?? "") characteristic")
			server.status = .disconnected
		}
	}

	/// Returns true if the peripheralManager state is poweredOn
	public var isBlePoweredOn: Bool { peripheralManager.state == .poweredOn }

	func buildServices(uuid: String) {
		let bleUserService = CBMutableService(type: CBUUID(string: uuid), primary: true)
		stateCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.state.uuid, properties: [.notify, .writeWithoutResponse], value: nil, permissions: [.writeable])
		let client2ServerCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.client2Server.uuid, properties: [.writeWithoutResponse], value: nil, permissions: [.writeable])
		server2ClientCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.server2Client.uuid, properties: [.notify], value: nil, permissions: [])
		bleUserService.characteristics = [stateCharacteristic, client2ServerCharacteristic, server2ClientCharacteristic]
		peripheralManager.removeAllServices()
		peripheralManager.add(bleUserService)
	}

	public func startBleAdvertising() {
		guard !isInErrorState else {
			logger.info("Current status is \(status)")
			return
		}
		if peripheralManager.state == .poweredOn {
			logger.info("Peripheral manager powered on")
			error = nil
			guard let serviceUuid = sessionDelegate.deviceEngagement?.ble_uuid else {
				logger.error("BLE initialization error")
				return
			}
			buildServices(uuid: serviceUuid)
			let advertisementData: [String: Any] = [ CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: serviceUuid)], CBAdvertisementDataLocalNameKey: serviceUuid ]
			// advertise the peripheral with the short UUID
			peripheralManager.startAdvertising(advertisementData)
			advertising = true
			status = .qrEngagementReady
		} else {
		// once bt is powered on, advertise
		if peripheralManager.state == .resetting {
			DispatchQueue.main.asyncAfter(deadline: .now()+1) {
				self.startBleAdvertising()
			}
		} else {
			logger.info("Peripheral manager powered off")
		}
		}
	}

	public var isAuthorized: Bool { peripheralManager.state != .unauthorized }
	
	public func stopBleAdvertising() {
		if let peripheralManager, peripheralManager.isAdvertising {
			peripheralManager.stopAdvertising()
		}
		advertising = false
	}

	public func stop() {
		stopBleAdvertising()
		sessionDelegate.qrCodePayload = nil
		subscribeCount = 0
		if let pk = sessionDelegate.deviceEngagement?.privateKey {
			Task { @MainActor in
				try? await pk.secureArea.deleteKeyBatch(id: pk.privateKeyId, startIndex: 0, batchSize: 1)
				sessionDelegate.deviceEngagement?.privateKey = nil
			}
		}
		if status == .error {
			status = .initializing
		}
	}

	func initPeripheralManager() {
		guard peripheralManager == nil else {
			return
		}
		bleDelegate = Delegate(server: self)
		logger.info("Initializing BLE peripheral manager")
		peripheralManager = CBPeripheralManager(delegate: bleDelegate, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
		subscribeCount = 0
	}

	var isInErrorState: Bool { status == .error }
	func handleErrorSet(_ newValue: Error?) {
		guard let newValue else {
			return
		}
		status = .error
		delegate?.didFinishedWithError(newValue)
		logger.log(level: .error, "Transfer error \(newValue) (\(newValue.localizedDescription)")
	}

	public func sendData(_ data: Data) {
			sendBuffer = MdocHelpers.prepareDataBlocksToSend(data, blockSize: min(511, remoteCentral.maximumUpdateValueLength-1))
			DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
				self.sendDataWithUpdates()
			}
	}

	func sendDataWithUpdates() {
		guard !sendBuffer.isEmpty else {
			status = .responseSent
			logger.info("Finished sending BLE data")
			return
		}
		let b = peripheralManager.updateValue(sendBuffer.first!, for: server2ClientCharacteristic, onSubscribedCentrals: [remoteCentral])
		if b, sendBuffer.count > 0 {
			sendBuffer.removeFirst()
			sendDataWithUpdates()
		}
	}

}

