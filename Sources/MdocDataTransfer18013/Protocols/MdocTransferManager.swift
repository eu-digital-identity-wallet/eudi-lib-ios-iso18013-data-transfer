//
//  MdocTransferManager.swift

import Foundation
import ASN1Decoder
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013
import Logging

public typealias RequestItems = [String: [String: [String]]]
/// Protocol for a transfer manager object used to transfer data to and from the Mdoc holder.
public protocol MdocTransferManager: AnyObject {
	func initialize(parameters: [String: Any])
	func performDeviceEngagement()
	func stop()
	var status: TransferStatus { get set }
	var deviceEngagement: DeviceEngagement? { get }
	var requireUserAccept: Bool { get set }
	var sessionEncryption: SessionEncryption? { get set }
	var deviceRequest: DeviceRequest? { get set }
	var deviceResponseToSend: DeviceResponse? { get set }
	var validRequestItems: RequestItems? { get set }
	var errorRequestItems: RequestItems? { get set }
	var delegate: MdocOfflineDelegate? { get set }
	var docs: [DeviceResponse]! { get set }
	var devicePrivateKey: CoseKeyPrivate! { get set }
	var iaca: [SecCertificate]!  { get set }
	var error: Error? { get set }
	var readerName: String? { get set }
}

/// String keys for the initialization dictionary
public enum InitializeKeys: String {
	case document_json_data
	case document_signup_response_data
	case device_private_key
	case trusted_certificates
	case require_user_accept
}

/// String keys for the user request dictionary
public enum UserRequestKeys: String {
	case valid_items_requested
	case error_items_requested
	case reader_certificate_issuer
	case reader_auth_validated
	case reader_certificate_validation_message
}

extension MdocTransferManager {
	
	public func initialize(parameters: [String: Any]) {
		if let d = parameters[InitializeKeys.document_json_data.rawValue] as? [Data] {
			// load json sample data here
			let sampleData = d.compactMap { $0.decodeJSON(type: SignUpResponse.self) }
			docs = sampleData.compactMap { $0.deviceResponse }
			devicePrivateKey = sampleData.compactMap { $0.devicePrivateKey }.first
		} else if let drs = parameters[InitializeKeys.document_signup_response_data.rawValue] as? [DeviceResponse], let dpk = parameters[InitializeKeys.device_private_key.rawValue] as? CoseKeyPrivate {
			docs = drs
			devicePrivateKey = dpk
		}
		if docs == nil { error = Self.makeError(code: .documents_not_provided); return }
		if docs.count == 0 { error = Self.makeError(code: .invalidInputDocument); return }
		if devicePrivateKey == nil { error = Self.makeError(code: .device_private_key_not_provided); return }
		if let i = parameters[InitializeKeys.trusted_certificates.rawValue] as? [Data] {
			iaca = i.compactMap {	SecCertificateCreateWithData(nil, $0 as CFData) }
		}
		if let b = parameters[InitializeKeys.require_user_accept.rawValue] as? Bool {
			requireUserAccept = b
		}
		status = .initialized
	}
	
