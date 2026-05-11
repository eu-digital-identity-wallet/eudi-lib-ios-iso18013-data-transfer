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

//  ServiceDefinition.swift
import Foundation
import CoreBluetooth
import SwiftCBOR

extension MdocGattServer {
	/// mdoc service characteristic definitions (mdoc is the GATT server)
	public enum MdocServiceCharacteristic: String, CustomStringConvertible, Sendable {
		case state = "00000001-A123-48CE-896B-4C76973373E6"
		case client2Server = "00000002-A123-48CE-896B-4C76973373E6"
		case server2Client = "00000003-A123-48CE-896B-4C76973373E6"

		public var description: String {
			switch self {
			case .state: return "State"
			case .client2Server: return "Client to Server"
			case .server2Client: return "Server to Client"
			}
		}
		
		init?(uuid: CBUUID) { self.init(rawValue: uuid.uuidString.uppercased()) }
		var uuid: CBUUID { CBUUID(string: rawValue) }
	}
}

extension MdocGattCentral {
	/// mdoc service characteristic definitions (mdoc is the GATT server)
	public enum MdocServiceCharacteristic: String, CustomStringConvertible, Sendable {
		case state = "00000005-A123-48CE-896B-4C76973373E6"
		case client2Server = "00000006-A123-48CE-896B-4C76973373E6"
		case server2Client = "00000007-A123-48CE-896B-4C76973373E6"
		case readerIdent = "00000008-A123-48CE-896B-4C76973373E6"

		public var description: String {
			switch self {
			case .state: return "State"
			case .client2Server: return "Client to Server"
			case .server2Client: return "Server to Client"
			case .readerIdent: return "Reader Ident"
			}
		}

		init?(uuid: CBUUID) { self.init(rawValue: uuid.uuidString.uppercased()) }
		var uuid: CBUUID { CBUUID(string: rawValue) }
	}
}

