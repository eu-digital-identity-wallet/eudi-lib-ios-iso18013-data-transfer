//
//  TransferStatus.swift

import Foundation

public enum TransferStatus: String {
	case initializing
	case initialized
	case qrEngagementReady
	case connected
	case started
	case requestReceived
	case responseSent
	case disconnected
	case error
}

public enum ErrorCode: Int, CustomStringConvertible {
	case documents_not_provided
	case invalidInputDocument
	case noDocumentToReturn
	case userRejected
	case requestDecodeError
	case bleNotAuthorized
	case unexpected_error
	
	public var description: String {
		switch self {
		case .documents_not_provided: return "DOCUMENTS_NOT_PROVIDED"
		case .invalidInputDocument: return "INVALID_INPUT_DOCUMENT"
		case .noDocumentToReturn: return "NO_DOCUMENT_TO_RETURN"
		case .requestDecodeError: return "REQUEST_DECODE_ERROR"
		case .userRejected: return "USER_REJECTED"
		case .bleNotAuthorized: return "BLE_NOT_AUTHORIZED"
		default: return "GENERIC_ERROR"
		}
	}
}
