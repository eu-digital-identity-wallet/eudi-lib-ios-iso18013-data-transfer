 /*
 * Copyright (c) 2023 European Commission
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */

//  MdocGATTServer.swift
import Foundation
import SwiftCBOR
import CoreBluetooth
#if canImport(UIKit)
import UIKit
#endif
import Logging
import ASN1Decoder
import MdocDataModel18013
import MdocSecurity18013

/// BLE Gatt server implementation of mdoc transfer manager
public class MdocGattServer: ObservableObject {
	var peripheralManager: CBPeripheralManager!
	var bleDelegate: Delegate!
	var remoteCentral: CBCentral!
	var stateCharacteristic: CBMutableCharacteristic!
	var server2ClientCharacteristic: CBMutableCharacteristic!
	public var deviceEngagement: DeviceEngagement?
	public var deviceRequest: DeviceRequest?
	public var sessionEncryption: SessionEncryption?
	public var docs: [DeviceResponse]!
	public var iaca: [SecCertificate]!
	public var devicePrivateKey: CoseKeyPrivate!
	public var readerName: String?
	public var qrCodeImageData: Data?
	public weak var delegate: (any MdocOfflineDelegate)?
	public var advertising: Bool = false
	public var error: Error? = nil  { willSet { handleErrorSet(newValue) }}
	public var status: TransferStatus = .initializing { willSet { handleStatusChange(newValue) } }
	var readBuffer = Data()
	var sendBuffer = [Data]()
	var numBlocks: Int = 0
	var subscribeCount: Int = 0
	
