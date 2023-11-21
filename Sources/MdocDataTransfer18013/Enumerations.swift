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
	case device_private_key
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
