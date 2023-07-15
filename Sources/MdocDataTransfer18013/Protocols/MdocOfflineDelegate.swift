//
//  MdocOfflineHandler.swift

import Foundation
import Combine
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013

public typealias UserAcceptHandler = (Bool) -> Void

public protocol MdocOfflineDelegate {
	func didChangeStatus(_ newStatus: TransferStatus)
	func didReceiveRequest(_ request: DeviceRequest, handleAccept: UserAcceptHandler)
}

public protocol MdocTransferManager: AnyObject {
	var sessionEncryption: SessionEncryption? { get set }
	var docs: [DeviceResponse]? { get set }
	var error: Error? { get set }
}

extension MdocTransferManager {
	func getMdocResponseToSend(requestData: Data) -> Data? {
		guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
		guard let docToSend = self.docs?.first else { logger.error("Transfer manager has not any doc"); return nil } // todo: find document and filter its data
		let cborToSend = docToSend.toCBOR(options: CBOROptions())
		let clearBytesToSend = cborToSend.encode()
		do {
			guard let cipherData = try sessionEncryption.encrypt(clearBytesToSend) else { return nil }
			return Data(cipherData)
		} catch { self.error = error}
		return nil
	}
	func setSampleDocuments(rawData: [Data]) {
		self.docs = rawData.compactMap {
			guard let sr = $0.decodeJSON(type: SignUpResponse.self) else { return nil }
			let dr = sr.deviceResponse
			return dr
		}
	}
}
