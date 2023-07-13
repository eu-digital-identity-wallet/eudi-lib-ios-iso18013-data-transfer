//
//  MdocGATTServer.swift
import Foundation
import MdocDataModel18013
import MdocSecurity18013
import CombineCoreBluetooth

public class MdocGattServer: ObservableObject {
	let peripheralManager = PeripheralManager.live
	let de: DeviceEngagement
	var sessionEncryption: SessionEncryption!
	let delegate: any MdocOfflineDelegate
	@Published var logs: String = ""
	var cancellables = Set<AnyCancellable>()
	@Published public var advertising: Bool = false
	@Published public var error: Error? = nil
	public var requireUserAccept = false
	
	public convenience init?(delegate: any MdocOfflineDelegate) {
		let de = DeviceEngagement(isBleServer: true)
		self.init(de: de, delegate: delegate)
	}
	
	public init?(de: DeviceEngagement, delegate: any MdocOfflineDelegate) {
		self.de = de
		guard de.isBleServer == true, de.ble_uuid != nil else { logger.error("Device engagement must have BLE with server mode record."); return nil }
		guard de.privateKey != nil else { logger.error("Device engagement must have private key (ephemeral holder key"); return nil }
		self.delegate = delegate
		peripheralManager.didReceiveWriteRequests
			.receive(on: DispatchQueue.main)
			.sink { [weak self] requests in
				guard let self = self else { return }
				print(requests.map({ r in
					"Write to \(r.characteristic.uuid), value: \(String(bytes: r.value ?? Data(), encoding: .utf8) ?? "<nil>")"
				}).joined(separator: "\n"), to: &self.logs)
				
				self.peripheralManager.respond(to: requests[0], withResult: .success)
			}.store(in: &cancellables)
	}
	
	func buildServices() {
		let bleUserService = CBMutableService(type: CBUUID(string: de.ble_uuid!), primary: true)
		let stateCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.state.uuid, properties: [.notify, .writeWithoutResponse], value: nil, permissions: [.writeable])
		let client2ServerCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.client2Server.uuid, properties: [.writeWithoutResponse], value: nil, permissions: [.writeable])
		let server2ClientCharacteristic = CBMutableCharacteristic(type: MdocServiceCharacteristic.server2Client.uuid, properties: [.notify], value: nil, permissions: [])
		bleUserService.characteristics = [stateCharacteristic, client2ServerCharacteristic, server2ClientCharacteristic]
		
		peripheralManager.removeAllServices()
		peripheralManager.add(bleUserService)
	}
	
	func start() {
		if peripheralManager.state == .poweredOn {
			buildServices()
			peripheralManager.startAdvertising(.init([.serviceUUIDs: [CBUUID(string: de.ble_uuid!)]]))
			advertising = true
		} else {
			// once bt is powered on, advertise
			peripheralManager.didUpdateState.first(where: { $0 == .poweredOn }).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.start()}.store(in: &cancellables)
		}
	}
	
	func stop() {
		peripheralManager.stopAdvertising()
		cancellables = []
		advertising = false
	}
}
