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

public class MdocGattCentral: NSObject, MdocBleTransport, @unchecked Sendable {
	var centralManager: CBCentralManager!
	var peripheral: CBPeripheral?
	var writeCharacteristic: CBCharacteristic?
	var readCharacteristic: CBCharacteristic?
	var stateCharacteristic: CBCharacteristic?
	var hasReaderIdentity = false
	var didSendStartRequest = false
	var maximumCharacteristicSize: Int?
	var readBuffer = Data()
	var sendBuffer = [Data]()
    var inactivityTimer: SessionInactivityTimeout?
	public var error: Error? = nil {
		didSet {
			if let error {
                terminateSession()
				status = .error
				delegate?.didFinishedWithError(error)
			}
		}
	}
	public weak var delegate: (any MdocOfflineDelegate)?
	public var status: TransferStatus = .initialized {
		didSet {
			delegate?.didChangeStatus(status)
		}
	}

	required public override init() {
		super.init()
		centralManager = CBCentralManager(delegate: self, queue: nil)
		status = .initialized
		if isBlePoweredOn {
			handleCentralPoweredOn()
		}
	}

	public func stop() {
		disconnectFromDevice()
	}

    public func startBleAdvertising() {
        guard Thread.isMainThread else { DispatchQueue.main.sync { self.startBleAdvertising() }; return }
        guard peripheral == nil, centralManager?.isScanning != true else { return }
        if centralManager?.state == .poweredOn { handleCentralPoweredOn() }
    }

    public func stopBleAdvertising() {
    }

    public var isBlePoweredOn: Bool { centralManager.state == .poweredOn }

	public var isAuthorized: Bool {
		centralManager.state != .unauthorized
	}
	public var supportsL2cap: Bool { false }
	
	private func handleCentralPoweredOn() {
        guard Thread.isMainThread else { DispatchQueue.main.sync { self.handleCentralPoweredOn() }; return }
		delegate?.didPoweredOn(isPeripheralManager: false)
		status = .poweredOn
		guard let serviceUuid = delegate?.deviceEngagement?.ble_uuid else {
			logger.error("BLE initialization error")
			error = MdocHelpers.makeError(code: .deviceEngagementMissing)
			return
		}
        monitorInactivity()
        guard inactivityTimer?.check() != false else { return }
		centralManager.scanForPeripherals(withServices: [CBUUID(string: serviceUuid)])
		logger.info("Started scanning for peripherals with service UUID \(serviceUuid)")
		status = .qrEngagementReady
	}

	private func tryStartRequestIfReady() {
		guard hasReaderIdentity, !didSendStartRequest, let peripheral, let readCharacteristic, let stateCharacteristic else {
			return
		}
		peripheral.setNotifyValue(true, for: readCharacteristic)
		peripheral.setNotifyValue(true, for: stateCharacteristic)
		peripheral.writeValue(Data(BleTransferMode.START_REQUEST), for: stateCharacteristic, type: .withoutResponse)
		didSendStartRequest = true
		status = .started
	}

	public func disconnectFromDevice() {
		if let stateCharacteristic {
			peripheral?.writeValue(Data(BleTransferMode.END_REQUEST), for: stateCharacteristic, type: .withoutResponse)
		}
		disconnect()
	}

    private func disconnect() { terminateSession() }

