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
#if !os(watchOS)
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
/// Mutable transport state is confined to the main queue, matching CoreBluetooth callbacks.
/// Public synchronous access dispatches to main when needed. Callers must not block main
/// while waiting for a background transport call. Delegate-owned state must follow the same rule.
public class MdocGattServer: @unchecked Sendable, MdocBleTransport {
	private var peripheralManager: CBPeripheralManager!
	private var bleDelegate: Delegate!
	private var remoteCentral: CBCentral?
	private var stateCharacteristic: CBMutableCharacteristic!
	private var server2ClientCharacteristic: CBMutableCharacteristic!
	private weak var storedDelegate: (any MdocOfflineDelegate)?
	public var delegate: (any MdocOfflineDelegate)? {
		get { BleMainQueue.sync { storedDelegate } }
		set { BleMainQueue.sync { storedDelegate = newValue } }
	}

	private var sessionDelegate: any MdocOfflineDelegate {
		guard let delegate else {
			fatalError("MdocOfflineDelegate must be set before using MdocGattServer")
		}
		return delegate
	}
	private var storedAdvertising = false
	public var advertising: Bool {
		get { BleMainQueue.sync { storedAdvertising } }
		set { BleMainQueue.sync { storedAdvertising = newValue } }
	}
	public var error: Error? {
		get { BleMainQueue.sync { storedError } }
		set { BleMainQueue.sync { storedError = newValue } }
	}
	private var storedError: Error? = nil {
		didSet {
			handleErrorSet(error)
		}
	}
	public var status: TransferStatus {
		get { BleMainQueue.sync { storedStatus } }
		set { BleMainQueue.sync { storedStatus = newValue } }
	}
	private var storedStatus: TransferStatus = .initializing {
		didSet {
			delegate?.didChangeStatus(status)
		}
	}
	private var session = GattSession()
	private var sendBuffer = [Data]()
	private var initSuccess:Bool = false

	required public init() {
		BleMainQueue.sync {
			status = .initialized
			initPeripheralManager()
		}
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
			let stateDescription: String
			switch peripheral.state {
			case .poweredOn:
				stateDescription = "Powered on"
			case .unauthorized:
				stateDescription = "Unauthorized"
			case .unsupported:
				stateDescription = "Unsupported"
			default:
				stateDescription = "Powered off"
			}
			logger.info("CBPeripheralManager didUpdateState: \(stateDescription)")
			if peripheral.state == .poweredOn {
				server.delegate?.didPoweredOn(isPeripheralManager: true)
				server.status = .poweredOn
			}
		}

