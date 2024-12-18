/*
Copyright (c) 2023 European Commission

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

/// Transfer status enumeration
public enum TransferStatus: String, Sendable {
	case initializing
	case initialized
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
		default: return "GENERIC_ERROR"
		}
	}
}




