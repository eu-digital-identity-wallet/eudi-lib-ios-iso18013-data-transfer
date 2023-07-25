//
//  MdocGATTServer.swift
import Foundation
import SwiftCBOR
import UIKit
import Logging
import MdocDataModel18013
import MdocSecurity18013
import CombineCoreBluetooth

public class MdocGattServer: ObservableObject, MdocTransferManager {
	let peripheralManager = PeripheralManager.live
	var remoteCentral: Central!
	var stateCharacteristic: CBMutableCharacteristic!
	var server2ClientCharacteristic: CBMutableCharacteristic!
	public var deviceEngagement: DeviceEngagement?
	var deviceRequest: DeviceRequest?
	public var deviceResponseToSend: DeviceResponse?
	public var validRequestItems: Set<String>? = Set()
	public var sessionEncryption: SessionEncryption?
	public var docs: [DeviceResponse]
	public var iaca: Data
	public weak var delegate: (any MdocOfflineDelegate)?
	var cancellables = Set<AnyCancellable>()
	@Published public var advertising: Bool = false
	@Published public var error: Error? = nil  { willSet { handleErrorSet(newValue) }}
	@Published public var status: TransferStatus = .initializing { willSet { handleStatusChange(newValue) }}
	@Published public var statusDescription: String = ""
	public var requireUserAccept = false
	var readBuffer = Data()
	var sendBuffer = [Data]()
	var numBlocks: Int = 0
	// default delegate
	@Published public var hasRequestPresented: Bool = false
	@Published public var requestItemsMessage: String = ""
	@Published public var hasError: Bool = false
	@Published public var errorMessage: String = ""
	public var handleAccept: (Bool) -> Void = { _ in }

	public init(docs: [DeviceResponse], iaca: Data) {
		self.docs = docs
		self.iaca = iaca
		peripheralManager.didReceiveWriteRequests.receive(on: DispatchQueue.main).sink { [weak self] requests in
			guard let self = self else { return }
			if requests[0].characteristic.uuid == MdocServiceCharacteristic.state.uuid, let h = requests[0].value?.first {
				if h == BleTransferMode.START_REQUEST.first! {
					guard status == .connected else {
						logger.error("State START command rejected. Not in connected state")
						self.peripheralManager.respond(to: requests[0], withResult: .unlikelyError);
						return
					}
					logger.info("Start request received to state characteristic") // --> start
					status = .started
					readBuffer.removeAll()
				}
				else if h == BleTransferMode.END_REQUEST.first! {
					guard status == .responseSent else {
						logger.error("State END command rejected. Not in responseSent state")
						self.peripheralManager.respond(to: requests[0], withResult: .unlikelyError);
						return
					}
					logger.info("End received to state characteristic") // --> end
					status = .disconnected
				}
			} else if requests[0].characteristic.uuid == MdocServiceCharacteristic.client2Server.uuid {
				guard status == .connected || status == .started else {
					logger.error("client2Server command rejected. Not in connected or started state")
					self.peripheralManager.respond(to: requests[0], withResult: .unlikelyError);
					return
				}
				for r in requests {
					guard let data = r.value, let h = data.first else { continue }
					let bStart = h == BleTransferMode.START_DATA.first!
					let bEnd = (h == BleTransferMode.END_DATA.first!)
					if data.count > 1 { readBuffer.append(data.advanced(by: 1)) }
					if !bStart && !bEnd { logger.warning("Not a valid request block: \(data)") }
					if bEnd { status = .requestReceived  }
				}
			}
			self.peripheralManager.respond(to: requests[0], withResult: .success)
		}.store(in: &cancellables)
		
		peripheralManager.centralDidSubscribeToCharacteristic.receive(on: DispatchQueue.main).receive(on: DispatchQueue.main).sink { [weak self] central,cbc in
			guard let self = self, self.status == .qrEngagementReady else { return }
			let mdocCbc = MdocServiceCharacteristic(uuid: cbc.uuid)
			logger.info("Remote central \(central.identifier) connected for \(mdocCbc?.rawValue ?? "") characteristic")
			self.remoteCentral = central
			if cbc.uuid == MdocServiceCharacteristic.server2Client.uuid { status = .connected }
		}.store(in: &cancellables)
		
		peripheralManager.centralDidSubscribeToCharacteristic.receive(on: DispatchQueue.main).sink { central,cbc in
			let mdocCbc = MdocServiceCharacteristic(uuid: cbc.uuid)
			logger.info("Remote central \(central.identifier) disconnected for \(mdocCbc?.rawValue ?? "") characteristic")
		}.store(in: &cancellables)
		
	//	peripheralManager.readyToUpdateSubscribers.receive(on: DispatchQueue.main).sink { [weak self] in
	//		guard let self = self, self.remoteCentral != nil else { return }
	//		self.sendDataWithUpdates()
	//	}.store(in: &cancellables)
	}
	
