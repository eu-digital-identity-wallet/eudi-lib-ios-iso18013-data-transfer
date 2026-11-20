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

import CoreBluetooth
import Foundation
import os

/// Mutable transport state is confined to the main queue, matching CoreBluetooth callbacks.
/// Public synchronous access dispatches to main when needed. Callers must not block main
/// while waiting for a background transport call. Delegate-owned state must follow the same rule.
public class MdocGattCentral: NSObject, MdocBleTransport, @unchecked Sendable {
	private var centralManager: CBCentralManager!
	private var peripheral: CBPeripheral?
	// Internal state is also used by tests, which must access it on the main queue.
	var writeCharacteristic: CBCharacteristic?
	var readCharacteristic: CBCharacteristic?
	var stateCharacteristic: CBCharacteristic?
	var hasReaderIdentity = false
	private var identityTimeout: DispatchWorkItem?
	private var rejectedCandidates: [UUID: Date] = [:]
	var didSendStartRequest = false
	var maximumCharacteristicSize: Int?
	var readBuffer = Data()
	var sendBuffer = [Data]()
	public var error: Error? {
		get { BleMainQueue.sync { storedError } }
		set { BleMainQueue.sync { storedError = newValue } }
	}
	private var storedError: Error? = nil {
		didSet {
			if let error {
				status = .error
				delegate?.didFinishedWithError(error)
			}
		}
	}
	private weak var storedDelegate: (any MdocOfflineDelegate)?
	public var delegate: (any MdocOfflineDelegate)? {
		get { BleMainQueue.sync { storedDelegate } }
		set { BleMainQueue.sync { storedDelegate = newValue } }
	}
	public var status: TransferStatus {
		get { BleMainQueue.sync { storedStatus } }
		set { BleMainQueue.sync { storedStatus = newValue } }
	}
	private var storedStatus: TransferStatus = .initialized {
		didSet {
			delegate?.didChangeStatus(status)
		}
	}

	required public override convenience init() {
		self.init(initializeBluetooth: true)
	}

	init(initializeBluetooth: Bool) {
		super.init()
		guard initializeBluetooth else { return }
		BleMainQueue.sync {
			centralManager = CBCentralManager(delegate: self, queue: nil)
			status = .initialized
			if isBlePoweredOn {
				handleCentralPoweredOn()
			}
		}
	}

	public func stop() {
		BleMainQueue.sync {
			centralManager?.stopScan()
			rejectedCandidates.removeAll()
			disconnectFromDevice()
		}
	}

    public func startBleAdvertising() {
    }

    public func stopBleAdvertising() {
    }

    public var isBlePoweredOn: Bool { BleMainQueue.sync { centralManager.state == .poweredOn } }

	public var isAuthorized: Bool {
		BleMainQueue.sync { centralManager.state != .unauthorized }
	}
	public var supportsL2cap: Bool { false }

	private func handleCentralPoweredOn() {
		delegate?.didPoweredOn(isPeripheralManager: false)
		status = .poweredOn
		guard let serviceUuid = delegate?.deviceEngagement?.ble_uuid else {
			logger.error("BLE initialization error")
			error = MdocHelpers.makeError(code: .deviceEngagementMissing)
			return
		}
		centralManager.scanForPeripherals(withServices: [CBUUID(string: serviceUuid)])
		logger.info("Started scanning for peripherals with service UUID \(serviceUuid)")
		status = .qrEngagementReady
	}

	private func tryStartRequestIfReady() {
		guard hasReaderIdentity, !didSendStartRequest, writeCharacteristic != nil, let peripheral, let readCharacteristic, let stateCharacteristic else {
			return
		}
		peripheral.setNotifyValue(true, for: readCharacteristic)
		peripheral.setNotifyValue(true, for: stateCharacteristic)
		peripheral.writeValue(Data(BleTransferMode.START_REQUEST), for: stateCharacteristic, type: .withoutResponse)
		didSendStartRequest = true
		status = .started
	}

	public func disconnectFromDevice() {
		BleMainQueue.sync {
			if didSendStartRequest, let stateCharacteristic {
				peripheral?.writeValue(Data(BleTransferMode.END_REQUEST), for: stateCharacteristic, type: .withoutResponse)
			}
			disconnect()
		}
	}

	private func disconnect() {
		identityTimeout?.cancel()
		identityTimeout = nil
		let previous = peripheral
		peripheral = nil
		previous?.delegate = nil
		if let previous { centralManager?.cancelPeripheralConnection(previous) }
		hasReaderIdentity = false
		didSendStartRequest = false
		writeCharacteristic = nil
		readCharacteristic = nil
		stateCharacteristic = nil
		maximumCharacteristicSize = nil
		readBuffer.removeAll()
		sendBuffer.removeAll()
	}

