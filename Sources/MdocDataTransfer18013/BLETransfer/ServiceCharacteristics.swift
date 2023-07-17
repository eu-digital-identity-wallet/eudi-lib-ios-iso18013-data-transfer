//
//  ServiceDefinition.swift
import Foundation
import CoreBluetooth
import SwiftCBOR

public enum BleTransferMode {
	case server
	case client
	// signals for coordination
	static var START_REQUEST: [UInt8] = [0x01]
	static var END_REQUEST: [UInt8] = [0x02]
	static var START_DATA: [UInt8] = [0x01]
	static var END_DATA: [UInt8] = [0x00]
	public static let BASE_UUID_SUFFIX_SERVICE = "-0000-1000-8000-00805F9B34FB"
	public static let QRHandover = CBOR.null
}

/// mdoc service characteristic definitions (mdoc is the GATT server)
public enum MdocServiceCharacteristic: String {
	case state = "00000001-A123-48CE-896B-4C76973373E6"
	case client2Server = "00000002-A123-48CE-896B-4C76973373E6"
	case server2Client = "00000003-A123-48CE-896B-4C76973373E6"
}

extension MdocServiceCharacteristic {
	init?(uuid: CBUUID) {	self.init(rawValue: uuid.uuidString.uppercased()) }
	var uuid: CBUUID { CBUUID(string: rawValue) }
}

