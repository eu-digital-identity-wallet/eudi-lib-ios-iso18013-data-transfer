//
//  MdocGATTServer.swift
import Foundation
import UIKit
import MdocDataModel18013
import MdocSecurity18013
import CombineCoreBluetooth

public class MdocGattServer: ObservableObject, MdocTransferManager {
	let peripheralManager = PeripheralManager.live
	var remoteCentral: Central!
	var stateCharacteristic: CBMutableCharacteristic!
	var server2ClientCharacteristic: CBMutableCharacteristic!
	public var deviceEngagement: DeviceEngagement?
	public var sessionEncryption: SessionEncryption?
	public var docs: [DeviceResponse]
	weak var delegate: (any MdocOfflineDelegate)?
	var cancellables = Set<AnyCancellable>()
	@Published public var advertising: Bool = false
	@Published public var error: Error? = nil  { willSet { handleErrorSet(newValue) }}
	@Published public var status: TransferStatus = .initializing { willSet { handleStatusChange(newValue) }}
	public var requireUserAccept = false
	public var displayDefaultAcceptUI = true
	var readBuffer = Data()
	var sendBuffer = [Data]()
	var numBlocks: Int = 0
	
	public init(docs: [DeviceResponse]) {
		self.docs = docs
		peripheralManager.didReceiveWriteRequests.receive(on: DispatchQueue.main).sink { [weak self] requests in
			guard let self = self, self.status == .connected || status == .started else {
				logger.error("Not in connected state")
				self?.peripheralManager.respond(to: requests[0], withResult: .unlikelyError);
				return
			}
			if requests[0].characteristic.uuid == MdocServiceCharacteristic.state.uuid, let h = requests[0].value?.first {
				if h == BleTransferMode.START_REQUEST.first! {
					logger.info("Start request received to state characteristic") // --> start
					status = .started
					readBuffer.removeAll()
				}
				else if h == BleTransferMode.END_REQUEST.first! {
					logger.info("End received to state characteristic") // --> end
					stop()
					status = .disconnected
				}
			} else if requests[0].characteristic.uuid == MdocServiceCharacteristic.client2Server.uuid {
				guard status == .connected || status == .started else { return }
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
		peripheralManager.centralDidSubscribeToCharacteristic.receive(on: DispatchQueue.main).sink { [weak self] central,cbc in
			guard let self = self, self.status == .qrEngagementReady else { return }
			let mdocCbc = MdocServiceCharacteristic(uuid: cbc.uuid)
			logger.info("Remote central \(central.identifier) connected for \(mdocCbc?.rawValue ?? "") characteristic: \(cbc.uuid)")
			self.remoteCentral = central
			if cbc.uuid == MdocServiceCharacteristic.server2Client.uuid { status = .connected }
		}.store(in: &cancellables)
		peripheralManager.centralDidSubscribeToCharacteristic.receive(on: DispatchQueue.main).sink { central,cbc in
			let mdocCbc = MdocServiceCharacteristic(uuid: cbc.uuid)
			logger.info("Remote central \(central.identifier) disconnected for \(mdocCbc?.rawValue ?? "") characteristic: \(cbc.uuid)")
		}.store(in: &cancellables)
		peripheralManager.readyToUpdateSubscribers.sink { [weak self] in
			guard let self = self, self.remoteCentral != nil else { return }
			self.sendDataWithUpdates() //DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { self.sendDataWithUpdates() }
		}.store(in: &cancellables)
	}
	
	public func performDeviceEngagement() -> UIImage? {
		deviceEngagement = DeviceEngagement(isBleServer: true, crv: .p256)
		guard let qrCodeImage = deviceEngagement!.getQrCodeImage() else { logger.error("Null Device engagement"); return nil }
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
		cancellables = []
		advertising = false
	}
	
	func handleStatusChange(_ newValue: TransferStatus) {
		logger.log(level: .info, "Transfer status will change to \(newValue)")
		if newValue == .requestReceived {
			guard let bytes = getMdocResponseToSend(requestData: readBuffer) else { status = .error; return }
			prepareDataToSend(bytes)
			sendDataWithUpdates()
		}
		else if newValue == .started || newValue == .connected {
			DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: { self.status = .disconnected })
		} else if newValue == .error || newValue == .disconnected {
			stop()
		}
	}
	
	func handleErrorSet(_ newValue: Error?) {
		guard let newValue else { return }
		status = .error
		logger.log(level: .error, "Transfer error \(newValue) (\(newValue.localizedDescription)")
	}
	
	func prepareDataToSend(_ msg: Data) {
		numBlocks = Helpers.CountNumBlocks(dataLength: msg.count, maxBlockSize: remoteCentral.maximumUpdateValueLength-1)
		logger.info("Sending response of total bytes \(msg.count) in \(numBlocks) blocks")
		sendBuffer.removeAll()
		// send blocks
		for i in 0..<numBlocks {
			let (block,bEnd) = Helpers.CreateBlockCommand(data: msg, blockId: i, maxBlockSize: remoteCentral.maximumUpdateValueLength-1)
			var blockWithHeader = Data()
			blockWithHeader.append(contentsOf: !bEnd ? BleTransferMode.START_DATA : BleTransferMode.END_DATA)
			// send actual data after header
			blockWithHeader.append(contentsOf: block)
			sendBuffer.append(blockWithHeader)
		}
	}
	
	func sendDataWithUpdates() {
		guard sendBuffer.count > 0 else { logger.info("Finished sending BLE data"); return }
		//logger.info("Sending \(numBlocks - sendBuffer.count + 1) out of \(numBlocks) blocks")
		let b = peripheralManager.updateValue(sendBuffer.first!, for: server2ClientCharacteristic, onSubscribedCentrals: [remoteCentral])
		if b { sendBuffer.removeFirst(); sendDataWithUpdates() }
	}
}
