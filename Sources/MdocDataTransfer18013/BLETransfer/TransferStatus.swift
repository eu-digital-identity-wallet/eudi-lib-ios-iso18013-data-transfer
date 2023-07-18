//
//  TransferStatus.swift

import Foundation

public enum TransferStatus: String {
	case initializing
	case qrEngagementReady
	case connected
	case started
	case requestReceived
	case responseSent
	case disconnected
	case error
}

public enum ErrorCode: Int, CustomStringConvertible {
	case invalidInputDocument
	case noDocumentToReturn
	case unexpected_error
	
	public var description: String {
		switch self {
		case .invalidInputDocument: return "INVALID_INPUT_DOCUMENT"
		case .noDocumentToReturn: return "NO_DOCUMENT_TO_RETURN"
		default: return "GENERIC_ERROR"
		}
	}
}