	public func performDeviceEngagement() -> UIImage? {
		deviceEngagement = DeviceEngagement(isBleServer: true, crv: .p256)
		sessionEncryption = nil
		guard let qrCodeImage = deviceEngagement!.getQrCodeImage() else { error = Self.makeError(code: .unexpected_error, str: "Null Device engagement"); return nil }
		guard docs.allSatisfy({ $0.documents != nil }) else { error = Self.makeError(code: .invalidInputDocument); return nil }
		status = .qrEngagementReady
		start()
		return qrCodeImage
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
			error = nil; errorMessage = ""
			guard var uuid = deviceEngagement!.ble_uuid else { logger.error("BLE initialization error"); return }
			let index = uuid.index(uuid.startIndex, offsetBy: 4)
			uuid = String(uuid[index...].prefix(4)).uppercased()
			buildServices(uuid: uuid)
			peripheralManager.startAdvertising(.init([.serviceUUIDs: [CBUUID(string: uuid)]]))
			advertising = true
		} else {
			// once bt is powered on, advertise
			peripheralManager.didUpdateState.first(where: { $0 == .poweredOn }).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.start()}.store(in: &cancellables)
		}
	}
	
	public func stop() {
		peripheralManager.stopAdvertising()
		peripheralManager.removeAllServices()
		advertising = false
	}
	
	func handleStatusChange(_ newValue: TransferStatus) {
		logger.log(level: .info, "Transfer status will change to \(newValue)")
		delegate?.didChangeStatus(newValue)
		statusDescription = "\(newValue)"
		if newValue == .requestReceived {
			peripheralManager.stopAdvertising()
			deviceRequest = decodeRequestAndInformUser(requestData: readBuffer, handler: userAccepted)
			if deviceRequest == nil { error = Self.makeError(code: .requestDecodeError) }
			if requireUserAccept == false { userAccepted(true) }
		}
		else if newValue == .started {
			DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: { self.status = .disconnected })
		} else if newValue == .disconnected {
			stop()
		}
	}
	
	public func userAccepted(_ b: Bool) {
		if !b { error = Self.makeError(code: .userRejected) }
		guard let bytes = getMdocResponseToSend(deviceRequest!, eReaderKey: sessionEncryption!.sessionKeys.publicKey) else { error = Self.makeError(code: .noDocumentToReturn); return }
		prepareDataToSend(bytes)
		DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { self.sendDataWithUpdates() }
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
		peripheralManager.updateValue(sendBuffer.first!, for: server2ClientCharacteristic, onSubscribedCentrals: [remoteCentral])
			.sink(receiveCompletion: { [weak self] c in
				guard let self = self else { return }
				if case .finished = c {
					if sendBuffer.count > 0 { sendBuffer.removeFirst(); DispatchQueue.main.async { self.sendDataWithUpdates() } }
				} else { status = .disconnected }
			}, receiveValue: {})
			.store(in: &cancellables)
	}
}

// quick implementation of delegate used for testing
extension MdocGattServer: MdocOfflineDelegate {
	
	public func didChangeStatus(_ newStatus: MdocDataTransfer18013.TransferStatus) {
	}
	
	public func didReceiveRequest(_ request: [String], handleAccept: @escaping (Bool) -> Void) {
		print(request.toCBOR(options: CBOROptions()).description)
		hasRequestPresented = true
		self.handleAccept = handleAccept
		requestItemsMessage = request.map { NSLocalizedString($0, comment: "") }.joined(separator: "\n")
	}
	
	public func didFinishedWithError(_ error: Error) {
		hasError = true
		errorMessage = error.localizedDescription
	}
}
