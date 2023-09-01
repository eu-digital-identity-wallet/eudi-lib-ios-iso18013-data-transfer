//
//  MdocGATTServer.swift
import Foundation
import CoreBluetooth
#if canImport(UIKit)
import UIKit
#endif
import Logging
import MdocDataModel18013
import MdocSecurity18013

/// BLE Gatt server implementation of mdoc transfer manager
public class MdocGattServer: ObservableObject, MdocTransferManager {
	var peripheralManager: CBPeripheralManager!
	var bleDelegate: Delegate!
	var remoteCentral: CBCentral!
	var stateCharacteristic: CBMutableCharacteristic!
	var server2ClientCharacteristic: CBMutableCharacteristic!
	public var deviceEngagement: DeviceEngagement?
	public var deviceRequest: DeviceRequest?
	public var deviceResponseToSend: DeviceResponse?
	public var validRequestItems: [String: [String]]?
	public var sessionEncryption: SessionEncryption?
	public var docs: [DeviceResponse]!
	public var iaca: [SecCertificate]!
	public var devicePrivateKey: CoseKeyPrivate!
	@Published public var qrCodeImageData: Data?
	public weak var delegate: (any MdocOfflineDelegate)?
	//var cancellables = Set<AnyCancellable>()
	@Published public var advertising: Bool = false
	@Published public var error: Error? = nil  { willSet { handleErrorSet(newValue) }}
	@Published public var status: TransferStatus = .initializing { willSet { handleStatusChange(newValue) }}
	public var requireUserAccept = false
	var readBuffer = Data()
	var sendBuffer = [Data]()
	var numBlocks: Int = 0
	var subscribeCount: Int = 0

	public init() {
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
			logger.info(peripheral.state == .poweredOn ? "Powered on" : peripheral.state == .unauthorized ? "Unauthorized" : peripheral.state == .unsupported ? "Unsupported" : "Powered off")
			if peripheral.state == .poweredOn, server.qrCodeImageData != nil { server.start() }
		}
		