	public init(parameters: [String: Any]) throws {
		guard let (docs, devicePrivateKey, iaca) = MdocHelpers.initializeData(parameters: parameters) else {
			throw Self.makeError(code: .documents_not_provided)
		}
		self.docs = docs; self.devicePrivateKey = devicePrivateKey; self.iaca = iaca
		status = .initialized; handleStatusChange(status)
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
			if peripheral.state == .poweredOn, server.qrCodeImageData != nil { server.start() }
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
						peripheral.respond(to: requests[0], withResult: .unlikelyError);
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
	/// ``qrCodeImageData`` is set to QR code image data corresponding to the device engagement.
	public func performDeviceEngagement() {
		guard !isPreview && !isInErrorState else { logger.info("Current status is \(status)"); return }
		// Check that the class is in the right state to start the device engagement process. It will fail if the class is in any other state.
		guard status == .initialized || status == .disconnected || status == .responseSent else { error = Self.makeError(code: .unexpected_error, str: error?.localizedDescription ?? "Not initialized!"); return }
		deviceEngagement = DeviceEngagement(isBleServer: true, crv: .p256)
		sessionEncryption = nil
#if os(iOS)
		/// get qrCode image data corresponding to the device engagement
		guard let qrCodeImage = deviceEngagement!.getQrCodeImage() else { error = Self.makeError(code: .unexpected_error, str: "Null Device engagement"); return }
		qrCodeImageData = qrCodeImage.pngData()
		logger.info("Created qrCode with size \(qrCodeImageData!.count)")
#endif
		guard docs.allSatisfy({ $0.documents != nil }) else { error = Self.makeError(code: .invalidInputDocument); return }
		// Check that the peripheral manager has been authorized to use Bluetooth.
		guard peripheralManager.state != .unauthorized else { error = Self.makeError(code: .bleNotAuthorized); return }
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
		guard !isPreview && !isInErrorState else { logger.info("Current status is \(status)"); return }
		if peripheralManager.state == .poweredOn {
			logger.info("Peripheral manager powered on")
			error = nil
			// get the BLE UUID from the device engagement and truncate it to the first 4 characters (short UUID)
			guard var uuid = deviceEngagement!.ble_uuid else { logger.error("BLE initialization error"); return }
			let index = uuid.index(uuid.startIndex, offsetBy: 4)
			uuid = String(uuid[index...].prefix(4)).uppercased()
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
		qrCodeImageData = nil
		advertising = false
		subscribeCount = 0
		if status == .error { status = .initializing } 
	}
	
	func handleStatusChange(_ newValue: TransferStatus) {
		guard !isPreview && !isInErrorState else { return }
		logger.log(level: .info, "Transfer status will change to \(newValue)")
		delegate?.didChangeStatus(newValue)
		if newValue == .requestReceived {
			peripheralManager.stopAdvertising()
			deviceRequest = decodeRequestAndInformUser(requestData: readBuffer, devicePrivateKey: devicePrivateKey, readerKeyRawData: nil, handOver: BleTransferMode.QRHandover, handler: userSelected)
			if deviceRequest == nil { error = Self.makeError(code: .requestDecodeError) }
		}
		else if newValue == .initialized {
			bleDelegate = Delegate(server: self)
			logger.info("Initializing BLE peripheral manager")
			peripheralManager = CBPeripheralManager(delegate: bleDelegate, queue: nil)
			subscribeCount = 0
		} else if newValue == .disconnected && status != .disconnected {
			stop()
		}
	}
	
	var isPreview: Bool {
		ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
	}
	
	var isInErrorState: Bool { status == .error }
	
	public func userSelected(_ b: Bool, _ items: RequestItems?) {
		status = .userSelected
		if !b { error = Self.makeError(code: .userRejected) }
		if let items {
			do {
				guard let (docToSend, _, _) = try MdocHelpers.getDeviceResponseToSend(deviceRequest: deviceRequest!, deviceResponses: docs, selectedItems: items, sessionEncryption: sessionEncryption, eReaderKey: sessionEncryption!.sessionKeys.publicKey, devicePrivateKey: devicePrivateKey) else { error = Self.makeError(code: .noDocumentToReturn); return }
				guard let bytes = getSessionDataToSend(docToSend: docToSend) else { error = Self.makeError(code: .noDocumentToReturn); return }
				prepareDataToSend(bytes)
				DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { self.sendDataWithUpdates() }
			} catch { self.error = error }
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
		guard !isPreview && !isInErrorState else { return }
		guard sendBuffer.count > 0 else {
			status = .responseSent; logger.info("Finished sending BLE data")
			stop()
			return
		}
		let b = peripheralManager.updateValue(sendBuffer.first!, for: server2ClientCharacteristic, onSubscribedCentrals: [remoteCentral])
		if b, sendBuffer.count > 0 { sendBuffer.removeFirst(); sendDataWithUpdates() }
	}
	
	public func getSessionDataToSend(docToSend: DeviceResponse) -> Data? {
		do {
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
			if docToSend.documents == nil { logger.error("Could not create documents to send") }
			let cborToSend = docToSend.toCBOR(options: CBOROptions())
			let clearBytesToSend = cborToSend.encode()
			guard let cipherData = try sessionEncryption.encrypt(clearBytesToSend) else { return nil }
			let sd = SessionData(cipher_data: status == .error ? nil : cipherData, status: status == .error ? 0 : 20)
			return Data(sd.encode(options: CBOROptions()))
		} catch { self.error = error}
		return nil
	}
	
	/// Decrypt the contents of a data object and return a ``DeviceRequest`` object if the data represents a valid device request. If the data does not represent a valid device request, the function returns nil.
	/// - Parameters:
	///   - requestData: Request data passed to the mdoc holder
	///   - handler: Handler to call with the accept/reject flag
	///   - devicePrivateKey: Device private key
	///   - readerKeyRawData: reader key cbor data (if reader engagement is used)
	/// - Returns: A ``DeviceRequest`` object

	public func decodeRequestAndInformUser(requestData: Data, devicePrivateKey: CoseKeyPrivate, readerKeyRawData: [UInt8]?, handOver: CBOR, handler: @escaping (Bool, RequestItems?) -> Void) -> DeviceRequest? {
		do {
			guard let seCbor = try CBOR.decode([UInt8](requestData)) else { logger.error("Request Data is not Cbor"); return nil }
			guard var se = SessionEstablishment(cbor: seCbor) else { logger.error("Request Data cannot be decoded to session establisment"); return nil }
			if se.eReaderKeyRawData == nil, let readerKeyRawData { se.eReaderKeyRawData = readerKeyRawData }
			guard se.eReaderKey != nil else { logger.error("Reader key not available"); return nil }
			let requestCipherData = se.data
			guard let deviceEngagement else { logger.error("Device Engagement not initialized"); return nil }
			// init session-encryption object from session establish message and device engagement, decrypt data
			sessionEncryption = SessionEncryption(se: se, de: deviceEngagement, handOver: handOver)
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
			guard let requestData = try sessionEncryption.decrypt(requestCipherData) else { logger.error("Request data cannot be decrypted"); return nil }
			guard let deviceRequest = DeviceRequest(data: requestData) else { logger.error("Decrypted data cannot be decoded"); return nil }
			guard let (_, validRequestItems, errorRequestItems) = try MdocHelpers.getDeviceResponseToSend(deviceRequest: deviceRequest, deviceResponses: docs, selectedItems: nil, sessionEncryption: sessionEncryption, eReaderKey: sessionEncryption.sessionKeys.publicKey, devicePrivateKey: devicePrivateKey) else { logger.error("Valid request items nil"); return nil }
			var params: [String: Any] = [UserRequestKeys.valid_items_requested.rawValue: validRequestItems, UserRequestKeys.error_items_requested.rawValue: errorRequestItems]
			if let docR = deviceRequest.docRequests.first {
				let mdocAuth = MdocReaderAuthentication(transcript: sessionEncryption.transcript)
				if let readerAuthRawCBOR = docR.readerAuthRawCBOR, let certData = docR.readerCertificate, let x509 = try? X509Certificate(der: certData), let issName = x509.issuerDistinguishedName, let (b,reasonFailure) = try? mdocAuth.validateReaderAuth(readerAuthCBOR: readerAuthRawCBOR, readerAuthCertificate: certData, itemsRequestRawData: docR.itemsRequestRawData!, rootCerts: iaca) {
					params[UserRequestKeys.reader_certificate_issuer.rawValue] = issName
					params[UserRequestKeys.reader_auth_validated.rawValue] = b
					if let reasonFailure { params[UserRequestKeys.reader_certificate_validation_message.rawValue] = reasonFailure }
				}
			}
			self.deviceRequest = deviceRequest
			delegate?.didReceiveRequest(params, handleSelected: handler)
			return deviceRequest
		} catch { self.error = error}
		return nil
	}
	
	public static func makeError(code: ErrorCode, str: String? = nil) -> NSError {
		let errorMessage = str ?? NSLocalizedString(code.description, comment: code.description)
		logger.error(Logger.Message(unicodeScalarLiteral: errorMessage))
		return NSError(domain: "\(MdocGattServer.self)", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: errorMessage])
	}
}

