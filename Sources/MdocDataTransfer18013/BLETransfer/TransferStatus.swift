//
//  TransferStatus.swift

import Foundation

public enum TransferStatus: String {
	case qrEngegementReady
	case connected
	case requestReceived
	case responseSent
	case disconnected
	case error
}