		func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
			if requests[0].characteristic.uuid == MdocServiceCharacteristic.state.uuid, let h = requests[0].value?.first {
				if h == BleTransferMode.START_REQUEST.first! {
					guard server.status == .connected else {
						logger.error("State START command rejected. Not in connected state")
						peripheral.respond(to: requests[0], withResult: .unlikelyError);
						return
					}
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
				guard server.status == .connected || server.status == .started else {
					logger.error("client2Server command rejected. Not in connected or started state")
					peripheral.respond(to: requests[0], withResult: .unlikelyError);
					return
				}
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
	
	public func initialize(parameters: [String: Any]) {
		bleDelegate = Delegate(server: self)
#if os(tvOS) || os(watchOS)
		peripheralManager = CBPeripheralManager(); peripheralManager.delegate = bleDelegate
#else
		peripheralManager = CBPeripheralManager(delegate: bleDelegate, queue: nil)
#endif

		guard let d = parameters[InitializeKeys.document_data.rawValue] as? [Data] else {
			error = Self.makeError(code: .documents_not_provided); return
		}
		// load json sample data here
		let sampleData = d.compactMap { $0.decodeJSON(type: SignUpResponse.self) }
		docs = sampleData.compactMap { $0.deviceResponse }
		devicePrivateKey = sampleData.compactMap { $0.devicePrivateKey }.first
		if docs.count == 0 { error = Self.makeError(code: .invalidInputDocument); return }
		if let i = parameters[InitializeKeys.trusted_certificates.rawValue] as? [Data] {
			iaca = i.compactMap {	SecCertificateCreateWithData(nil, $0 as CFData) }
		}
		if let b = parameters[InitializeKeys.require_user_accept.rawValue] as? Bool {
			requireUserAccept = b
		}
		status = .initialized
	}
	
	/// Returns true if the peripheralManager state is poweredOn
	public var isBlePoweredOn: Bool { peripheralManager.state == .poweredOn }

	/// Returns true if the peripheralManager state is unauthorized
	public var isBlePermissionDenied: Bool { peripheralManager.state == .unauthorized }

	// Create a new device engagement object and start the device engagement process.
	///
	/// ``qrCodeImageData`` is set to QR code image data corresponding to the device engagement.
	public func performDeviceEngagement() {
		// Check that the class is in the right state to start the device engagement process. It will fail if the class is in any other state.
		guard status == .initialized || status == .disconnected || status == .responseSent else { error = Self.makeError(code: .unexpected_error, str: error?.localizedDescription ?? "Not initialized!"); return }
		deviceEngagement = DeviceEngagement(isBleServer: true, crv: .p256)
		sessionEncryption = nil
		#if os(iOS)
		/// get qrCode image data corresponding to the device engagement
		guard let qrCodeImage = deviceEngagement!.getQrCodeImage() else { error = Self.makeError(code: .unexpected_error, str: "Null Device engagement"); return }
		qrCodeImageData = qrCodeImage.pngData()
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
		}
	}
	
	public func stop() {
		if peripheralManager.isAdvertising {	peripheralManager.stopAdvertising() }
		qrCodeImageData = nil
		advertising = false
		subscribeCount = 0
	}
	
	func handleStatusChange(_ newValue: TransferStatus) {
		logger.log(level: .info, "Transfer status will change to \(newValue)")
		delegate?.didChangeStatus(newValue)
		if newValue == .requestReceived {
			peripheralManager.stopAdvertising()
			deviceRequest = decodeRequestAndInformUser(requestData: readBuffer, devicePrivateKey: devicePrivateKey, handler: userAccepted)
			if deviceRequest == nil { error = Self.makeError(code: .requestDecodeError) }
			if requireUserAccept == false || _isDebugAssertConfiguration() { userAccepted(true) }
		}
		else if newValue == .initialized {
			subscribeCount = 0
			peripheralManager.removeAllServices()
		} else if newValue == .disconnected && status != .disconnected {
			stop()
		}
	}
	
	public func userAccepted(_ b: Bool) {
		if !b { error = Self.makeError(code: .userRejected) }
		guard let bytes = getMdocResponseToSend(deviceRequest!, eReaderKey: sessionEncryption!.sessionKeys.publicKey) else { error = Self.makeError(code: .noDocumentToReturn); return }
		prepareDataToSend(bytes)
		DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { self.sendDataWithUpdates() }
	}
	
	static func makeError(code: ErrorCode, str: String? = nil) -> NSError {
		let errorMessage = str ?? NSLocalizedString(code.description, comment: code.description)
		logger.error(Logger.Message(unicodeScalarLiteral: errorMessage))
		return NSError(domain: "\(MdocGattServer.self)", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: errorMessage])
	}
	
	func handleErrorSet(_ newValue: Error?) {
		guard let newValue else { return }
		status = .error
		delegate?.didFinishedWithError(newValue)
		logger.log(level: .error, "Transfer error \(newValue) (\(newValue.localizedDescription)")
	}
	
	func prepareDataToSend(_ msg: Data) {
		let mbs = min(511, remoteCentral.maximumUpdateValueLength-1)
		numBlocks = Helpers.CountNumBlocks(dataLength: msg.count, maxBlockSize: mbs)
		logger.info("Sending response of total bytes \(msg.count) in \(numBlocks) blocks and block size: \(mbs)")
		sendBuffer.removeAll()
		// send blocks
		for i in 0..<numBlocks {
			let (block,bEnd) = Helpers.CreateBlockCommand(data: msg, blockId: i, maxBlockSize: mbs)
			var blockWithHeader = Data()
			blockWithHeader.append(contentsOf: !bEnd ? BleTransferMode.START_DATA : BleTransferMode.END_DATA)
			// send actual data after header
			blockWithHeader.append(contentsOf: block)
			sendBuffer.append(blockWithHeader)
		}
	}
	
	func sendDataWithUpdates() {
		guard sendBuffer.count > 0 else {
			status = .responseSent; logger.info("Finished sending BLE data")
			return
		}
		let b = peripheralManager.updateValue(sendBuffer.first!, for: server2ClientCharacteristic, onSubscribedCentrals: [remoteCentral])
		if b, sendBuffer.count > 0 { sendBuffer.removeFirst(); sendDataWithUpdates() }
	}
}

