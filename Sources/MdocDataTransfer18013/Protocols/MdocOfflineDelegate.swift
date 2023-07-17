//
//  MdocOfflineHandler.swift

import Foundation
import Combine
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013

public typealias UserAcceptHandler = (Bool) -> Void

public protocol MdocOfflineDelegate: AnyObject {
	func didChangeStatus(_ newStatus: TransferStatus)
	func didReceiveRequest(_ request: DeviceRequest, handleAccept: UserAcceptHandler)
}

public protocol MdocTransferManager: AnyObject {
	var deviceEngagement: DeviceEngagement? { get }
	var requireUserAccept: Bool { get set }
	var displayDefaultAcceptUI: Bool { get set }
	var sessionEncryption: SessionEncryption? { get set }
	var docs: [DeviceResponse] { get set }
	var error: Error? { get set }
}

extension MdocTransferManager {
	func getMdocResponseToSend(requestData: Data) -> Data? {
		guard let se = SessionEstablishment(data: [UInt8](requestData)) else { logger.error("Request Data cannot be decoded to session establisment"); return nil }
		let requestCipherData = se.data
		guard let deviceEngagement else { logger.error("Device Engagement not initialized"); return nil }
		sessionEncryption = SessionEncryption(se: se, de: deviceEngagement, handOver: BleTransferMode.QRHandover)
		guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
		do {
			guard let requestData = try sessionEncryption.decrypt(requestCipherData) else { logger.error("Request data cannot be decrypted"); return nil }
			guard let deviceRequest = DeviceRequest(data: requestData) else { logger.error("Decrypted data cannot be decoded"); return nil }
			guard let docToSend = self.docs.first else { logger.error("Transfer manager has not any doc"); return nil } // todo: find document and filter its data
			let cborToSend = docToSend.toCBOR(options: CBOROptions())
			let clearBytesToSend = cborToSend.encode()
			guard let cipherData = try sessionEncryption.encrypt(clearBytesToSend) else { return nil }
			let sd = SessionData(cipher_data: cipherData, status: 0)
			return Data(sd.encode(options: CBOROptions()))
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
