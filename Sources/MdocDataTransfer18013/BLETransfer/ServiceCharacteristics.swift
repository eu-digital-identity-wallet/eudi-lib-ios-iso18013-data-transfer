//
//  ServiceDefinition.swift
import Foundation
import CoreBluetooth

/// mdoc service characteristic definitions (mdoc is the GATT server)
public enum MdocServiceCharacteristic: String {
	case state
	case client2Server
	case server2Client
}

extension MdocServiceCharacteristic {
	var uuid: CBUUID {
		switch self {
		case .state: return CBUUID(string: "00000001-A123-48CE-896B-4C76973373E6")
		case .client2Server: return CBUUID(string: "00000002-A123-48CE-896B-4C76973373E6")
		case .server2Client: return CBUUID(string: "00000003-A123-48CE-896B-4C76973373E6")
		}
	}
}

