//
//  MdocTransferManager.swift

import Foundation
import Combine
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013

public protocol MdocTransferManager: AnyObject {
	var status: TransferStatus { get }
	var deviceEngagement: DeviceEngagement? { get }
	var requireUserAccept: Bool { get set }
	var sessionEncryption: SessionEncryption? { get set }
	var delegate: MdocOfflineDelegate? { get }
	var docs: [DeviceResponse] { get set }
	var iaca: Data  { get set }
	var error: Error? { get set }
}

extension MdocTransferManager {
	func decodeRequestAndInformUser(requestData: Data, handler: @escaping (Bool) -> Void) -> DeviceRequest? {
		do {
			guard let seCbor = try CBOR.decode([UInt8](requestData)) else { logger.error("Request Data is not Cbor"); return nil }
			guard let se = SessionEstablishment(cbor: seCbor), se.eReaderKey != nil else { logger.error("Request Data cannot be decoded to session establisment"); return nil }
			let requestCipherData = se.data
			guard let deviceEngagement else { logger.error("Device Engagement not initialized"); return nil }
			// init session-encryption object from session establish message and device engagement, decrypt data
			sessionEncryption = SessionEncryption(se: se, de: deviceEngagement, handOver: BleTransferMode.QRHandover)
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
			guard let requestData = try sessionEncryption.decrypt(requestCipherData) else { logger.error("Request data cannot be decrypted"); return nil }
			guard let deviceRequest = DeviceRequest(data: requestData) else { logger.error("Decrypted data cannot be decoded"); return nil }
			delegate?.didReceiveRequest(deviceRequest, handleAccept: handler)
			return deviceRequest
		} catch { self.error = error}
		return nil
	}
	
	func getMdocResponseToSend(_ deviceRequest: DeviceRequest, eReaderKey: CoseKey) -> Data? {
		do {
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
			var docToSend = try getDeviceResponseToSend(deviceRequest, eReaderKey: eReaderKey) ?? DeviceResponse(status: 10)
			if status == .error { docToSend = DeviceResponse(status: 10) }
			if docToSend.documents == nil { logger.error("Could not create documents to send") }
			let cborToSend = docToSend.toCBOR(options: CBOROptions())
			let clearBytesToSend = cborToSend.encode()
			guard let cipherData = try sessionEncryption.encrypt(clearBytesToSend) else { return nil }
			let sd = SessionData(cipher_data: cipherData, status: status == .error ? 10 : 0)
			return Data(sd.encode(options: CBOROptions()))
		} catch { self.error = error}
		return nil
	}
	
	// todo: find document and filter its data
	func getDeviceResponseToSend(_ deviceRequest: DeviceRequest, eReaderKey: CoseKey) throws -> DeviceResponse? {
		guard let firstDocRequest = deviceRequest.docRequests.first else { return docs.first }
		guard var docToSend = docs.first(where: { $0.documents!.contains(where: {d in d.docType == firstDocRequest.itemsRequest.docType }) }) else { logger.error("Transfer manager has not any doc"); return nil } // todo: find document and filter its data
		let documents = docToSend.documents!
		var docFiltered = [Document]()
		for docReq in deviceRequest.docRequests {
			guard let d = documents.findDoc(name: docReq.itemsRequest.docType) else { continue }
			guard let issuerNs = d.issuerSigned.issuerNameSpaces else { continue }
			var nsItemsToAdd = [NameSpace: [IssuerSignedItem]]()
			for (nsReq, itemsReq) in docReq.itemsRequest.requestNameSpaces.nameSpaces {
				guard let items = issuerNs[nsReq] else { continue }
				let itemsToAdd = items.filter({ itemsReq.elementIdentifiers.contains($0.elementIdentifier) })
				nsItemsToAdd[nsReq] = itemsToAdd
			}
			guard let (issuerAuthToAdd, pk) = try IssuerAuthentication.makeDefaultIssuerAuth(for: d, iaca: iaca) else {logger.error("IACA not valid"); return nil }
			let issToAdd = IssuerSigned(issuerNameSpaces: IssuerNameSpaces(nameSpaces: nsItemsToAdd), issuerAuth: issuerAuthToAdd)
			let authKeys = CoseKeyExchange(publicKey: eReaderKey, privateKey: pk)
			let mdocAuth = MdocAuthentication(transcript: sessionEncryption!.transcript, authKeys: authKeys)
			guard let devAuth = try mdocAuth.getDeviceAuthForTransfer(docType: docReq.itemsRequest.docType) else {logger.error("Cannot create device auth"); return nil }
			let devSignedToAdd = DeviceSigned(deviceAuth: devAuth)
			let docToAdd = Document(docType: docReq.itemsRequest.docType, issuerSigned: issToAdd, deviceSigned: devSignedToAdd, errors: nil)
			docFiltered.append(docToAdd)
		}
		// todo: document-errors, errors
		docToSend = DeviceResponse(version: docToSend.version, documents: docFiltered, documentErrors: nil, status: 0)
		return docToSend
	}
	
}
