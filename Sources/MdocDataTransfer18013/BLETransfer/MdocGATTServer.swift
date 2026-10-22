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
public class MdocGattServer: @unchecked Sendable, MdocBleTransport {
	var peripheralManager: CBPeripheralManager!
	var bleDelegate: Delegate!
	var remoteCentral: CBCentral?
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
		var sendBuffer = [Data]()
	var peerState = GattPeerState()
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
            guard [.connected, .started, .requestReceived, .userSelected, .responseSent].contains(server.status),
                  server.peerState.accepts(first.central.identifier) else {
                peripheral.respond(to: first, withResult: .insufficientAuthorization)
                return
            }
            var writes: [GattPeerState.Write] = []
            for request in requests {
                guard request.central.identifier == first.central.identifier,
                      request.offset == 0, let value = request.value else {
                    peripheral.respond(to: first, withResult: .unlikelyError)
                    return
                }
                switch request.characteristic.uuid {
                case MdocServiceCharacteristic.state.uuid: writes.append(.state(value))
                case MdocServiceCharacteristic.client2Server.uuid: writes.append(.data(value))
                default:
                    peripheral.respond(to: first, withResult: .requestNotSupported)
                    return
                }
            }
            do {
                let event = try server.peerState.receive(writes, from: first.central.identifier)
                peripheral.respond(to: first, withResult: .success)
                switch event {
                case .started: server.status = .started
                case .request(let data):
                    server.status = .requestReceived
                    server.delegate?.didReceiveRequest(data)
                case .ended:
                    server.clearPeer()
                    Task { [weak server] in await server?.deleteEphemeralSessionKey() }
                    server.status = .disconnected
                case nil: break
                }
            } catch {
                peripheral.respond(to: first, withResult: .unlikelyError)
            }
        }

		public func peripheralManager(
			_ peripheral: CBPeripheralManager,
			central: CBCentral,
			didSubscribeTo characteristic: CBCharacteristic
		) {
			guard server.status == .qrEngagementReady else {
				return
			}
            let channel: GattPeerState.Channel
            switch characteristic.uuid {
            case MdocServiceCharacteristic.state.uuid: channel = .state
            case MdocServiceCharacteristic.server2Client.uuid: channel = .response
            default: return
            }
            guard server.peerState.subscribe(central.identifier, to: channel) else { return }
            server.remoteCentral = central
            if server.peerState.ready {
                server.status = .connected
                server.delegate?.didConnected(isPeripheral: false, deviceName: central.identifier.uuidString)
            }
		}

		public func peripheralManager(
			_ peripheral: CBPeripheralManager,
			central: CBCentral,
			didUnsubscribeFrom characteristic: CBCharacteristic
		) {
            guard server.peerState.centralID == central.identifier,
                  characteristic.uuid == MdocServiceCharacteristic.state.uuid ||
                  characteristic.uuid == MdocServiceCharacteristic.server2Client.uuid else { return }
            server.clearPeer()
            server.status = .disconnected
		}
	}

	/// Returns true if the peripheralManager state is poweredOn
	public var isBlePoweredOn: Bool { peripheralManager.state == .poweredOn }
	
	public var supportsL2cap: Bool { false }
	
	func buildServices(uuid: String) {
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
			clearPeer()
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

	public var isAuthorized: Bool { peripheralManager.state != .unauthorized }

	public func stopBleAdvertising() {
		if let peripheralManager, peripheralManager.isAdvertising {
			peripheralManager.stopAdvertising()
		}
		advertising = false
	}

	func deleteEphemeralSessionKey() async {
		if let pk = sessionDelegate.deviceEngagement?.privateKey {
			try? await pk.secureArea.deleteKeyBatch(id: pk.privateKeyId, startIndex: 0, batchSize: 1)
			sessionDelegate.deviceEngagement?.privateKey = nil
		}
}

public func stop() {
		stopBleAdvertising()
		sessionDelegate.qrCodePayload = nil
		clearPeer()
		Task { [weak self] in await self?.deleteEphemeralSessionKey() }
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
		let managerOptions = [CBPeripheralManagerOptionShowPowerAlertKey: true]
		peripheralManager = CBPeripheralManager(delegate: bleDelegate, queue: nil, options: managerOptions)
		clearPeer()
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

    func clearPeer() {
        remoteCentral = nil
        peerState.reset()
        sendBuffer.removeAll()
    }

    // Allows exercising failure handling without starting a Bluetooth manager.
    init(peripheralManager: CBPeripheralManager?) {
        self.peripheralManager = peripheralManager
        status = .initialized
    }

    public func sendData(_ data: Data) {
        guard let central = remoteCentral, peerState.accepts(central.identifier),
              status == .requestReceived || status == .userSelected,
              central.maximumUpdateValueLength > 1 else {
            error = MdocHelpers.makeError(code: .unexpected_error, str: "No subscribed GATT peer for response")
            return
        }
        let maxPayloadBlockSize = min(511, central.maximumUpdateValueLength - 1)
        sendBuffer = MdocHelpers.prepareDataBlocksToSend(data, blockSize: maxPayloadBlockSize)
        let generation = peerState.generation
        DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { [weak self] in
            guard let self, self.peerState.generation == generation else { return }
            self.sendDataWithUpdates()
        }
    }

    func sendDataWithUpdates() {
        guard let central = remoteCentral, peerState.accepts(central.identifier),
              let peripheralManager, let server2ClientCharacteristic else { return }
        while let block = sendBuffer.first {
            guard peripheralManager.updateValue(block, for: server2ClientCharacteristic,
                                                onSubscribedCentrals: [central]) else { return }
            sendBuffer.removeFirst()
        }
        status = .responseSent
        logger.info("Finished sending BLE data")
    }
}

#endif
