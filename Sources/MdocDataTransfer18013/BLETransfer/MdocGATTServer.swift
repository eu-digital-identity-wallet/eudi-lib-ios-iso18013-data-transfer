/*
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
*/

//  MdocGATTServer.swift
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
public class MdocGattServer: @unchecked Sendable, ObservableObject {
	var peripheralManager: CBPeripheralManager!
	var bleDelegate: Delegate!
	var remoteCentral: CBCentral!
	var stateCharacteristic: CBMutableCharacteristic!
	var server2ClientCharacteristic: CBMutableCharacteristic!
	public var deviceEngagement: DeviceEngagement?
	public var deviceRequest: DeviceRequest?
	public var sessionEncryption: SessionEncryption?
	public var docs: [String: IssuerSigned]!
	public var docDisplayNames: [String: [String: [String: String]]?]!
	public var docMetadata: [String: Data?]!
	public var iaca: [SecCertificate]!
	public var devicePrivateKeys: [String: CoseKeyPrivate]!
	public var dauthMethod: DeviceAuthMethod
	public var readerName: String?
	public var qrCodePayload: String?
	public weak var delegate: (any MdocOfflineDelegate)?
	public var advertising: Bool = false
	public var error: Error? = nil  { willSet { handleErrorSet(newValue) }}
	public var status: TransferStatus = .initializing { willSet { Task { @MainActor in await handleStatusChange(newValue) } } }
	public var unlockData: [String: Data]!
	public var deviceResponseBytes: Data?
	/// response metadata array
	public var responseMetadata: [Data?]!
	var readBuffer = Data()
	var sendBuffer = [Data]()
	var numBlocks: Int = 0
	var subscribeCount: Int = 0
	var initSuccess:Bool = false

	public init(parameters: InitializeTransferData) throws {
		let objs = parameters.toInitializeTransferInfo()
		self.docs = objs.documentObjects.mapValues { IssuerSigned(data: $0.bytes) }.compactMapValues { $0 }
		docMetadata = parameters.docMetadata
		docDisplayNames = objs.docDisplayNames
		self.devicePrivateKeys = objs.privateKeyObjects
		self.iaca = objs.iaca
		self.dauthMethod = objs.deviceAuthMethod
		status = .initialized
		initPeripheralManager()
		initSuccess = true
	}

	@objc(CBPeripheralManagerDelegate)
	class Delegate: NSObject, CBPeripheralManagerDelegate {
		unowned var server: MdocGattServer

		init(server: MdocGattServer) {
			self.server = server
		}

		func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
			if server.sendBuffer.count > 0 { self.server.sendDataWithUpdates() }
		}