    func monitorInactivity(using suppliedTimer: SessionInactivityTimeout? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { self.monitorInactivity(using: suppliedTimer) }
            return
        }
        guard let engagement = delegate?.deviceEngagement, let key = engagement.privateKey else { return }
        let timer = suppliedTimer ?? SessionInactivityTimeout.shared(for: key)
        guard inactivityTimer !== timer else { return }
        inactivityTimer?.end()
        inactivityTimer = timer
        timer.observe(self) { [weak self, weak timer] notify in
            guard let self, let timer, self.inactivityTimer === timer else { return false }
            let currentKey = self.delegate?.deviceEngagement?.privateKey
            let ownsSession = currentKey?.privateKeyId == key.privateKeyId && currentKey?.index == key.index &&
                currentKey.map { ObjectIdentifier($0.secureArea) == ObjectIdentifier(key.secureArea) } == true
            if !ownsSession { clearMdocSession(nil, engagement: engagement) }
            self.terminateSession(clearDelegate: ownsSession)
            if notify && ownsSession {
                self.error = MdocHelpers.makeError(code: .bleSessionTimeout)
                return true
            }
            return false
        }
    }

    @discardableResult
    func terminateSession(clearDelegate: Bool = true) -> Task<Void, Never>? {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { self.terminateSession(clearDelegate: clearDelegate) }
        }
        let timer = inactivityTimer
        inactivityTimer = nil
        timer?.end()
        centralManager?.stopScan()
        let oldPeripheral = peripheral
        peripheral = nil
        oldPeripheral?.delegate = nil
        if let oldPeripheral { centralManager?.cancelPeripheralConnection(oldPeripheral) }
        hasReaderIdentity = false
        didSendStartRequest = false
        maximumCharacteristicSize = nil
        writeCharacteristic = nil
        readCharacteristic = nil
        stateCharacteristic = nil
        readBuffer.removeAll()
        sendBuffer.removeAll()
        return clearDelegate ? clearMdocSession(delegate) : nil
    }

    // Used by tests without starting Bluetooth.
    init(centralManager: CBCentralManager?) {
        super.init()
        self.centralManager = centralManager
    }

	public func sendData(_ data: Data) {
        guard Thread.isMainThread else { DispatchQueue.main.sync { self.sendData(data) }; return }
        guard inactivityTimer?.check() != false else { return }
		guard status == .requestReceived else {
			logger.info("Unexpected write in status \(status)")
			return
		}
        inactivityTimer?.activity()
		status = .userSelected
		let blockSize = max((maximumCharacteristicSize ?? 1) - 1, 1)
		sendBuffer = MdocHelpers.prepareDataBlocksToSend(data, blockSize: blockSize)
		writeNextBlock()
	}

	private func writeNextBlock() {
        guard inactivityTimer?.check() != false else { return }
		guard !sendBuffer.isEmpty else {
            finishResponse()
			return
		}
		guard let writeCharacteristic else {
			error = MdocHelpers.makeError(code: .bleNotSupported)
			return
		}
        guard let peripheral else { return }
		peripheral.writeValue(sendBuffer.first!, for: writeCharacteristic, type: .withoutResponse)
        inactivityTimer?.activity()
		if !sendBuffer.isEmpty { sendBuffer.removeFirst() }
	}

    func finishResponse() {
        terminateSession()
        status = .responseSent
        logger.info("Finished sending BLE data")
        status = .disconnected
    }

	private func getCharacteristic(
		list: [CBCharacteristic],
		mdocChar: MdocServiceCharacteristic,
		properties: [CBCharacteristicProperties],
		description: String
	) throws -> CBCharacteristic? {
		if let characteristic = list.first(where: { $0.uuid == mdocChar.uuid }) {
			for property in properties where !characteristic.properties.contains(property) {
				logger.info("Characteristic \(mdocChar.description) is expected to have \(description) properties")
				break
			}
			return characteristic
		} else {
			logger.info("Characteristic \(mdocChar.description) with UUID \(mdocChar.uuid.uuidString) not found")
		}
		return nil
	}

	func processCharacteristics(
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
		if let readerIdent = try getCharacteristic(
			list: characteristics,
			mdocChar: .readerIdent,
			properties: readerIdentityProperties,
			description: "read"
		) {
			peripheral.readValue(for: readerIdent)
		}
		let negotiatedMaximumCharacteristicSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
		maximumCharacteristicSize = min(negotiatedMaximumCharacteristicSize - 3, 512)
		tryStartRequestIfReady()
	}

	func processData(
		peripheral: CBPeripheral,
		characteristic: CBCharacteristic
	) throws {
        guard inactivityTimer?.check() != false else { return }
		if var data = characteristic.value {
			let characteristicDescription =
				MdocServiceCharacteristic(uuid: characteristic.uuid)?.description
				?? characteristic.uuid.uuidString
			logger.info("Processing \(data.count) bytes for \(characteristicDescription)")
			switch characteristic.uuid {
			case MdocServiceCharacteristic.state.uuid:
				if data.count != 1 {
					error = MdocHelpers.makeError(code: .bleInvalidStateLength)
                    return
				}
				switch data[0] {
				case BleTransferMode.END_REQUEST.first!: // 0x02:
                    terminateSession()
					status = .disconnected
				case let byte:
					logger.error("Unknown state \(byte)")
					error = MdocHelpers.makeError(code: .bleInvalidStateByte)
				}
			case MdocServiceCharacteristic.server2Client.uuid:
                guard status == .started else { return }
				let firstByte = data.popFirst()
				readBuffer.append(data)
				switch firstByte {
				case .none:
					error = MdocHelpers.makeError(code: .bleNoData)
				case BleTransferMode.END_DATA.first!: // 0x00:
                    inactivityTimer?.activity()
                    let request = readBuffer
                    readBuffer.removeAll()
					status = .requestReceived
                    delegate?.didReceiveRequest(request)
				case BleTransferMode.START_DATA.first!: break
				case let .some(byte):
					logger.error("Unknown data prefix \(byte)")
					error = MdocHelpers.makeError(code: .bleNotSupported)
				}
			case MdocServiceCharacteristic.readerIdent.uuid:
				logger.info("Ident")
				hasReaderIdentity = true
				tryStartRequestIfReady()
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
        guard status == .qrEngagementReady else { return }
		logger.info("Discovered peripheral")
		peripheral.delegate = self
		self.peripheral = peripheral
		centralManager?.connect(peripheral, options: nil)
		centralManager?.stopScan()
	}

	public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
		let serviceUuid = delegate?.deviceEngagement?.ble_uuid
		peripheral.discoverServices([CBUUID(string: serviceUuid ?? "")])
		delegate?.didConnected(isPeripheral: true, deviceName: peripheral.name)
		status = .connected
		tryStartRequestIfReady()
	}
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        terminateSession()
        status = .disconnected
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        terminateSession()
        status = .disconnected
    }

}

extension MdocGattCentral: CBPeripheralDelegate {
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
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
        guard self.peripheral === peripheral else { return }
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

	public func peripheral(
		_ peripheral: CBPeripheral,
		didUpdateValueFor characteristic: CBCharacteristic,
		error: Error?
	) {
        guard self.peripheral === peripheral else { return }
        if let error { self.error = error; return }
		do {
			try processData(peripheral: peripheral, characteristic: characteristic)
		} catch {
			self.error = error
			centralManager?.cancelPeripheralConnection(peripheral)
		}
	}

	public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
		writeNextBlock()
	}

	public func peripheral(_ peripheral: CBPeripheral, didModifyServices _: [CBService]) {
        guard self.peripheral === peripheral else { return }
		disconnectFromDevice()
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
