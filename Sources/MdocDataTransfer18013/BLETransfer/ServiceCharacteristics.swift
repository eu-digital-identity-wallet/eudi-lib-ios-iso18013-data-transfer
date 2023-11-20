 /*
 * Copyright (c) 2023 European Commission
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */

//  ServiceDefinition.swift
import Foundation
import CoreBluetooth
import SwiftCBOR

/// The enum BleTransferMode defines the two roles in the communication, which can be a server or a client.
///
/// The four static variables are used to signal the start and the end of the communication. This is done by sending the bytes 0x01 and 0x02 for the start and end of the communication, respectively. For the start and end of the data transmission, the bytes 0x01 and 0x00 are used.
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