		func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
			logger.info("CBPeripheralManager didUpdateState:")
			logger.info(peripheral.state == .poweredOn ? "Powered on" : peripheral.state == .unauthorized ? "Unauthorized" : peripheral.state == .unsupported ? "Unsupported" : "Powered off")
			if peripheral.state == .poweredOn, server.qrCodePayload != nil { server.start() }
		}

		func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
			if requests[0].characteristic.uuid == MdocServiceCharacteristic.state.uuid, let h = requests[0].value?.first {
				if h == BleTransferMode.START_REQUEST.first! {
					logger.info("Start request received to state characteristic") // --> start
					server.status = .started
					server.readBuffer.removeAll()
				}
				else if h == BleTransferMode.END_REQUEST.first! {
					guard server.status == .responseSent else {
						logger.error("State END command rejected. Not in responseSent state")
						peripheral.respond(to: requests[0], withResult: .unlikelyError)
						return
					}
					logger.info("End received to state characteristic") // --> end
					server.status = .disconnected
				}
			} else if requests[0].characteristic.uuid == MdocServiceCharacteristic.client2Server.uuid {
				for r in requests {
					guard let data = r.value, let h = data.first else { continue }
					let bStart = h == BleTransferMode.START_DATA.first!
					let bEnd = (h == BleTransferMode.END_DATA.first!)
					if data.count > 1 { server.readBuffer.append(data.advanced(by: 1)) }
					if !bStart && !bEnd { logger.warning("Not a valid request block: \(data)") }
					if bEnd { server.status = .requestReceived  }
				}
			}
			peripheral.respond(to: requests[0], withResult: .success)
		}

		public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
			guard server.status == .qrEngagementReady else { return }
			let mdocCbc = MdocServiceCharacteristic(uuid: characteristic.uuid)
			logger.info("Remote central \(central.identifier) connected for \(mdocCbc?.rawValue ?? "") characteristic")
			server.remoteCentral = central
			if characteristic.uuid == MdocServiceCharacteristic.state.uuid || characteristic.uuid == MdocServiceCharacteristic.server2Client.uuid { server.subscribeCount += 1 }
			if server.subscribeCount > 1 { server.status = .connected }
		}

		public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
			let mdocCbc = MdocServiceCharacteristic(uuid: characteristic.uuid)
			logger.info("Remote central \(central.identifier) disconnected for \(mdocCbc?.rawValue ?? "") characteristic")
		}
	}

	/// Returns true if the peripheralManager state is poweredOn
	public var isBlePoweredOn: Bool { peripheralManager.state == .poweredOn }

	/// Returns true if the peripheralManager state is unauthorized
	public var isBlePermissionDenied: Bool { peripheralManager.state == .unauthorized }

	// Create a new device engagement object and start the device engagement process.
	///
	/// ``qrCodePayload`` is set to QR code data corresponding to the device engagement.
	public func performDeviceEngagement(secureArea: any SecureArea, crv: CoseEcCurve, rfus: [String]? = nil) async throws {
		guard !isPreview && !isInErrorState else {
			logger.info("Current status is \(status)")
			return
		}
		// Check that the class is in the right state to start the device engagement process. It will fail if the class is in any other state.
		guard status == .initialized || status == .disconnected || status == .responseSent else { error = MdocHelpers.makeError(code: .unexpected_error, str: error?.localizedDescription ?? "Not initialized!"); return }
		deviceEngagement = DeviceEngagement(isBleServer: true, rfus: rfus)
		try await deviceEngagement!.makePrivateKey(crv: crv, secureArea: secureArea)
		sessionEncryption = nil
#if os(iOS)
		qrCodePayload = deviceEngagement!.getQrCodePayload()
		logger.info("Created qrCode payload: \(qrCodePayload!)")
#endif
		// todo: issuerNameSpaces is not mandatory according to specs, need to change
		guard docs.values.allSatisfy({ $0.issuerNameSpaces != nil }) else { error = MdocHelpers.makeError(code: .invalidInputDocument); return }
		// Check that the peripheral manager has been authorized to use Bluetooth.
		guard peripheralManager.state != .unauthorized else { error = MdocHelpers.makeError(code: .bleNotAuthorized); return }
		start()
	}

	func buildServices(uuid: String) {
		let bleUserService = CBMutableService(type: CBUUID(string: uuid), primary: true)
		stateCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.state.uuid, properties: [.notify, .writeWithoutResponse], value: nil, permissions: [.writeable])
		let client2ServerCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.client2Server.uuid, properties: [.writeWithoutResponse], value: nil, permissions: [.writeable])
		server2ClientCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.server2Client.uuid, properties: [.notify], value: nil, permissions: [])
		bleUserService.characteristics = [stateCharacteristic, client2ServerCharacteristic, server2ClientCharacteristic]
		peripheralManager.removeAllServices()
		peripheralManager.add(bleUserService)
	}

	func start() {
		guard !isPreview && !isInErrorState else {
			logger.info("Current status is \(status)")
			return
		}
		if peripheralManager.state == .poweredOn {
			logger.info("Peripheral manager powered on")
			error = nil
			guard let uuid = deviceEngagement?.ble_uuid else {
				logger.error("BLE initialization error")
				return
			}
			buildServices(uuid: uuid)
			let advertisementData: [String: Any] = [ CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: uuid)], CBAdvertisementDataLocalNameKey: uuid ]
			// advertise the peripheral with the short UUID
			peripheralManager.startAdvertising(advertisementData)
			advertising = true
			status = .qrEngagementReady
		} else {
			// once bt is powered on, advertise
			if peripheralManager.state == .resetting { DispatchQueue.main.asyncAfter(deadline: .now()+1) { self.start()} }
			else { logger.info("Peripheral manager powered off") }
		}
	}

	public func stop() {
		guard !isPreview else { return }
		if let peripheralManager, peripheralManager.isAdvertising { peripheralManager.stopAdvertising() }
		qrCodePayload = nil
		advertising = false
		subscribeCount = 0
		if let pk = deviceEngagement?.privateKey { Task { @MainActor in try? await pk.secureArea.deleteKey(id: pk.privateKeyId); deviceEngagement?.privateKey = nil } }
		if status == .error && initSuccess { status = .initializing }
	}

	fileprivate func initPeripheralManager() {
		guard peripheralManager == nil else { return }
		bleDelegate = Delegate(server: self)
		logger.info("Initializing BLE peripheral manager")
		peripheralManager = CBPeripheralManager(delegate: bleDelegate, queue: nil)
		subscribeCount = 0
	}

	func handleStatusChange(_ newValue: TransferStatus) async {
		guard !isPreview && !isInErrorState else { return }
		logger.log(level: .info, "Transfer status will change to \(newValue)")
		delegate?.didChangeStatus(newValue)
		if newValue == .requestReceived {
			peripheralManager.stopAdvertising()
			let decodedRes = await MdocHelpers.decodeRequestAndInformUser(deviceEngagement: deviceEngagement, docs: docs, docMetadata: docMetadata.compactMapValues { $0 }, docDisplayNames: docDisplayNames, iaca: iaca, requestData: readBuffer, devicePrivateKeys: devicePrivateKeys, dauthMethod: dauthMethod, unlockData: unlockData, readerKeyRawData: nil, handOver: BleTransferMode.QRHandover)
			switch decodedRes {
			case .success(let decoded):
				self.deviceRequest = decoded.deviceRequest
				sessionEncryption = decoded.sessionEncryption
				if decoded.isValidRequest {
					delegate?.didReceiveRequest(decoded.userRequestInfo, handleSelected: userSelected)
				} else {
					await userSelected(false, nil)
				}
			case .failure(let err):
				error = err
				return
			}
		}
		else if newValue == .initialized {
			initPeripheralManager()
		} else if newValue == .disconnected && status != .disconnected {
			stop()
		}
	}

	var isPreview: Bool {
		ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
	}

	var isInErrorState: Bool { status == .error }

	public func userSelected(_ b: Bool, _ items: RequestItems?) async {
		status = .userSelected
		let resError = await MdocHelpers.getSessionDataToSend(sessionEncryption: sessionEncryption, status: .error, docToSend: DeviceResponse(status: 0))
		var bytesToSend = try! resError.get()
		deviceResponseBytes = bytesToSend.1
		var errorToSend: Error?
		defer {
			logger.info("Prepare \(bytesToSend.0.count) bytes to send")
			prepareDataToSend(bytesToSend.0)
			DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
				self.sendDataWithUpdates()
			}
		}
		if !b { errorToSend = MdocHelpers.makeError(code: .userRejected) }
		if let items {
			do {
				let docTypeReq = deviceRequest?.docRequests.first?.itemsRequest.docType ?? ""
				guard let (drToSend, _, _, resMetadata) = try await MdocHelpers.getDeviceResponseToSend(deviceRequest: deviceRequest!, issuerSigned: docs, docDisplayNames: docDisplayNames, docMetadata: docMetadata.compactMapValues { $0 }, selectedItems: items, sessionEncryption: sessionEncryption, eReaderKey: sessionEncryption!.sessionKeys.publicKey, devicePrivateKeys: devicePrivateKeys, dauthMethod: dauthMethod, unlockData: unlockData) else {
					errorToSend = MdocHelpers.getErrorNoDocuments(docTypeReq); return
				}
				guard let dts = drToSend.documents, !dts.isEmpty else { errorToSend = MdocHelpers.getErrorNoDocuments(docTypeReq); return  }
				let dataRes = await MdocHelpers.getSessionDataToSend(sessionEncryption: sessionEncryption, status: .requestReceived, docToSend: drToSend)
				switch dataRes {
				case .success(let bytes):
					bytesToSend = bytes
					deviceResponseBytes = bytes.1
					responseMetadata = resMetadata
				case .failure(let err):
					errorToSend = err
					return
				}
			}
			catch { errorToSend = error }
			if let errorToSend { logger.error("Error sending data: \(errorToSend)")}
		}
	}

	func handleErrorSet(_ newValue: Error?) {
		guard let newValue else { return }
		status = .error
		delegate?.didFinishedWithError(newValue)
		logger.log(level: .error, "Transfer error \(newValue) (\(newValue.localizedDescription)")
	}

	func prepareDataToSend(_ msg: Data) {
		let mbs = min(511, remoteCentral.maximumUpdateValueLength-1)
		numBlocks = MdocHelpers.CountNumBlocks(dataLength: msg.count, maxBlockSize: mbs)
		logger.info("Sending response of total bytes \(msg.count) in \(numBlocks) blocks and block size: \(mbs)")
		sendBuffer.removeAll()
		// send blocks
		for i in 0..<numBlocks {
			let (block,bEnd) = MdocHelpers.CreateBlockCommand(data: msg, blockId: i, maxBlockSize: mbs)
			var blockWithHeader = Data()
			blockWithHeader.append(contentsOf: !bEnd ? BleTransferMode.START_DATA : BleTransferMode.END_DATA)
			// send actual data after header
			blockWithHeader.append(contentsOf: block)
			sendBuffer.append(blockWithHeader)
		}
	}

	func sendDataWithUpdates() {
		guard !isPreview else { return }
		guard sendBuffer.count > 0 else {
			status = .responseSent
			logger.info("Finished sending BLE data")
			stop()
			return
		}
		let b = peripheralManager.updateValue(sendBuffer.first!, for: server2ClientCharacteristic, onSubscribedCentrals: [remoteCentral])
		if b, sendBuffer.count > 0 {
			sendBuffer.removeFirst()
			sendDataWithUpdates()
		}
	}


}

