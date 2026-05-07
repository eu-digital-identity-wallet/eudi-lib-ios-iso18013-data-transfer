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

enum CharacteristicsError: Error {
	case missingMandatoryCharacteristic(name: String)
	case missingMandatoryProperty(name: String, characteristicName: String)
}

@MainActor enum DataError: Sendable, Error {
	case noData(characteristic: CBUUID)
	case invalidStateLength
	case unknownState(byte: UInt8)
	case unknownCharacteristic(uuid: CBUUID)
	case unknownDataTransferPrefix(byte: UInt8)
}

public class MdocGattCentral: NSObject, @unchecked Sendable {
	func initialize() {
		centralManager = CBCentralManager(delegate: self, queue: nil)
	}

	func isAuthorized() -> Bool {
		centralManager.state != .unauthorized
	}

	func start() {
		machinePendingState = .initial
	}

	func stop() {
		disconnectFromDevice()
	}

	var uuid: String?
	var readyContinuation: CheckedContinuation<Void, Error>?

	enum MachineState {
		case initial, hardwareOn, fatalError, complete, halted
		case awaitPeripheralDiscovery, peripheralDiscovered, checkPeripheral
		case awaitRequest, requestReceived, sendingResponse
	}
	var centralManager: CBCentralManager!
	var serviceUuid: CBUUID
	var peripheral: CBPeripheral?
	var writeCharacteristic: CBCharacteristic?
	var readCharacteristic: CBCharacteristic?
	var stateCharacteristic: CBCharacteristic?
	var maximumCharacteristicSize: Int?
	var writingQueueTotalChunks = 0
	var writingQueueChunkIndex = 0
	var writingQueue = [Data]()
	var incomingMessageBuffer = Data()
	var outgoingMessageBuffer = Data()
	public var error: Error? = nil { willSet { if let newValue { delegate?.didFinishedWithError(newValue) } } }
	public weak var delegate: (any MdocOfflineDelegate)?

	var machineState = MachineState.initial
	var machinePendingState = MachineState.initial {
		didSet {
			updateState()
		}
	}

	public init(serviceUuid: CBUUID) {
		self.serviceUuid = serviceUuid
		super.init()
	}

	private func updateState() {
		var update = true

		while update {
			if machineState != machinePendingState {
				logger.info("「\(machineState) → \(machinePendingState)」")
			} else {
				logger.info("「\(machineState)」")
			}

			update = false
			switch machineState {
			case .initial:
				if machinePendingState == .hardwareOn {
					machineState = machinePendingState
					update = true
				}

			case .hardwareOn:
				centralManager.scanForPeripherals(withServices: [serviceUuid])
				machineState = machinePendingState
				machinePendingState = .awaitPeripheralDiscovery
				readyContinuation?.resume()
				readyContinuation = nil

			case .awaitPeripheralDiscovery:
				if machinePendingState == .peripheralDiscovered {
					machineState = machinePendingState
				}

			case .peripheralDiscovered:
				if machinePendingState == .checkPeripheral {
					machineState = machinePendingState
					centralManager?.stopScan()
				}

			case .checkPeripheral:
				if machinePendingState == .awaitRequest, let peripheral {
					if let readCharacteristic, let stateCharacteristic {
						peripheral.setNotifyValue(true, for: readCharacteristic)
						peripheral.setNotifyValue(true, for: stateCharacteristic)
						peripheral.writeValue(Data([0x01]), for: stateCharacteristic, type: .withoutResponse)
						machineState = machinePendingState
					}
				}

			case .awaitRequest:
				if machinePendingState == .requestReceived {
					machineState = machinePendingState
					// send message to reader
					incomingMessageBuffer = Data()
				}

			case .requestReceived:
				if machinePendingState == .sendingResponse {
					machineState = machinePendingState
					let chunkSize = max((maximumCharacteristicSize ?? 1) - 1, 1)
					writingQueue = chunkMessage(outgoingMessageBuffer, chunkSize: chunkSize)
					writingQueueTotalChunks = writingQueue.count
					writingQueueChunkIndex = 0
					drainWritingQueue()
					update = true
				}

			case .sendingResponse:
				if machinePendingState == .complete {
					machineState = .complete
				}

			case .fatalError:
				machineState = .halted
				machinePendingState = .halted

			case .complete, .halted:
				break
			}
		}
	}