	/// Decrypt the contents of a data object and return a ``DeviceRequest`` object if the data represents a valid device request. If the data does not represent a valid device request, the function returns nil.
	/// - Parameters:
	///   - requestData: Request data passed to the mdoc holder
	///   - handler: Handler to call with the accept/reject flag
	///   - devicePrivateKey: Device private key
	///   - readerKeyRawData: reader key cbor data (if reader engagement is used)
	/// - Returns: A ``DeviceRequest`` object
	public func decodeRequestAndInformUser(requestData: Data, devicePrivateKey: CoseKeyPrivate, readerKeyRawData: [UInt8]?, handOver: CBOR, handler: @escaping (Bool, RequestItems?) -> Void) -> DeviceRequest? {
		do {
			guard let seCbor = try CBOR.decode([UInt8](requestData)) else { logger.error("Request Data is not Cbor"); return nil }
			guard var se = SessionEstablishment(cbor: seCbor) else { logger.error("Request Data cannot be decoded to session establisment"); return nil }
			if se.eReaderKeyRawData == nil, let readerKeyRawData { se.eReaderKeyRawData = readerKeyRawData }
			guard se.eReaderKey != nil else { logger.error("Reader key not available"); return nil }
			let requestCipherData = se.data
			guard let deviceEngagement else { logger.error("Device Engagement not initialized"); return nil }
			// init session-encryption object from session establish message and device engagement, decrypt data
			sessionEncryption = SessionEncryption(se: se, de: deviceEngagement, handOver: handOver)
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
			guard let requestData = try sessionEncryption.decrypt(requestCipherData) else { logger.error("Request data cannot be decrypted"); return nil }
			guard let deviceRequest = DeviceRequest(data: requestData) else { logger.error("Decrypted data cannot be decoded"); return nil }
			try getDeviceResponseToSend(deviceRequest, selectedItems: nil, eReaderKey: sessionEncryption.sessionKeys.publicKey, devicePrivateKey: devicePrivateKey)
			guard let validRequestItems, let errorRequestItems else { logger.error("Valid request items nil"); return nil }
			var params: [String: Any] = [UserRequestKeys.valid_items_requested.rawValue: validRequestItems, UserRequestKeys.error_items_requested.rawValue: errorRequestItems]
			if let docR = deviceRequest.docRequests.first {
				let mdocAuth = MdocReaderAuthentication(transcript: sessionEncryption.transcript)
				if let readerAuthRawCBOR = docR.readerAuthRawCBOR, let certData = docR.readerCertificate, let x509 = try? X509Certificate(der: certData), let issName = x509.issuerDistinguishedName, let (b,reasonFailure) = try? mdocAuth.validateReaderAuth(readerAuthCBOR: readerAuthRawCBOR, readerAuthCertificate: certData, itemsRequestRawData: docR.itemsRequestRawData!, rootCerts: iaca) {
					params[UserRequestKeys.reader_certificate_issuer.rawValue] = issName
					params[UserRequestKeys.reader_auth_validated.rawValue] = b
					if let reasonFailure { params[UserRequestKeys.reader_certificate_validation_message.rawValue] = reasonFailure }
				}
			}
			self.deviceRequest = deviceRequest
			if requireUserAccept { delegate?.didReceiveRequest(params, handleSelected: handler) }
			return deviceRequest
		} catch { self.error = error}
		return nil
	}
	
