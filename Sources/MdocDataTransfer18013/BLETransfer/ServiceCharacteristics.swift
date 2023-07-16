//
//  ServiceDefinition.swift
import Foundation
import CoreBluetooth

public enum BleTransferMode {
	case server
	case client
	// signals for coordination
	static var START_REQUEST: [UInt8] = [0x01]
	static var END_REQUEST: [UInt8] = [0x02]
	static var START_DATA: [UInt8] = [0x01]
	static var END_DATA: [UInt8] = [0x00]
	public static let BASE_UUID_SUFFIX_SERVICE = "-0000-1000-8000-00805F9B34FB"
}

/// mdoc service characteristic definitions (mdoc is the GATT server)
public enum MdocServiceCharacteristic: String {
	case state
	case client2Server
	case server2Client
}

extension MdocServiceCharacteristic {
	init?(uuid: CBUUID) {
		self.init(rawValue: uuid.uuidString)
	}
	
	var uuid: CBUUID {
		switch self {
		case .state: return CBUUID(string: "00000001-A123-48CE-896B-4C76973373E6")
		case .client2Server: return CBUUID(string: "00000002-A123-48CE-896B-4C76973373E6")
		case .server2Client: return CBUUID(string: "00000003-A123-48CE-896B-4C76973373E6")
		}
	}
}

