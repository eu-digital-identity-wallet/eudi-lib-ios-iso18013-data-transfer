/*
Copyright (c) 2023 European Commission

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//  Helpers.swift
import Foundation
import CoreBluetooth
import Combine
import MdocDataModel18013
import MdocSecurity18013
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation
import SwiftCBOR
import Logging
import X509

public typealias RequestItems = [String: [NameSpace: [RequestItem]]]

/// Helper methods
public class MdocHelpers {
	
	static var errorNoDocumentsDescriptionKey: String { "doctype_not_found" }
	static func getErrorNoDocuments(_ docType: String) -> Error { NSError(domain: "\(MdocGattServer.self)", code: 0, userInfo: ["key": Self.errorNoDocumentsDescriptionKey, "%s": docType]) }
	
	public static func makeError(code: ErrorCode, str: String? = nil) -> NSError {
		let errorMessage = str ?? NSLocalizedString(code.description, comment: code.description)
		logger.error(Logger.Message(unicodeScalarLiteral: errorMessage))
		return NSError(domain: "\(MdocGattServer.self)", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: errorMessage, "key": code.description])
	}
	
	public static func getSessionDataToSend(sessionEncryption: SessionEncryption?, status: TransferStatus, docToSend: DeviceResponse) async -> Result<Data, Error> {
		do {
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return .failure(Self.makeError(code: .sessionEncryptionNotInitialized)) }
			if docToSend.documents == nil { logger.error("Could not create documents to send") }
			let cborToSend = docToSend.toCBOR(options: CBOROptions())
			let clearBytesToSend = cborToSend.encode()
			let cipherData = try await sessionEncryption.encrypt(clearBytesToSend)
			let sd = SessionData(cipher_data: status == .error ? nil : cipherData, status: status == .error ? 11 : 20)
			return .success(Data(sd.encode(options: CBOROptions())))
		} catch { return .failure(error) }
	}
	
	/// Decrypt the contents of a data object and return a ``DeviceRequest`` object if the data represents a valid device request. If the data does not represent a valid device request, the function returns nil.
	/// - Parameters:
	///   - deviceEngagement: deviceEngagement
	///   - docs: IssuerSigned documents
	///   - iaca: Root certificates trusted
	///   - devicePrivateKeys: Device private keys
	///   - dauthMethod: Method to perform mdoc authentication
	///   - handOver: handOver structure
	/// - Returns: A ``DeviceRequest`` object

	public static func decodeRequestAndInformUser(deviceEngagement: DeviceEngagement?, docs: [String: IssuerSigned], docDisplayNames: [String: [String: [String: String]]?], iaca: [SecCertificate], requestData: Data, devicePrivateKeys: [String: CoseKeyPrivate], dauthMethod: DeviceAuthMethod, unlockData: [String: Data], readerKeyRawData: [UInt8]?, handOver: CBOR) async -> Result<(sessionEncryption: SessionEncryption, deviceRequest: DeviceRequest, userRequestInfo: UserRequestInfo, isValidRequest: Bool), Error> {
		do {
			guard let seCbor = try CBOR.decode([UInt8](requestData)) else { logger.error("Request Data is not Cbor"); return .failure(Self.makeError(code: .requestDecodeError)) }
			guard var se = SessionEstablishment(cbor: seCbor) else { logger.error("Request Data cannot be decoded to session establisment"); return .failure(Self.makeError(code: .requestDecodeError)) }
			if se.eReaderKeyRawData == nil, let readerKeyRawData { se.eReaderKeyRawData = readerKeyRawData }
			guard se.eReaderKey != nil else { logger.error("Reader key not available"); return .failure(Self.makeError(code: .readerKeyMissing)) }
			let requestCipherData = se.data
			guard let deviceEngagement else { logger.error("Device Engagement not initialized"); return .failure(Self.makeError(code: .deviceEngagementMissing)) }
			// init session-encryption object from session establish message and device engagement, decrypt data
			let sessionEncryption = SessionEncryption(se: se, de: deviceEngagement, handOver: handOver)
			guard var sessionEncryption else { logger.error("Session Encryption not initialized"); return .failure(Self.makeError(code: .sessionEncryptionNotInitialized)) }
			guard let requestData = try await sessionEncryption.decrypt(requestCipherData) else { logger.error("Request data cannot be decrypted"); return .failure(Self.makeError(code: .requestDecodeError)) }
			guard let deviceRequest = DeviceRequest(data: requestData) else { logger.error("Decrypted data cannot be decoded"); return .failure(Self.makeError(code: .requestDecodeError)) }
			guard let (drTest, validRequestItems, errorRequestItems) = try await Self.getDeviceResponseToSend(deviceRequest: deviceRequest, issuerSigned: docs, docDisplayNames: docDisplayNames, selectedItems: nil, sessionEncryption: sessionEncryption, eReaderKey: sessionEncryption.sessionKeys.publicKey, devicePrivateKeys: devicePrivateKeys, dauthMethod: dauthMethod, unlockData: unlockData) else { logger.error("Valid request items nil"); return .failure(Self.makeError(code: .requestDecodeError)) }
			let bInvalidReq = (drTest.documents == nil)
			var userRequestInfo = UserRequestInfo(docDataFormats: docs.mapValues { _ in .cbor }, validItemsRequested: validRequestItems, errorItemsRequested: errorRequestItems)
			if let docR = deviceRequest.docRequests.first {
				let mdocAuth = MdocReaderAuthentication(transcript: sessionEncryption.transcript)
				if let readerAuthRawCBOR = docR.readerAuthRawCBOR, case let certData = docR.readerCertificates, certData.count > 0, let x509 = try? X509.Certificate(derEncoded: [UInt8](certData.first!)), let (b,reasonFailure) = try? mdocAuth.validateReaderAuth(readerAuthCBOR: readerAuthRawCBOR, readerAuthX5c: certData, itemsRequestRawData: docR.itemsRequestRawData!, rootCerts: iaca) {
					userRequestInfo.readerCertificateIssuer = MdocHelpers.getCN(from: x509.subject.description)
					userRequestInfo.readerAuthValidated = b
					if let reasonFailure {  userRequestInfo.readerCertificateValidationMessage = reasonFailure }
				}
			}
			return .success((sessionEncryption: sessionEncryption, deviceRequest: deviceRequest, userRequestInfo: userRequestInfo, isValidRequest: !bInvalidReq))
		} catch { return .failure(error) }
	}
	
	/// Construct ``DeviceResponse`` object to present from wallet data and input device request
	/// - Parameters:
	///   - deviceRequest: Device request coming from verifier
	///   - issuerSigned: Map of document ID to issuerSigned cbor data
	///   - selectedItems: Selected items from user (Map of Document ID to namespaced items)
	///   - sessionEncryption: Session Encryption data structure
	///   - eReaderKey: eReader (verifier) ephemeral public key
	///   - devicePrivateKeys: Device Private keys
	///   - sessionTranscript: Session Transcript object
	///   - dauthMethod: Mdoc Authentication method
	/// - Returns: (Device response object, valid requested items, error request items) tuple
	public static func getDeviceResponseToSend(deviceRequest: DeviceRequest?, issuerSigned: [String: IssuerSigned], docDisplayNames: [String: [String: [String: String]]?], selectedItems: RequestItems? = nil, sessionEncryption: SessionEncryption? = nil, eReaderKey: CoseKey? = nil, devicePrivateKeys: [String: CoseKeyPrivate], sessionTranscript: SessionTranscript? = nil, dauthMethod: DeviceAuthMethod, unlockData: [String: Data]) async throws -> (deviceResponse: DeviceResponse, validRequestItems: RequestItems, errorRequestItems: RequestItems)? {
		var docFiltered = [Document](); var docErrors = [[DocType: UInt64]]()
		var validReqItemsDocDict = RequestItems(); var errorReqItemsDocDict = RequestItems()
		guard deviceRequest != nil || selectedItems != nil else { fatalError("Invalid call") }
		let haveSelectedItems = selectedItems != nil
		// doc.id's (if have selected items), otherwise doc.types
		let reqDocIdsOrDocTypes = if haveSelectedItems { Array(selectedItems!.keys) } else { deviceRequest!.docRequests.map(\.itemsRequest.docType) }
		var docId: String?
		for reqDocIdOrDocType in reqDocIdsOrDocTypes {
			var docReq: DocRequest? // if selected items is null
			if haveSelectedItems == false {
				docReq = deviceRequest?.docRequests.findDoc(name: reqDocIdOrDocType)
				guard let pair = issuerSigned.first(where: { $1.issuerAuth.mso.docType == reqDocIdOrDocType}) else {
					docErrors.append([reqDocIdOrDocType: UInt64(0)])
					errorReqItemsDocDict[reqDocIdOrDocType] = [:]
					continue
				}
				docId = pair.key
			} else {
				guard issuerSigned[reqDocIdOrDocType] != nil else { continue }
			}
			let devicePrivateKey = devicePrivateKeys[reqDocIdOrDocType] // used only if doc.id
			let doc = if haveSelectedItems { issuerSigned[reqDocIdOrDocType]! } else { Array(issuerSigned.values).findDoc(name: reqDocIdOrDocType)!.0 }
			let displayNames = if haveSelectedItems { docDisplayNames[reqDocIdOrDocType] } else { docDisplayNames[docId!] }
			// Document's data must be in CBOR bytes that has the IssuerSigned structure according to ISO 23220-4
			// Currently, the library does not support IssuerSigned structure without the nameSpaces field.
			guard let issuerNs = doc.issuerNameSpaces else { logger.error("Document does not contain issuer namespaces"); return nil }
			var nsItemsToAdd = [NameSpace: [IssuerSignedItem]]()
			var nsErrorsToAdd = [NameSpace: ErrorItems]()
			var validReqItemsNsDict = [NameSpace: [RequestItem]]()
			// for each request namespace
			let reqNamespaces = if haveSelectedItems { Array(selectedItems![reqDocIdOrDocType]!.keys)} else {  Array(docReq!.itemsRequest.requestNameSpaces.nameSpaces.keys) }
			for reqNamespace in reqNamespaces {
				let reqElementIdentifiers = if haveSelectedItems { Array(selectedItems![reqDocIdOrDocType]![reqNamespace]!).map(\.elementIdentifier) } else { docReq!.itemsRequest.requestNameSpaces.nameSpaces[reqNamespace]!.elementIdentifiers }
				guard let items = issuerNs[reqNamespace] else {
					nsErrorsToAdd[reqNamespace] = Dictionary(grouping: reqElementIdentifiers, by: {$0}).mapValues { _ in 0 }
					continue
				}
				var itemsReqSet = Set(reqElementIdentifiers)
				if haveSelectedItems == false { itemsReqSet = itemsReqSet.subtracting(IsoMdlModel.self.moreThan2AgeOverElementIdentifiers(reqDocIdOrDocType, reqNamespace, SimpleAgeAttest(namespaces: issuerNs.nameSpaces), reqElementIdentifiers)) }
				let itemsSet = Set(items.map(\.elementIdentifier))
				var itemsToAdd = items.filter({ itemsReqSet.contains($0.elementIdentifier) })
				if let selectedItems {
					let selectedNsItems = selectedItems[reqDocIdOrDocType]?[reqNamespace] ?? []
					itemsToAdd = itemsToAdd.filter({ selectedNsItems.map(\.elementIdentifier).contains($0.elementIdentifier) })
				}
				if itemsToAdd.count > 0 {
					nsItemsToAdd[reqNamespace] = itemsToAdd
					validReqItemsNsDict[reqNamespace] = itemsToAdd.map { RequestItem(elementIdentifier: $0.elementIdentifier, displayName: displayNames??[reqNamespace]?[$0.elementIdentifier], intentToRetain: docReq?.itemsRequest.requestNameSpaces.nameSpaces[reqNamespace]?.dataElements[$0.elementIdentifier], isOptional: nil) }
				}
				let errorItemsSet = itemsReqSet.subtracting(itemsSet)
				if errorItemsSet.count > 0 {
					nsErrorsToAdd[reqNamespace] = Dictionary(grouping: errorItemsSet, by: { $0 }).mapValues { _ in 0 }
				}
			} // end ns for
			let errors: Errors? = nsErrorsToAdd.count == 0 ? nil : Errors(errors: nsErrorsToAdd)
			if nsItemsToAdd.count > 0 {
				let issuerAuthToAdd = doc.issuerAuth
				let issToAdd = IssuerSigned(issuerNameSpaces: IssuerNameSpaces(nameSpaces: nsItemsToAdd), issuerAuth: issuerAuthToAdd)
				var devSignedToAdd: DeviceSigned? = nil
				let sessionTranscript = sessionEncryption?.transcript ?? sessionTranscript
				if let eReaderKey, let sessionTranscript, let devicePrivateKey {
					let authKeys = CoseKeyExchange(publicKey: eReaderKey, privateKey: devicePrivateKey)
					let mdocAuth = MdocAuthentication(transcript: sessionTranscript, authKeys: authKeys)
					guard let devAuth = try await mdocAuth.getDeviceAuthForTransfer(docType: doc.issuerAuth.mso.docType, dauthMethod: dauthMethod, unlockData: unlockData[reqDocIdOrDocType]) else {
						logger.error("Cannot create device auth"); return nil
					}
					devSignedToAdd = DeviceSigned(deviceAuth: devAuth)
				}
				let docToAdd = Document(docType: doc.issuerAuth.mso.docType, issuerSigned: issToAdd, deviceSigned: devSignedToAdd, errors: errors)
				docFiltered.append(docToAdd)
				validReqItemsDocDict[doc.issuerAuth.mso.docType] = validReqItemsNsDict
			} else {
				docErrors.append([doc.issuerAuth.mso.docType: UInt64(0)])
			}
			errorReqItemsDocDict[doc.issuerAuth.mso.docType] = nsErrorsToAdd.mapValues { $0.keys.map(RequestItem.init) }
		} // end doc for
		let documentErrors: [DocumentError]? = docErrors.count == 0 ? nil : docErrors.map(DocumentError.init(docErrors:))
		let documentsToAdd = docFiltered.count == 0 ? nil : docFiltered
		let deviceResponseToSend = DeviceResponse(version: DeviceResponse.defaultVersion, documents: documentsToAdd, documentErrors: documentErrors, status: 0)
		return (deviceResponseToSend, validReqItemsDocDict, errorReqItemsDocDict)
	}
	
	/// Returns the number of blocks that dataLength bytes of data can be split into, given a maximum block size of maxBlockSize bytes.
	/// - Parameters:
	///   - dataLength: Length of data to be split
	///   - maxBlockSize: The maximum block size
	/// - Returns: Number of blocks 
	public static func CountNumBlocks(dataLength: Int, maxBlockSize: Int) -> Int {
		let blockSize = maxBlockSize
		var numBlocks = 0
		if dataLength > maxBlockSize {
			numBlocks = dataLength / blockSize;
			if numBlocks * blockSize < dataLength {
				numBlocks += 1
			}
		} else if dataLength > 0 {
			numBlocks = 1
		}
		return numBlocks
	}
	
	/// Creates a block for a given block id from a data object. The block size is limited to maxBlockSize bytes.
	/// - Parameters:
	///   - data: The data object to be sent
	///   - blockId: The id (number) of the block to be sent
	///   - maxBlockSize: The maximum block size
	/// - Returns: (chunk:The data block, bEnd: True if this is the last block, false otherwise)
	public static func CreateBlockCommand(data: Data, blockId: Int, maxBlockSize: Int) -> (Data, Bool) {
		let start = blockId * maxBlockSize
		var end = (blockId+1) * maxBlockSize
		var bEnd = false
		if end >= data.count {
			end = data.count
			bEnd = true
		}
		let chunk = data.subdata(in: start..<end)
		return (chunk,bEnd)
	}
	
	#if os(iOS)
	
	/// Check if BLE access is allowed, and if not, present a dialog that opens settings
	/// - Parameters:
	///   - vc: The view controller that will present the settings
	///   - action: The action to perform
	@MainActor
	public static func checkBleAccess(_ vc: UIViewController, action: @escaping ()->Void) {
		switch CBManager.authorization {
		case .denied:
			// "Denied, request permission from settings"
			presentSettings(vc, msg: NSLocalizedString("Bluetooth access is denied", comment: ""))
		case .restricted:
			logger.warning("Restricted, device owner must approve")
		case .allowedAlways:
			// "Authorized, proceed"
			DispatchQueue.main.async { action() }
		case .notDetermined:
			DispatchQueue.main.async { action() }
		@unknown default:
			logger.info("Unknown authorization status")
		}
	}
	
	/// Check if the user has given permission to access the camera. If not, ask them to go to the settings app to give permission.
	/// - Parameters:
	///   - vc:  The view controller that will present the settings
	///   - action: The action to perform
	@MainActor
	public static func checkCameraAccess(_ vc: UIViewController, action: @escaping ()->Void) {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .denied:
			// "Denied, request permission from settings"
			presentSettings(vc, msg: NSLocalizedString("Camera access is denied", comment: ""))
		case .restricted:
			logger.warning("Restricted, device owner must approve")
		case .authorized:
			// "Authorized, proceed"
			DispatchQueue.main.async { action() }
		case .notDetermined:
			AVCaptureDevice.requestAccess(for: .video) { success in
				if success {
					DispatchQueue.main.async { action() }
				} else {
					logger.info("Permission denied")
				}
			}
		@unknown default:
			logger.info("Unknown authorization status")
		}
	}
	
	/// Present an alert controller with a message, and two actions, one to cancel, and one to go to the settings page.
	/// - Parameters:
	///   - vc: The view controller that will present the settings
	///   - msg: The message to show
	@MainActor
	public static func presentSettings(_ vc: UIViewController, msg: String) {
		let alertController = UIAlertController(title: NSLocalizedString("error", comment: ""), message: msg, preferredStyle: .alert)
		alertController.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .default))
		alertController.addAction(UIAlertAction(title: NSLocalizedString("settings", comment: ""), style: .cancel) { _ in
			if let url = URL(string: UIApplication.openSettingsURLString) {
				UIApplication.shared.open(url, options: [:], completionHandler: { _ in
					// Handle
				})
			}
		})
		vc.present(alertController, animated: true)
	}
	
	/// Finds the top view controller in the view hierarchy of the app. It is used to present a new view controller on top of any existing view controllers.
	@MainActor
	public static func getTopViewController(base: UIViewController? = UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController) -> UIViewController? {
		if let nav = base as? UINavigationController {
			return getTopViewController(base: nav.visibleViewController)
		} else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
			return getTopViewController(base: selected)
		} else if let presented = base?.presentedViewController {
			return getTopViewController(base: presented)
		}
		return base
	}
	
	#endif

	/// Get the common name (CN) from the certificate distringuished name (DN)
	public static func getCN(from dn: String) -> String  {
			let regex = try! NSRegularExpression(pattern: "CN=([^,]+)")
			if let match = regex.firstMatch(in: dn, range: NSRange(location: 0, length: dn.count)) {
				if let r = Range(match.range(at: 1), in: dn) {
					return String(dn[r])
				}
			}
			return dn
		}
}