	@discardableResult public func getDeviceResponseToSend(_ deviceRequest: DeviceRequest?, selectedItems: RequestItems?, eReaderKey: CoseKey?, devicePrivateKey: CoseKeyPrivate) throws -> DeviceResponse? {
		let documents = docs.flatMap { $0.documents! }
		var docFiltered = [Document](); var docErrors = [[DocType: UInt64]]()
		var validReqItemsDocDict = RequestItems(); var errorReqItemsDocDict = RequestItems()
		guard deviceRequest != nil || selectedItems != nil else { fatalError("Invalid call") }
		let haveDeviceRequest = deviceRequest != nil
		let reqDocTypes = haveDeviceRequest ? deviceRequest!.docRequests.map(\.itemsRequest.docType) : Array(selectedItems!.keys)
		for reqDocType in reqDocTypes {
			let docReq = deviceRequest?.docRequests.findDoc(name: reqDocType)
			guard let doc = documents.findDoc(name: reqDocType) else {
				docErrors.append([reqDocType: UInt64(0)])
				errorReqItemsDocDict[reqDocType] = [:]
				continue
			}
			guard let issuerNs = doc.issuerSigned.issuerNameSpaces else { logger.error("Null issuer namespaces"); return nil }
			var nsItemsToAdd = [NameSpace: [IssuerSignedItem]]()
			var nsErrorsToAdd = [NameSpace : ErrorItems]()
			var validReqItemsNsDict = [NameSpace: [String]]()
			// for each request namespace
			let reqNamespaces = haveDeviceRequest ? Array(docReq!.itemsRequest.requestNameSpaces.nameSpaces.keys) : Array(selectedItems![reqDocType]!.keys)
			for reqNamespace in reqNamespaces {
				let reqElementIdentifiers = haveDeviceRequest ? docReq!.itemsRequest.requestNameSpaces.nameSpaces[reqNamespace]!.elementIdentifiers : Array(selectedItems![reqDocType]![reqNamespace]!)
				guard let items = issuerNs[reqNamespace] else {
					nsErrorsToAdd[reqNamespace] = Dictionary(grouping: reqElementIdentifiers, by: {$0}).mapValues { _ in 0 }
					continue
				}
				let itemsReqSet = Set(reqElementIdentifiers)
				let itemsSet = Set(items.map(\.elementIdentifier))
				var itemsToAdd = items.filter({ itemsReqSet.contains($0.elementIdentifier) })
				if let selectedItems {
					let selectedNsItems = selectedItems[reqDocType]?[reqNamespace] ?? []
					itemsToAdd = itemsToAdd.filter({ selectedNsItems.contains($0.elementIdentifier) })
				}
				if itemsToAdd.count > 0 {
					nsItemsToAdd[reqNamespace] = itemsToAdd
					validReqItemsNsDict[reqNamespace] = itemsToAdd.map(\.elementIdentifier)
				}
				let errorItemsSet = itemsReqSet.subtracting(itemsSet)
				if errorItemsSet.count > 0 { 
					nsErrorsToAdd[reqNamespace] = Dictionary(grouping: errorItemsSet, by: { $0 }).mapValues { _ in 0 }
				}
			} // end ns for
			let issuerAuthToAdd = doc.issuerSigned.issuerAuth
			let issToAdd = IssuerSigned(issuerNameSpaces: IssuerNameSpaces(nameSpaces: nsItemsToAdd), issuerAuth: issuerAuthToAdd)
			var devSignedToAdd: DeviceSigned? = nil
			if let eReaderKey, let sessionEncryption {
				let authKeys = CoseKeyExchange(publicKey: eReaderKey, privateKey: devicePrivateKey)
				let mdocAuth = MdocAuthentication(transcript: sessionEncryption.transcript, authKeys: authKeys)
				guard let devAuth = try mdocAuth.getDeviceAuthForTransfer(docType: reqDocType) else {logger.error("Cannot create device auth"); return nil }
				devSignedToAdd = DeviceSigned(deviceAuth: devAuth)
			}
			let errors: Errors? = nsErrorsToAdd.count == 0 ? nil : Errors(errors: nsErrorsToAdd)
			let docToAdd = Document(docType: reqDocType, issuerSigned: issToAdd, deviceSigned: devSignedToAdd, errors: errors)
			docFiltered.append(docToAdd)
			validReqItemsDocDict[reqDocType] = validReqItemsNsDict
			errorReqItemsDocDict[reqDocType] = nsErrorsToAdd.mapValues { Array($0.keys) }
		} // end doc for
		let documentErrors: [DocumentError]? = docErrors.count == 0 ? nil : docErrors.map(DocumentError.init(docErrors:))
		deviceResponseToSend = DeviceResponse(version: docs.first!.version, documents: docFiltered, documentErrors: documentErrors, status: 0)
		validRequestItems = validReqItemsDocDict; errorRequestItems = errorReqItemsDocDict
		return deviceResponseToSend
	}
	
	public func getSessionDataToSend(_ deviceRequest: DeviceRequest, eReaderKey: CoseKey) -> Data? {
		do {
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return nil }
			guard let docToSend = deviceResponseToSend else { logger.error("Response to send not created"); return nil }
			if docToSend.documents == nil { logger.error("Could not create documents to send") }
			let cborToSend = docToSend.toCBOR(options: CBOROptions())
			let clearBytesToSend = cborToSend.encode()
			guard let cipherData = try sessionEncryption.encrypt(clearBytesToSend) else { return nil }
			let sd = SessionData(cipher_data: status == .error ? nil : cipherData, status: status == .error ? 0 : 20)
			return Data(sd.encode(options: CBOROptions()))
		} catch { self.error = error}
		return nil
	}
	
	public static func makeError(code: ErrorCode, str: String? = nil) -> NSError {
		let errorMessage = str ?? NSLocalizedString(code.description, comment: code.description)
		logger.error(Logger.Message(unicodeScalarLiteral: errorMessage))
		return NSError(domain: "\(MdocGattServer.self)", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: errorMessage])
	}
	
}
