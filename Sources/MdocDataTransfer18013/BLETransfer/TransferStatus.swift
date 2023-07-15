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
