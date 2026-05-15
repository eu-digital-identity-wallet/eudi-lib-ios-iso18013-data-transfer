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

//  TransferStatus.swift

import Foundation
import SwiftCBOR
/// The enum BleTransferMode defines the two roles in the communication, which can be a server or a client.
///
/// The four static variables are used to signal the start and end of communication.
/// This is done by sending bytes 0x01 and 0x02 for start and end.
/// For start and end of data transmission, bytes 0x01 and 0x00 are used.
public enum BleTransferMode: Sendable {
	case server
	case client
	case both
	// signals for coordination
	static let START_REQUEST: [UInt8] = [0x01]
	static let END_REQUEST: [UInt8] = [0x02]
	static let START_DATA: [UInt8] = [0x01]
	static let END_DATA: [UInt8] = [0x00]
	public static let BASE_UUID_SUFFIX_SERVICE = "-0000-1000-8000-00805F9B34FB"
	public static let QRHandover = CBOR.null
}

/// Transfer status enumeration
public enum TransferStatus: String, Sendable {
	case initializing
	case initialized
	case poweredOn
	case qrEngagementReady
	case connected
	case started
	case requestReceived
	case userSelected
	case responseSent
	case disconnected
	case error
}

/// Possible error codes
public enum ErrorCode: Int, CustomStringConvertible, Sendable {
	case documents_not_provided
	case invalidInputDocument
	case invalidUrl
	case device_private_key_not_provided
	case noDocumentToReturn
	case userRejected
	case requestDecodeError
	case bleNotAuthorized
	case bleNotSupported
	case unexpected_error
	case sessionEncryptionNotInitialized
	case deviceEngagementMissing
	case readerKeyMissing
	case bleInvalidStateLength
	case bleInvalidStateByte
	case bleNoData
	
	public var description: String {
		switch self {
		case .documents_not_provided: return "DOCUMENTS_NOT_PROVIDED"
		case .invalidInputDocument: return "INVALID_INPUT_DOCUMENT"
		case .invalidUrl: return "INVALID_URL"
		case .device_private_key_not_provided: return "DEVICE_PRIVATE_KEY_NOT_PROVIDED"
		case .noDocumentToReturn: return "NO_DOCUMENT_TO_RETURN"
		case .requestDecodeError: return "REQUEST_DECODE_ERROR"
		case .userRejected: return "USER_REJECTED"
		case .bleNotAuthorized: return "BLE_NOT_AUTHORIZED"
		case .bleNotSupported: return "BLE_NOT_SUPPORTED"
		case .deviceEngagementMissing: return "DEVICE_ENGAGEMENT_MISSING"
		case .readerKeyMissing: return "READER_KEY_MISSING"
		case .sessionEncryptionNotInitialized: return "SESSION_ENCYPTION_NOT_INITIALIZED"
		case .bleInvalidStateLength: return "INVALID_STATE_LENGTH"
		case .bleInvalidStateByte: return "INVALID_STATE_BYTE"
		case .bleNoData: return "NO_DATA"
		default: return "GENERIC_ERROR"
		}
	}
}