	func disconnectFromDevice() {
		if let stateCharacteristic {
			peripheral?.writeValue(Data([0x02]), for: stateCharacteristic, type: .withoutResponse)
		}
		disconnect()
	}

	private func disconnect() {
		if let peripheral {
			centralManager.cancelPeripheralConnection(peripheral)
			self.peripheral = nil
		}
	}

	func send(_ data: Data) {
		outgoingMessageBuffer = data
		switch machineState {
		case .requestReceived:
			machinePendingState = .sendingResponse
		default:
			logger.info("Unexpected write in state \(machineState)")
		}
	}

	private func drainWritingQueue() {
		guard !writingQueue.isEmpty else {
			// callback.callback(message: .uploadProgress(writingQueueTotalChunks, writingQueueTotalChunks))
			machinePendingState = .complete
			return
		}

		var chunk = writingQueue.removeFirst()
		writingQueueChunkIndex += 1
		let firstByte: Data.Element = writingQueueChunkIndex == writingQueueTotalChunks ? 0x00 : 0x01
		chunk.reverse()
		chunk.append(firstByte)
		chunk.reverse()
		// callback.callback(message: .uploadProgress(writingQueueChunkIndex, writingQueueTotalChunks))
		peripheral?.writeValue(chunk, for: writeCharacteristic!, type: .withoutResponse)
		if firstByte == 0x00 {
			machinePendingState = .complete
			// callback.callback(message: .done)
		}
	}

	private func chunkMessage(_ data: Data, chunkSize: Int) -> [Data] {
		guard !data.isEmpty else {
			return []
		}
		var chunks = [Data]()
		var index = 0
		while index < data.count {
			let end = min(index + chunkSize, data.count)
			chunks.append(data.subdata(in: index..<end))
			index = end
		}
		return chunks
	}

	private func getCharacteristic(list: [CBCharacteristic], uuid: CBUUID, properties: [CBCharacteristicProperties], required: Bool) throws -> CBCharacteristic? {
		let characteristicName = MDocCharacteristicNameFromUUID(uuid)

		if let candidate = list.first(where: { $0.uuid == uuid }) {
			for property in properties where !candidate.properties.contains(property) {
				let propertyName = MDocCharacteristicPropertyName(property)
				if required {
					throw CharacteristicsError.missingMandatoryProperty(name: propertyName, characteristicName: characteristicName)
				} else {
					return nil
				}
			}
			return candidate
		}

		if required {
			throw CharacteristicsError.missingMandatoryCharacteristic(name: characteristicName)
		}
		return nil
	}

	func processCharacteristics(peripheral: CBPeripheral, characteristics: [CBCharacteristic]) throws {
		stateCharacteristic = try getCharacteristic(list: characteristics, uuid: readerStateCharacteristicId, properties: [.notify, .writeWithoutResponse], required: true)
		writeCharacteristic = try getCharacteristic(list: characteristics, uuid: readerClient2ServerCharacteristicId, properties: [.writeWithoutResponse], required: true)
		readCharacteristic = try getCharacteristic(list: characteristics, uuid: readerServer2ClientCharacteristicId, properties: [.notify], required: true)
		if let readerIdent = try getCharacteristic(list: characteristics, uuid: readerIdentCharacteristicId, properties: [.read], required: true) {
			peripheral.readValue(for: readerIdent)
		}
		let negotiatedMaximumCharacteristicSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
		maximumCharacteristicSize = min(negotiatedMaximumCharacteristicSize - 3, 512)
	}

