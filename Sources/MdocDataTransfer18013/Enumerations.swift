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
public enum TransferStatus: String {
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
public enum ErrorCode: Int, CustomStringConvertible {
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
		default: return "GENERIC_ERROR"
		}
	}
}

/// String keys for the initialization dictionary
public enum InitializeKeys: String {
	case document_json_data
	case document_signup_response_data
	case document_signup_response_obj
	case device_private_key_data
	case device_private_key_obj
	case trusted_certificates
}

/// String keys for the user request dictionary
public enum UserRequestKeys: String {
	case valid_items_requested
	case error_items_requested
	case reader_certificate_issuer
	case reader_auth_validated
	case reader_certificate_validation_message
}
