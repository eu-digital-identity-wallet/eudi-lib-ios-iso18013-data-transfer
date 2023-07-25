//
//  MdocTransferManager.swift

import Foundation
import ASN1Decoder
import Combine
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013

public protocol MdocTransferManager: AnyObject {
	func initialize(parameters: [String: Any])
	var status: TransferStatus { get }
	var deviceEngagement: DeviceEngagement? { get }
	var requireUserAccept: Bool { get set }
	var sessionEncryption: SessionEncryption? { get set }
	var deviceResponseToSend: DeviceResponse? { get set }
	var validRequestItems: [String: [String]]? { get set }
	var delegate: MdocOfflineDelegate? { get }
	var docs: [DeviceResponse]! { get set }
	var iaca: [SecCertificate]!  { get set }
	var error: Error? { get set }
}

public enum InitializeKeys: String {
	case document_data
	case trusted_certificates
	case require_user_accept
}

public enum UserRequestKeys: String {
	case items_requested
	case reader_authority
	case reader_authenticated
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
			try getDeviceResponseToSend(deviceRequest, eReaderKey: sessionEncryption.sessionKeys.publicKey)
			guard let validRequestItems else { logger.error("Valid request items nil"); return nil }
			var params: [String: Any] = [UserRequestKeys.items_requested.rawValue: validRequestItems]
			if let docR = deviceRequest.docRequests.first {
				let mdocAuth = MdocReaderAuthentication(transcript: sessionEncryption.transcript)
				if let readerAuthRawCBOR = docR.readerAuthRawCBOR, let certData = docR.readerCertificate, let x509 = try? X509Certificate(der: certData), let issName = x509.issuerDistinguishedName, let b = try? mdocAuth.validateReaderAuth(readerAuthCBOR: readerAuthRawCBOR, readerAuthCertificate: certData, itemsRequestRawData: docR.itemsRequestRawData!, rootCerts: iaca) {
					params[UserRequestKeys.reader_authority.rawValue] = issName
					params[UserRequestKeys.reader_authenticated.rawValue] = b
				}
			}
			delegate?.didReceiveRequest(params, handleAccept: handler)
			return deviceRequest
		} catch { self.error = error}
		return nil
	}
	
	func getDeviceResponseToSend(_ deviceRequest: DeviceRequest, eReaderKey: CoseKey) throws {
		guard let firstDocRequest = deviceRequest.docRequests.first else { return }
		guard var docToSend = docs.first(where: { $0.documents!.contains(where: {d in d.docType == firstDocRequest.itemsRequest.docType }) }) else { logger.error("Transfer manager has not any doc"); return } // todo: find document and filter its data
		let documents = docToSend.documents!
		var docFiltered = [Document](); var docErrors = [[DocType: UInt64]](); var validReqItemsDict = [String:[String]]()
		for docReq in deviceRequest.docRequests {
			guard let d = documents.findDoc(name: docReq.itemsRequest.docType) else {
				docErrors.append([docReq.itemsRequest.docType: UInt64(0)])
				continue
			}
			guard let issuerNs = d.issuerSigned.issuerNameSpaces else { logger.error("Null issuer namespaces"); return }
			var nsItemsToAdd = [NameSpace: [IssuerSignedItem]](); var nsErrorsToAdd = [NameSpace : ErrorItems]()
			for (nsReq, itemsReq) in docReq.itemsRequest.requestNameSpaces.nameSpaces {
				guard let items = issuerNs[nsReq] else {
					nsErrorsToAdd[nsReq] = itemsReq.dataElements.mapValues { _ in 0 }
					continue
				}
				let itemsReqSet = Set(itemsReq.elementIdentifiers); let itemsSet = Set(items.map(\.elementIdentifier))
				let itemsToAdd = items.filter({ itemsReqSet.contains($0.elementIdentifier) })
				if itemsToAdd.count > 0 {
					nsItemsToAdd[nsReq] = itemsToAdd
					validReqItemsDict[docReq.itemsRequest.docType] = itemsToAdd.map(\.elementIdentifier)
				}
				let errorItemsSet = itemsReqSet.subtracting(itemsSet)
				if errorItemsSet.count > 0 { nsErrorsToAdd[nsReq] = Dictionary(grouping: errorItemsSet, by: { $0 }).mapValues { _ in 0 }
				}
			}
			guard let (issuerAuthDef, pk) = try IssuerAuthentication.makeDefaultIssuerAuth(for: d, iaca: SecCertificateCopyData(iaca.first!) as! Data) else { logger.error("IACA not valid"); return }
			let issuerAuthToAdd = d.issuerSigned.issuerAuth ?? issuerAuthDef
			let issToAdd = IssuerSigned(issuerNameSpaces: IssuerNameSpaces(nameSpaces: nsItemsToAdd), issuerAuth: issuerAuthToAdd)
			let authKeys = CoseKeyExchange(publicKey: eReaderKey, privateKey: pk)
			let mdocAuth = MdocAuthentication(transcript: sessionEncryption!.transcript, authKeys: authKeys)
			guard let devAuth = try mdocAuth.getDeviceAuthForTransfer(docType: docReq.itemsRequest.docType) else {logger.error("Cannot create device auth"); return }
			let devSignedToAdd = DeviceSigned(deviceAuth: devAuth)
			let errors: Errors? = nsErrorsToAdd.count == 0 ? nil : Errors(errors: nsErrorsToAdd)
			let docToAdd = Document(docType: docReq.itemsRequest.docType, issuerSigned: issToAdd, deviceSigned: devSignedToAdd, errors: errors)
			docFiltered.append(docToAdd)
		}
		var documentErrors: [DocumentError]? = docErrors.count == 0 ? nil : docErrors.map(DocumentError.init(docErrors:))
		docToSend = DeviceResponse(version: docToSend.version, documents: docFiltered, documentErrors: documentErrors, status: 0)
		deviceResponseToSend = docToSend
		validRequestItems = validReqItemsDict
	}
	
	func getMdocResponseToSend(_ deviceRequest: DeviceRequest, eReaderKey: CoseKey) -> Data? {
		do {
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
			guard let docToSend = deviceResponseToSend else { logger.error("Response to send not created"); return nil }
			if docToSend.documents == nil { logger.error("Could not create documents to send") }
			let cborToSend = docToSend.toCBOR(options: CBOROptions())
			let clearBytesToSend = cborToSend.encode()
			guard let cipherData = try sessionEncryption.encrypt(clearBytesToSend) else { return nil }
			let sd = SessionData(cipher_data: status == .error ? nil : cipherData, status: status == .error ? 20 : 0)
			return Data(sd.encode(options: CBOROptions()))
		} catch { self.error = error}
		return nil
	}
}