	func processData(peripheral: CBPeripheral, characteristic: CBCharacteristic) throws {
		if var data = characteristic.value {
			logger.info("Processing \(data.count) bytes for \(MDocCharacteristicNameFromUUID(characteristic.uuid)) -> ")
			switch characteristic.uuid {
			case readerStateCharacteristicId:
				if data.count != 1 {
					throw DataError.invalidStateLength
				}
				switch data[0] {
				case 0x02:
					// callback.callback(message: .done)
					disconnect()
				case let byte:
					throw DataError.unknownState(byte: byte)
				}

			case readerServer2ClientCharacteristicId:
				let firstByte = data.popFirst()
				incomingMessageBuffer.append(data)
				switch firstByte {
				case .none:
					throw DataError.noData(characteristic: characteristic.uuid)
				case 0x00:
					logger.info("End")
					machinePendingState = .requestReceived
				case 0x01:
					logger.info("Chunk")
				case let .some(byte):
					throw DataError.unknownDataTransferPrefix(byte: byte)
				}

			case readerIdentCharacteristicId:
				logger.info("Ident")
				machinePendingState = .awaitRequest

			case let uuid:
				throw DataError.unknownCharacteristic(uuid: uuid)
			}
		} else {
			throw DataError.noData(characteristic: characteristic.uuid)
		}
	}
}

extension MdocGattCentral: CBCentralManagerDelegate {
	public func centralManagerDidUpdateState(_ central: CBCentralManager) {
		if central.state == .poweredOn {
			machinePendingState = .hardwareOn
		} else {
			error = MdocHelpers.makeError(code: .bleNotSupported)
		}
	}

	public func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData _: [String: Any], rssi _: NSNumber) {
		logger.info("Discovered peripheral")
		peripheral.delegate = self
		self.peripheral = peripheral
		centralManager?.connect(peripheral, options: nil)
		machinePendingState = .peripheralDiscovered
	}

	public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
		peripheral.discoverServices([serviceUuid])
		machinePendingState = .checkPeripheral
	}
}

extension MdocGattCentral: CBPeripheralDelegate {
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		if let error {
			self.error = error
			return
		}
		if let services = peripheral.services {
			logger.info("Discovered services")
			for service in services {
				peripheral.discoverCharacteristics(nil, for: service)
			}
		}
	}

	public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		if let error {
			self.error = error
			return
		}
		if let characteristics = service.characteristics {
			logger.info("Discovered characteristics")
			do {
				try processCharacteristics(peripheral: peripheral, characteristics: characteristics)
			} catch {
				self.error = error
				centralManager?.cancelPeripheralConnection(peripheral)
			}
		}
	}

	public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error _: Error?) {
		do {
			try processData(peripheral: peripheral, characteristic: characteristic)
		} catch {
			self.error = error
			centralManager?.cancelPeripheralConnection(peripheral)
		}
	}

	public func peripheralIsReady(toSendWriteWithoutResponse _: CBPeripheral) {
		drainWritingQueue()
	}

	public func peripheral(_ peripheral: CBPeripheral, didModifyServices _: [CBService]) {
		disconnectFromDevice()
	}
}

extension MdocGattCentral: CBPeripheralManagerDelegate {
	public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
		switch peripheral.state {
		case .poweredOn:
			logger.info("Peripheral Is Powered On.")
		case .unsupported:
			logger.info("Peripheral Is Unsupported.")
		case .unauthorized:
			logger.info("Peripheral Is Unauthorized.")
		case .unknown:
			logger.info("Peripheral Unknown")
		case .resetting:
			logger.info("Peripheral Resetting")
		case .poweredOff:
			print("Peripheral Is Powered Off.")
		@unknown default:
			logger.info("Error")
		}
	}
}

private func makePeripheralError(_ description: String) -> NSError {
	NSError(domain: "\(MdocGattCentral.self)", code: 0, userInfo: [NSLocalizedDescriptionKey: description])
}