	// Candidate failures are recoverable; the terminal error callback would end engagement.
	func rejectReaderCandidate() {
		BleMainQueue.sync {
			if let peripheral { rejectedCandidates[peripheral.identifier] = Date().addingTimeInterval(30) }
			disconnect()
			logger.error("Reader Ident verification or discovery failed; resuming discovery")
			guard centralManager?.state == .poweredOn,
				let uuid = delegate?.deviceEngagement?.ble_uuid else { return }
			// Keep receiving foreground advertisements so a candidate can be retried after its cooldown.
			// didDiscover filters cooling-down candidates and prevents concurrent connections.
			centralManager?.scanForPeripherals(
				withServices: [CBUUID(string: uuid)],
				options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
			)
			status = .qrEngagementReady
		}
	}

	private func scheduleIdentityTimeout() {
		identityTimeout?.cancel()
		let timeout = DispatchWorkItem { [weak self] in
			guard let self, self.peripheral != nil, !self.hasReaderIdentity else { return }
			self.rejectReaderCandidate()
		}
		identityTimeout = timeout
		DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
	}

	public func sendData(_ data: Data) {
		BleMainQueue.sync {
			guard status == .requestReceived else {
				logger.info("Unexpected write in status \(status)")
				return
			}
			status = .userSelected
			let blockSize = max((maximumCharacteristicSize ?? 1) - 1, 1)
			sendBuffer = MdocHelpers.prepareDataBlocksToSend(data, blockSize: blockSize)
			writeNextBlock()
		}
	}

	private func writeNextBlock() {
		guard !sendBuffer.isEmpty else {
			status = .responseSent
			logger.info("Finished sending BLE data")
			status = .disconnected
			return
		}
		guard let writeCharacteristic else {
			error = MdocHelpers.makeError(code: .bleNotSupported)
			return
		}
		peripheral?.writeValue(sendBuffer.first!, for: writeCharacteristic, type: .withoutResponse)
		if !sendBuffer.isEmpty { sendBuffer.removeFirst() }
	}

	private func getCharacteristic(
		list: [CBCharacteristic],
		mdocChar: MdocServiceCharacteristic,
		properties: [CBCharacteristicProperties],
		description: String
	) throws -> CBCharacteristic? {
		if let characteristic = list.first(where: { $0.uuid == mdocChar.uuid }) {
			for property in properties where !characteristic.properties.contains(property) {
				throw makePeripheralError("Missing required \(description) properties for \(mdocChar.description)")
			}
			return characteristic
		} else {
			logger.info("Characteristic \(mdocChar.description) with UUID \(mdocChar.uuid.uuidString) not found")
		}
		return nil
	}

	private func processCharacteristics(
		peripheral: CBPeripheral,
		characteristics: [CBCharacteristic]
	) throws {
		let stateProperties: [CBCharacteristicProperties] = [.notify, .writeWithoutResponse]
		let writeProperties: [CBCharacteristicProperties] = [.writeWithoutResponse]
		let readProperties: [CBCharacteristicProperties] = [.notify]
		let readerIdentityProperties: [CBCharacteristicProperties] = [.read]
		stateCharacteristic = try getCharacteristic(
			list: characteristics,
			mdocChar: .state,
			properties: stateProperties,
			description: "notify, writeWithoutResponse"
		)
		writeCharacteristic = try getCharacteristic(
			list: characteristics,
			mdocChar: .client2Server,
			properties: writeProperties,
			description: "writeWithoutResponse"
		)
		readCharacteristic = try getCharacteristic(
			list: characteristics,
			mdocChar: .server2Client,
			properties: readProperties,
			description: "notify"
		)
		guard let readerIdent = try getCharacteristic(
			list: characteristics,
			mdocChar: .readerIdent,
			properties: readerIdentityProperties,
			description: "read"
		), stateCharacteristic != nil, writeCharacteristic != nil, readCharacteristic != nil else {
			throw makePeripheralError("Missing required BLE characteristic")
		}
		peripheral.readValue(for: readerIdent)
		let negotiatedMaximumCharacteristicSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
		maximumCharacteristicSize = min(negotiatedMaximumCharacteristicSize - 3, 512)
		tryStartRequestIfReady()
	}

	/// The reader sends one byte on the State characteristic. 0x02 ends the session.
	static func checkEndRequest(state data: Data) throws {
		guard data.count == 1 else { throw MdocHelpers.makeError(code: .bleInvalidStateLength) }
		guard data.first == BleTransferMode.END_REQUEST.first else { throw MdocHelpers.makeError(code: .bleInvalidStateByte) }
	}