        func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            guard let first = requests.first else { return }
            for request in requests {
                guard let characteristic = Self.sessionCharacteristic(request.characteristic),
                      let value = request.value, request.offset == 0 else {
                    peripheral.respond(to: first, withResult: .requestNotSupported)
                    return
                }
                do {
                    let result = try server.session.write(value, characteristic: characteristic,
                        central: request.central.identifier, status: server.status)
                    switch result {
                    case .started: server.status = .started
                    case .ended: server.endSession()
                    case .fragment: break
                    case let .request(data):
                        let generation = server.session.generation

                        server.status = .requestReceived
                        guard server.session.generation == generation else {

                            peripheral.respond(to: first, withResult: .writeNotPermitted)

                            return

                        }

                        server.delegate?.didReceiveRequest(data)
                    }
                } catch {
                    peripheral.respond(to: first, withResult: .writeNotPermitted)
                    return
                }
            }
            peripheral.respond(to: first, withResult: .success)
        }

        private static func sessionCharacteristic(_ characteristic: CBCharacteristic) -> GattSession.Characteristic? {
            switch MdocServiceCharacteristic(uuid: characteristic.uuid) {
            case .state: return .state
            case .server2Client: return .serverToClient
            case .client2Server: return .clientToServer
            case nil: return nil
            }
        }

        public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                      didSubscribeTo characteristic: CBCharacteristic) {
            guard let kind = Self.sessionCharacteristic(characteristic),
                  server.session.subscribe(kind, central: central.identifier, status: server.status) else { return }
            server.remoteCentral = central
            server.stopBleAdvertising()
            if server.session.ready {
                server.status = .connected
                server.delegate?.didConnected(isPeripheral: false, deviceName: central.identifier.uuidString)
            }
        }

        public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                      didUnsubscribeFrom characteristic: CBCharacteristic) {
            guard let kind = Self.sessionCharacteristic(characteristic),
                  server.session.acceptsUnsubscribe(kind, central: central.identifier) else { return }
            server.endSession()
        }

	}

	/// Returns true if the peripheralManager state is poweredOn
	public var isBlePoweredOn: Bool { BleMainQueue.sync { peripheralManager.state == .poweredOn } }

	public var supportsL2cap: Bool { false }

	private func buildServices(uuid: String) {
		let bleUserService = CBMutableService(type: CBUUID(string: uuid), primary: true)
		let stateProperties: CBCharacteristicProperties = [.notify, .writeWithoutResponse]
		let clientToServerProperties: CBCharacteristicProperties = [.writeWithoutResponse]
		let serverToClientProperties: CBCharacteristicProperties = [.notify]
		let writablePermissions: CBAttributePermissions = [.writeable]
		stateCharacteristic = CBMutableCharacteristic(
			type: MdocServiceCharacteristic.state.uuid,
			properties: stateProperties,
			value: nil,
			permissions: writablePermissions
		)
		let client2ServerCharacteristic = CBMutableCharacteristic(
			type: MdocServiceCharacteristic.client2Server.uuid,
			properties: clientToServerProperties,
			value: nil,
			permissions: writablePermissions
		)
		server2ClientCharacteristic = CBMutableCharacteristic(
			type: MdocServiceCharacteristic.server2Client.uuid,
			properties: serverToClientProperties,
			value: nil,
			permissions: []
		)
		bleUserService.characteristics = [stateCharacteristic, client2ServerCharacteristic, server2ClientCharacteristic]
		peripheralManager.removeAllServices()
		peripheralManager.add(bleUserService)
	}

	public func startBleAdvertising() {
		BleMainQueue.sync {
			guard !isInErrorState, session.centralID == nil else {
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
				let advertisedServiceUuids = [CBUUID(string: serviceUuid)]
				let advertisementData: [String: Any] = [
					CBAdvertisementDataServiceUUIDsKey: advertisedServiceUuids,
					CBAdvertisementDataLocalNameKey: serviceUuid
				]
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
	}

	public var isAuthorized: Bool { BleMainQueue.sync { peripheralManager.state != .unauthorized } }

	public func stopBleAdvertising() {
		BleMainQueue.sync {
			if let peripheralManager, peripheralManager.isAdvertising {
				peripheralManager.stopAdvertising()
			}
			advertising = false
		}
	}

    private func deleteEphemeralSessionKey() {
        guard let key = sessionDelegate.deviceEngagement?.privateKey else { return }
        // Detach this engagement's key before asynchronous deletion, so teardown
        // cannot delete a key belonging to a subsequent presentation.
        sessionDelegate.deviceEngagement?.privateKey = nil
        Task {
            try? await key.secureArea.deleteKeyBatch(id: key.privateKeyId, startIndex: 0, batchSize: 1)
        }
    }

    private func clearSession() {
        session.reset()
        remoteCentral = nil
        sendBuffer.removeAll()
    }

    private func endSession() {
        stopBleAdvertising()
        clearSession()
        deleteEphemeralSessionKey()
        status = .disconnected
    }

    public func stop() {
		BleMainQueue.sync {
			stopBleAdvertising()
			sessionDelegate.qrCodePayload = nil
			clearSession()
			deleteEphemeralSessionKey()
			if status == .error {
				status = .initializing
			}
		}
	}

	private func initPeripheralManager() {
		guard peripheralManager == nil else {
			return
		}
		bleDelegate = Delegate(server: self)
		logger.info("Initializing BLE peripheral manager")
		let managerOptions = [CBPeripheralManagerOptionShowPowerAlertKey: true]
		peripheralManager = CBPeripheralManager(delegate: bleDelegate, queue: nil, options: managerOptions)
		clearSession()
	}

	private var isInErrorState: Bool { status == .error }
	private func handleErrorSet(_ newValue: Error?) {
		guard let newValue else {
			return
		}
		status = .error
		delegate?.didFinishedWithError(newValue)
		logger.log(level: .error, "Transfer error \(newValue) (\(newValue.localizedDescription)")
	}

	public func sendData(_ data: Data) {
		BleMainQueue.sync {
			guard let remoteCentral else {
				error = MdocHelpers.makeError(code: .unexpected_error, str: "No remote central available for response")
				return
			}
			let maxPayloadBlockSize = min(511, remoteCentral.maximumUpdateValueLength - 1)
			sendBuffer = MdocHelpers.prepareDataBlocksToSend(data, blockSize: maxPayloadBlockSize)
			let generation = session.generation
			DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
				guard self.session.generation == generation else { return }
				self.sendDataWithUpdates()
			}
		}
	}

	private func sendDataWithUpdates() {
		guard !sendBuffer.isEmpty else {
			status = .responseSent
			logger.info("Finished sending BLE data")
			return
		}
		guard let remoteCentral else {
			error = MdocHelpers.makeError(code: .unexpected_error, str: "No remote central available for response")
			return
		}
		let firstPendingBlock = sendBuffer.first!
		let isUpdateAccepted = peripheralManager.updateValue(
			firstPendingBlock,
			for: server2ClientCharacteristic,
			onSubscribedCentrals: [remoteCentral]
		)
		if isUpdateAccepted, sendBuffer.count > 0 {
			sendBuffer.removeFirst()
			sendDataWithUpdates()
		}
	}

}

#endif