	private func processData(
		peripheral: CBPeripheral,
		characteristic: CBCharacteristic
	) throws {
		guard peripheral === self.peripheral else { return }
		if characteristic.uuid == MdocServiceCharacteristic.readerIdent.uuid {
			guard ReaderIdent.matches(characteristic.value, engagement: delegate?.deviceEngagement?.qrCoded) else {
				rejectReaderCandidate()
				return
			}
			hasReaderIdentity = true
			identityTimeout?.cancel()
			identityTimeout = nil
			tryStartRequestIfReady()
			return
		}
		guard hasReaderIdentity, didSendStartRequest else { return }
		if var data = characteristic.value {
			let characteristicDescription =
				MdocServiceCharacteristic(uuid: characteristic.uuid)?.description
				?? characteristic.uuid.uuidString
			logger.info("Processing \(data.count) bytes for \(characteristicDescription)")
			switch characteristic.uuid {
			case MdocServiceCharacteristic.state.uuid:
				do {
					try Self.checkEndRequest(state: data)
					status = .disconnected
				} catch let stateError {
					logger.debug("Invalid state frame (\(data.count) bytes)")
					error = stateError
				}
			case MdocServiceCharacteristic.server2Client.uuid:
				let firstByte = data.popFirst()
				readBuffer.append(data)
				switch firstByte {
				case .none:
					error = MdocHelpers.makeError(code: .bleNoData)
				case BleTransferMode.END_DATA.first!: // 0x00:
					delegate?.didReceiveRequest(readBuffer)
					status = .requestReceived
				case BleTransferMode.START_DATA.first!: break
				case let .some(byte):
					logger.error("Unknown data prefix \(byte)")
					error = MdocHelpers.makeError(code: .bleNotSupported)
				}
			case let uuid:
				logger.error("Unknown characteristic \(uuid)")
				error = MdocHelpers.makeError(code: .bleNotSupported)
			}
		} else {
			error = MdocHelpers.makeError(code: .bleNoData)
		}
	}
}

extension MdocGattCentral: CBCentralManagerDelegate {
	public func centralManagerDidUpdateState(_ central: CBCentralManager) {
		if central.state == .poweredOn {
			handleCentralPoweredOn()
		} else {
			error = MdocHelpers.makeError(code: .bleNotSupported)
		}
	}

	public func centralManager(
		_: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData _: [String: Any],
		rssi _: NSNumber
	) {
		guard self.peripheral == nil else { return }
		rejectedCandidates = rejectedCandidates.filter { $0.value > Date() }
		guard rejectedCandidates[peripheral.identifier] == nil else { return }
		logger.info("Discovered peripheral")
		peripheral.delegate = self
		self.peripheral = peripheral
		centralManager?.connect(peripheral, options: nil)
		centralManager?.stopScan()
		scheduleIdentityTimeout()
	}

	public func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		guard peripheral === self.peripheral else { return }
		rejectReaderCandidate()
	}

	public func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		guard peripheral === self.peripheral else { return }
		if !hasReaderIdentity {
			rejectReaderCandidate()
		} else {
			disconnect()
			status = .disconnected
		}
	}

	public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
		guard peripheral === self.peripheral else { return }
		guard let serviceUuid = delegate?.deviceEngagement?.ble_uuid else {
			rejectReaderCandidate()
			return
		}
		peripheral.discoverServices([CBUUID(string: serviceUuid)])
		delegate?.didConnected(isPeripheral: true, deviceName: peripheral.name)
		status = .connected
		tryStartRequestIfReady()
	}
}

extension MdocGattCentral: CBPeripheralDelegate {
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard peripheral === self.peripheral else { return }
		guard error == nil, let services = peripheral.services, !services.isEmpty else {
			rejectReaderCandidate()
			return
		}
		logger.info("Discovered services")
		for service in services {
			peripheral.discoverCharacteristics(nil, for: service)
		}
	}

	public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		guard peripheral === self.peripheral else { return }
		guard error == nil, let characteristics = service.characteristics else {
			rejectReaderCandidate()
			return
		}
		logger.info("Discovered characteristics")
		do {
			try processCharacteristics(peripheral: peripheral, characteristics: characteristics)
		} catch {
			rejectReaderCandidate()
		}
	}

	public func peripheral(
		_ peripheral: CBPeripheral,
		didUpdateValueFor characteristic: CBCharacteristic,
		error: Error?
	) {
		guard peripheral === self.peripheral else { return }
		if let error {
			if !hasReaderIdentity || characteristic.uuid == MdocServiceCharacteristic.readerIdent.uuid {
				rejectReaderCandidate()
			} else { self.error = error }
			return
		}
		do {
			try processData(peripheral: peripheral, characteristic: characteristic)
		} catch {
			self.error = error
			centralManager?.cancelPeripheralConnection(peripheral)
		}
	}

	public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
		guard peripheral === self.peripheral, hasReaderIdentity else { return }
		writeNextBlock()
	}

	public func peripheral(_ peripheral: CBPeripheral, didModifyServices _: [CBService]) {
		guard peripheral === self.peripheral else { return }
		if !hasReaderIdentity { rejectReaderCandidate() } else { disconnectFromDevice() }
	}
}

extension MdocGattCentral: CBPeripheralManagerDelegate {
	public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
		switch peripheral.state {
		case .poweredOn: logger.info("Peripheral Is Powered On.")
		case .unsupported: logger.info("Peripheral Is Unsupported.")
		case .unauthorized: logger.info("Peripheral Is Unauthorized.")
		case .unknown: logger.info("Peripheral Unknown")
		case .resetting: logger.info("Peripheral Resetting")
		case .poweredOff: logger.info("Peripheral Is Powered Off.")
		@unknown default: logger.info("Error")
		}
	}
}

private func makePeripheralError(_ description: String) -> NSError {
	NSError(domain: "\(MdocGattCentral.self)", code: 0, userInfo: [NSLocalizedDescriptionKey: description])
}
