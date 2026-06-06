/*
Copyright (c) 2026 European Commission

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

public typealias RequestItems = [DocType: [NameSpace: [RequestItem]]]

public typealias RequestTransactionData = [DocType: RequestTransactionDataItem]

/// Helper methods
public class MdocHelpers {

	static var errorNoDocumentsDescriptionKey: String { "doctype_not_found" }
	public static func getErrorNoDocuments(_ docType: String) -> Error {
		let userInfo: [String: String] = [
			"key": Self.errorNoDocumentsDescriptionKey,
			"%s": docType
		]
		return NSError(domain: "\(MdocGattServer.self)", code: 0, userInfo: userInfo)
	}

	public static func makeError(code: ErrorCode, str: String? = nil) -> NSError {
		let errorMessage = str ?? NSLocalizedString(code.description, comment: code.description)
		logger.error(Logger.Message(unicodeScalarLiteral: errorMessage))
		let userInfo: [String: String] = [
			NSLocalizedDescriptionKey: errorMessage,
			"key": code.description
		]
		return NSError(domain: "\(MdocGattServer.self)", code: code.rawValue, userInfo: userInfo)
	}

	/// Get the session data to send to the reader. The session data is encrypted using the session encryption object
	/// - Parameters:
	///   - sessionEncryption: Instance of session encryption object
	///   - status: Transfer status
	///   - docToSend: Device response object to send
	///
	/// - Returns: A tuple containing the encrypted session data and the clear text data to send.
	public static func getSessionDataToSend(
		sessionEncryption: SessionEncryption?,
		status: TransferStatus,
		docToSend: DeviceResponse
	) async -> Result<(Data, Data), Error> {
		do {
			guard var sessionEncryption else {
				logger.error("Session Encryption not initialized")
				return .failure(Self.makeError(code: .sessionEncryptionNotInitialized))
			}
			if docToSend.documents == nil, status != .error { logger.error("Could not create documents to send") }
			let cborToSend = docToSend.toCBOR(options: CBOROptions())
			let clearBytesToSend = cborToSend.encode()
			let cipherData = try await sessionEncryption.encrypt(clearBytesToSend)
			let sd = SessionData(cipher_data: status == .error ? nil : cipherData, status: status == .error ? 11 : 20)
			return .success((Data(sd.encode(options: CBOROptions())), Data(clearBytesToSend)))
		} catch { return .failure(error) }
	}

	/// Decrypt the contents of a data object and return a ``DeviceRequest``
	/// if the data represents a valid device request.
	/// If not, the function returns nil.
	/// - Parameters:
	///   - deviceEngagement: deviceEngagement
	///   - docs: IssuerSigned documents
	///   - docMetadata: Document metadata
	///   - iaca: Root certificates trusted
	///   - devicePrivateKeys: Device private keys
	///   - dauthMethod: Method to perform mdoc authentication
	///   - handOver: handOver structure
	/// - Returns: A ``DeviceRequest`` object

	public static func decodeRequestAndInformUser(
		deviceEngagement: DeviceEngagement?,
		docs: [String: IssuerSigned],
		docMetadata: [String: Data],
		iaca: [x5chain],
		requestData: Data,
		privateKeyObjects: [String: CoseKeyPrivate],
		dauthMethod: DeviceAuthMethod,
		unlockData: [String: Data],
		readerKeyRawData: [UInt8]?,
		handOver: CBOR
	) async -> Result<(
		sessionEncryption: SessionEncryption,
		deviceRequest: DeviceRequest,
		userRequestInfo: UserRequestInfo,
		isValidRequest: Bool
	), Error> {
		do {
			guard let seCbor = try CBOR.decode([UInt8](requestData)) else {
				logger.error("Request Data is not Cbor")
				return .failure(Self.makeError(code: .requestDecodeError))
			}
			var se = try SessionEstablishment(cbor: seCbor)
			if se.eReaderKeyRawData == nil, let readerKeyRawData { se.eReaderKeyRawData = readerKeyRawData }
			guard se.eReaderKey != nil else {
				logger.error("Reader key not available")
				return .failure(Self.makeError(code: .readerKeyMissing))
			}
			let requestCipherData = se.data
			guard let deviceEngagement else {
				logger.error("Device Engagement not initialized")
				return .failure(Self.makeError(code: .deviceEngagementMissing))
			}
			// init session-encryption object from session establish message and device engagement, decrypt data
			let sessionEncryption = SessionEncryption(se: se, de: deviceEngagement, handOver: handOver)
			guard var sessionEncryption else {
				logger.error("Session Encryption not initialized")
				return .failure(Self.makeError(code: .sessionEncryptionNotInitialized))
			}
			let requestData = try await sessionEncryption.decrypt(requestCipherData)
			let deviceRequest = try DeviceRequest(data: requestData)
			let requestResponse = try await Self.getDeviceResponseToSend(
				deviceRequest: deviceRequest,
				issuerSigned: docs,
				docMetadata: docMetadata,
				selectedItems: nil,
				sessionEncryption: sessionEncryption,
				eReaderKey: sessionEncryption.sessionKeys.publicKey,
				privateKeyObjects: privateKeyObjects,
				dauthMethod: dauthMethod,
				unlockData: unlockData
			)
			guard let (previewDeviceResponse, validRequestItems, _, _, _, _) = requestResponse else {
				logger.error("Valid request items nil")
				return .failure(Self.makeError(code: .requestDecodeError))
			}
			let isInvalidRequest = (previewDeviceResponse.documents == nil)
			let requestedDocDataFormats = docs.mapValues { _ in DocDataFormat.cbor }
			var userRequestInfo = UserRequestInfo(
				docDataFormats: requestedDocDataFormats,
				itemsRequested: validRequestItems,
				deviceRequestBytes: Data(requestData)
			)
			for docR in deviceRequest.docRequests {
				let mdocAuth = MdocReaderAuthentication(transcript: sessionEncryption.sessionTranscript)
				let readerValidation: ReaderAuthenticationResult
				if let readerAuthRawCBOR = docR.readerAuthRawCBOR {
					let authBytes = Data(readerAuthRawCBOR.encode())
					let certData = docR.readerCertificates
					if certData.count > 0, let x509 = try? X509.Certificate(derEncoded: [UInt8](certData.first!)) {
						let certificateIssuer = MdocHelpers.getCN(from: x509.subject.description)
						do {
							let itemsRequestRawData = docR.itemsRequestRawData!
							let (isValidated, validationMessage) = try mdocAuth.validateReaderAuth(
								readerAuthCBOR: readerAuthRawCBOR,
								readerAuthX5c: certData,
								itemsRequestRawData: itemsRequestRawData,
								rootIaca: iaca
							)
							readerValidation = ReaderAuthenticationResult(
								isValidated: isValidated,
								certificateIssuer: certificateIssuer,
								validationMessage: validationMessage,
								authBytes: authBytes,
								certificateChain: certData
							)
						} catch {
							logger.warning("Reader auth validation failed: \(error.localizedDescription)")
							let failureDescription = "Reader auth validation failed: \(error.localizedDescription)"
							readerValidation = ReaderAuthenticationResult(
								isValidated: false,
								certificateIssuer: certificateIssuer,
								validationMessage: failureDescription,
								authBytes: authBytes,
								certificateChain: certData
							)
						}
					} else {
						logger.warning("Reader certificate missing or malformed")
						readerValidation = ReaderAuthenticationResult(
							isValidated: false,
							validationMessage: "Reader certificate missing or malformed",
							authBytes: authBytes
						)
					}
				} else {
					logger.warning("Reader authentication not present in request")
					readerValidation = ReaderAuthenticationResult(
						isValidated: false,
						validationMessage: "Reader authentication not present in request"
					)
				}
				userRequestInfo.readerAuthResults[docR.itemsRequest.docType] = readerValidation
			}
				return .success((
					sessionEncryption: sessionEncryption,
					deviceRequest: deviceRequest,
					userRequestInfo: userRequestInfo,
					isValidRequest: !isInvalidRequest
				))
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
	public static func getDeviceResponseToSend(
		deviceRequest: DeviceRequest?,
		issuerSigned: [DocType: IssuerSigned],
		docMetadata: [DocType: Data],
		selectedItems: RequestItems? = nil,
		sessionEncryption: SessionEncryption? = nil,
		eReaderKey: CoseKey? = nil,
		privateKeyObjects: [DocType: CoseKeyPrivate],
		sessionTranscript: SessionTranscript? = nil,
		dauthMethod: DeviceAuthMethod,
		unlockData: [DocType: Data],
		zkSpecsRequested: [DocType: [ZkSystemSpec]]? = nil,
		zkSystemRepository: ZkSystemRepository? = nil,
		deviceNameSpacesRequested: [DocType: DeviceNameSpaces]? = nil
	) async throws -> (
		deviceResponse: DeviceResponse,
		validRequestItems: RequestItems,
		errorRequestItems: RequestItems,
		responseMetadata: [Data?],
		documentIds: [String],
		zkpDocumentIds: [String]
	)? {
		var docFiltered = [Document](); var docIdsFiltered = [String]();
		var docErrors = [[DocType: UInt64]]()
		var validReqItemsDocDict = RequestItems(); var errorReqItemsDocDict = RequestItems()
		var resMetadata = [Data?]()
		guard deviceRequest != nil || selectedItems != nil else { fatalError("Invalid call") }
		let sessionTranscript = sessionEncryption?.sessionTranscript ?? sessionTranscript
		let haveSelectedItems = selectedItems != nil
		// doc.id's (if have selected items), otherwise doc.types
		let reqDocIdsOrDocTypes = if haveSelectedItems {
			Array(selectedItems!.keys)
		} else {
			deviceRequest!.docRequests.map(\.itemsRequest.docType)
		}
		var docId: String?
		for reqDocIdOrDocType in reqDocIdsOrDocTypes {
			var docReq: DocRequest? // if selected items is null
			if haveSelectedItems == false {
				docReq = deviceRequest?.docRequests.findDoc(name: reqDocIdOrDocType)
				guard let issuerSignedPair = issuerSigned.first(
					where: { $1.issuerAuth.mso.docType == reqDocIdOrDocType }
				) else {
					docErrors.append([reqDocIdOrDocType: UInt64(0)])
					errorReqItemsDocDict[reqDocIdOrDocType] = [:]
					continue
				}
				docId = issuerSignedPair.key
			} else {
				guard issuerSigned[reqDocIdOrDocType] != nil else { continue }
			}
			let documentToRespond = if haveSelectedItems {
				issuerSigned[reqDocIdOrDocType]!
			} else {
				Array(issuerSigned.values).findDoc(name: reqDocIdOrDocType)!.0
			}
			let privateKeyObject = if haveSelectedItems {
				privateKeyObjects[reqDocIdOrDocType]
			} else {
				privateKeyObjects[docId!]
			}
			let documentMetadata = if haveSelectedItems {
				docMetadata[reqDocIdOrDocType]
			} else {
				docMetadata[docId!]
			}
			resMetadata.append(documentMetadata)
			// Document's data must be in CBOR bytes that has the IssuerSigned structure according to ISO 23220-4
			// Currently, the library does not support IssuerSigned structure without the nameSpaces field.
			guard let issuerNs = documentToRespond.issuerNameSpaces else {
				logger.error("Document does not contain issuer namespaces")
				return nil
			}
			var nsItemsToAdd = [NameSpace: [IssuerSignedItem]]()
			var nsErrorsToAdd = [NameSpace: ErrorItems]()
			var validReqItemsNsDict = [NameSpace: [RequestItem]]()
			// for each request namespace
			let docSelectedItems: [NameSpace: [RequestItem]]? = if haveSelectedItems {
				selectedItems![reqDocIdOrDocType]
			} else {
				nil
			}
			let reqNamespaces: [String] = if haveSelectedItems {
				if !docSelectedItems!.isEmpty {
					Array(docSelectedItems!.keys)
				} else {
					Array(issuerNs.nameSpaces.keys)
				}
			} else {
				Array(docReq!.itemsRequest.requestNameSpaces.nameSpaces.keys)
			}
			for reqNamespace in reqNamespaces {
				let reqElementIdentifiers: [String] = if haveSelectedItems {
					if !docSelectedItems!.isEmpty {
						Array(docSelectedItems![reqNamespace]!).map(\.elementIdentifier)
					} else {
						Array(issuerNs.nameSpaces[reqNamespace]!.map(\.elementIdentifier))
					}
				} else {
					docReq!.itemsRequest.requestNameSpaces.nameSpaces[reqNamespace]!.elementIdentifiers
				}
				guard let items = issuerNs[reqNamespace] else {
					nsErrorsToAdd[reqNamespace] = Dictionary(grouping: reqElementIdentifiers, by: {$0}).mapValues { _ in 0 }
					continue
				}
				var itemsReqSet = Set(reqElementIdentifiers)
				if haveSelectedItems == false {
					let simpleAgeAttestation = SimpleAgeAttest(namespaces: issuerNs.nameSpaces)
					let ageOverElementIdentifiers = IsoMdlModel.self.moreThan2AgeOverElementIdentifiers(
						reqDocIdOrDocType,
						reqNamespace,
						simpleAgeAttestation,
						reqElementIdentifiers
					)
					itemsReqSet = itemsReqSet.subtracting(ageOverElementIdentifiers)
				}
				let itemsSet = Set(items.map(\.elementIdentifier))
				var itemsToAdd = items.filter({ itemsReqSet.contains($0.elementIdentifier) })
				if haveSelectedItems {
					itemsToAdd = itemsToAdd.filter({ reqElementIdentifiers.contains($0.elementIdentifier) })
				}
				if itemsToAdd.count > 0 {
					nsItemsToAdd[reqNamespace] = itemsToAdd
					let retainedElementsById = docReq?
						.itemsRequest
						.requestNameSpaces
						.nameSpaces[reqNamespace]?
						.dataElements
					validReqItemsNsDict[reqNamespace] = itemsToAdd.map { item in
						let intentToRetain = retainedElementsById?[item.elementIdentifier]
						return RequestItem(
							elementIdentifier: item.elementIdentifier,
							intentToRetain: intentToRetain,
							isOptional: nil
						)
					}
				}
				let errorItemsSet = itemsReqSet.subtracting(itemsSet)
				if errorItemsSet.count > 0 {
					nsErrorsToAdd[reqNamespace] = Dictionary(grouping: errorItemsSet, by: { $0 }).mapValues { _ in 0 }
				}
			} // end ns for
			let errors: Errors? = nsErrorsToAdd.isEmpty ? nil : Errors(errors: nsErrorsToAdd)
			if nsItemsToAdd.count > 0 {
				let issuerAuthToAdd = documentToRespond.issuerAuth
				let issuerNameSpacesToAdd = IssuerNameSpaces(nameSpaces: nsItemsToAdd)
				let issuerSignedToAdd = IssuerSigned(
					issuerNameSpaces: issuerNameSpacesToAdd,
					issuerAuth: issuerAuthToAdd
				)
				var devSignedToAdd: DeviceSigned? = nil
				if let sessionTranscript, let privateKeyObject {
					let deviceNameSpacesToAdd = deviceNameSpacesRequested?[reqDocIdOrDocType]
					if let deviceNameSpacesToAdd {
						let keyAuthorizations = issuerAuthToAdd.mso.deviceKeyInfo.keyAuthorizations
						
						for (_, element) in deviceNameSpacesToAdd.deviceNameSpaces.enumerated() {
							let namespace = element.key
							let deviceSignedItems = element.value
							
							// Check if issuer auth authorizes entire namespace
							if (keyAuthorizations?.nameSpaces?.contains(namespace) == true) {
								continue
							}
							
							// Check if issuer auth authorizes all device signed items
							for deviceSignedItem in deviceSignedItems.deviceSignedItems {
								if (keyAuthorizations?.dataElements?.contains(where: { $0.key == namespace && $0.value.contains(deviceSignedItem.key)}) != true) {
									logger.error(
										"Requested device namespace is not authorized by issuer auth",
										metadata: [
											"reqDocIdOrDocType": .string(reqDocIdOrDocType),
											"deviceNameSpace": .string(namespace),
											"deviceSignedItem": .string(deviceSignedItem.key)
										]
									)
									
									return nil
								}
							}
						}
					}
					let authKeys = CoseKeyExchange(publicKey: eReaderKey, privateKey: privateKeyObject)
					let mdocAuth = MdocAuthentication(sessionTranscript: sessionTranscript, authKeys: authKeys)
					let unlockPayload = unlockData[reqDocIdOrDocType]
					guard let devAuth = try await mdocAuth.getDeviceAuthForTransfer(
						docType: documentToRespond.issuerAuth.mso.docType,
						dauthMethod: dauthMethod,
						deviceNameSpaces: deviceNameSpacesToAdd,
						unlockData: unlockPayload,
					) else {
						logger.error("Cannot create device auth"); return nil
					}
					devSignedToAdd = DeviceSigned(deviceAuth: devAuth)
				}
				guard let devSignedToAdd else { logger.error("Cannot create device signed"); continue }
				let docToAdd = Document(
					docType: documentToRespond.issuerAuth.mso.docType,
					issuerSigned: issuerSignedToAdd,
					deviceSigned: devSignedToAdd,
					errors: errors
				)
				docFiltered.append(docToAdd)
				docIdsFiltered.append(reqDocIdOrDocType)
				validReqItemsDocDict[documentToRespond.issuerAuth.mso.docType] = validReqItemsNsDict
			} else {
				docErrors.append([documentToRespond.issuerAuth.mso.docType: UInt64(0)])
			}
			errorReqItemsDocDict[documentToRespond.issuerAuth.mso.docType] =
				nsErrorsToAdd.mapValues { $0.keys.map(RequestItem.init) }
		} // end doc for
		let documentErrors: [DocumentError]? = docErrors.isEmpty ? nil : docErrors.map(DocumentError.init(docErrors:))
		let documentsToAdd = docFiltered.isEmpty ? nil : docFiltered
		var deviceResponseToSend = DeviceResponse(documents: documentsToAdd, documentErrors: documentErrors, status: 0)
		var documentIds = docIdsFiltered
		var zkpDocumentIds: [String] = []
		if let zkSystemRepository, let sessionTranscript, haveSelectedItems, docFiltered.count > 0 {
			let zkSpecsByDocType = zkSpecsRequested ?? deviceRequest?.docRequests.reduce(into: [:]) { result, docReq in
				if let specs = docReq.itemsRequest.requestInfo?.zkRequest?.systemSpecs {
					result[docReq.itemsRequest.docType] = specs
				}
			}
			if let zkSpecsByDocType {
				(deviceResponseToSend, documentIds, zkpDocumentIds) = try await transformDeviceResponseWithZkp(
					zkSystemRepository: zkSystemRepository,
					zkSpecsByDocType: zkSpecsByDocType,
					deviceResponse: deviceResponseToSend,
					sessionTranscript: sessionTranscript,
					docIdsFiltered: docIdsFiltered
				)
			}
		}
		return (deviceResponseToSend, validReqItemsDocDict, errorReqItemsDocDict, resMetadata, documentIds, zkpDocumentIds)
	}

	/// Prepares data blocks to be sent over BLE.	
	static func prepareDataBlocksToSend(_ msg: Data, blockSize: Int) -> [Data] {
		var sendBuffer = [Data]()
		var numBlocks: Int = 0
		numBlocks = MdocHelpers.countNumBlocks(dataLength: msg.count, maxBlockSize: blockSize)
		logger.info("Sending response of total bytes \(msg.count) in \(numBlocks) blocks and block size: \(blockSize)")
		sendBuffer.removeAll()
		// send blocks
		for i in 0..<numBlocks {
			let (block,bEnd) = MdocHelpers.createBlockCommand(data: msg, blockId: i, maxBlockSize: blockSize)
			var blockWithHeader = Data()
			blockWithHeader.append(contentsOf: !bEnd ? BleTransferMode.START_DATA : BleTransferMode.END_DATA)
			// send actual data after header
			blockWithHeader.append(contentsOf: block)
			sendBuffer.append(blockWithHeader)
		}
		return sendBuffer
	}

	/// Returns the number of blocks that `dataLength` bytes can be split into,
	/// given a maximum block size of `maxBlockSize` bytes.
	/// - Parameters:
	///   - dataLength: Length of data to be split
	///   - maxBlockSize: The maximum block size
	/// - Returns: Number of blocks
	public static func countNumBlocks(dataLength: Int, maxBlockSize: Int) -> Int {
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
	/// - Returns: (chunk:The data block, isLastBlock: true if this is the last block)
	public static func createBlockCommand(
		data: Data,
		blockId: Int,
		maxBlockSize: Int
	) -> (Data, Bool) {
		let start = blockId * maxBlockSize
		var end = (blockId+1) * maxBlockSize
		var isLastBlock = false
		if end >= data.count {
			end = data.count
			isLastBlock = true
		}
		let chunk = data.subdata(in: start..<end)
		return (chunk, isLastBlock)
	}

	/// Returns the number of attributes requested in a document
	/// - Parameter document: The document to count attributes from
	/// - Returns: The number of requested attributes
	public static func numAttributesRequested(
		for document: Document
	) -> Int {
		guard let issuerNs = document.issuerSigned.issuerNameSpaces else { return 0 }
		return issuerNs.nameSpaces.values.reduce(0) { $0 + $1.count }
	}

	/// Find the matched zero-knowledge proof system for the DocRequest.
    ///
    /// - Parameters:
    ///   - zkSystemRepository: the zero-knowledge proof system repository
    /// - Returns: the matched zero-knowledge proof system and its specification, or nil if none found
	public static func findMatchedZkSystem(
		document: Document,
		zkSystemSpecs: [ZkSystemSpec],
		zkSystemRepository: ZkSystemRepository
	) -> (any ZkSystemProtocol, ZkSystemSpec)? {
        guard !zkSystemSpecs.isEmpty else { return nil }
        return zkSystemSpecs.lazy.compactMap { zkSpec -> (any ZkSystemProtocol, ZkSystemSpec)? in
            guard let system = zkSystemRepository.lookup(zkSpec.system) else { return nil }
            let numAttributes = Int64(numAttributesRequested(for: document))
			guard let spec = system.getMatchingSystemSpec(
				zkSystemSpecs: zkSystemSpecs,
				numAttributesRequested: numAttributes
			) else { return nil }
            return (system, spec) }.first
    }

	/// Transform a DeviceResponse by replacing Documents with ZkDocuments where applicable
	///
	/// - Parameters:
	///   - zkSystemRepository: The zero-knowledge proof system repository
	///   - zkSpecsByDocType: Map of document type to its zero-knowledge system specs
	///   - deviceResponse: The device response to transform
	///   - sessionTranscript: The session transcript
	/// - Returns: A transformed DeviceResponse with ZkDocuments where applicable
	public static func transformDeviceResponseWithZkp(
		zkSystemRepository: ZkSystemRepository,
		zkSpecsByDocType: [DocType: [ZkSystemSpec]],
		deviceResponse: DeviceResponse,
		sessionTranscript: SessionTranscript,
		docIdsFiltered: [String]
	) async throws -> (deviceResponse: DeviceResponse, documentIds: [String], zkpDocumentIds: [String]) {
		guard let documents = deviceResponse.documents else { return (deviceResponse, [], []) }
		var zkpDocumentIds = [String]()
		var documents2 = [Document]()
		var documentIds = docIdsFiltered
		var zkDocuments = [ZkDocument]()
		for (index, document) in documents.enumerated() {
			// Find matching ZK system specs for this document's docType
			guard let zkSystemSpecs = zkSpecsByDocType[document.docType],
				let (zkSystem, zkSpec) = findMatchedZkSystem(
					document: document,
					zkSystemSpecs: zkSystemSpecs,
					zkSystemRepository: zkSystemRepository
				)
			else {
				documents2.append(document)
				continue
			}
			let dr = documents.count == 1 ? deviceResponse : getSingleDocumentDeviceResponse(document: document)
			let docBytes = dr.toCBOR(options: CBOROptions()).encode()
			// Generate ZkDocument — fail closed if proof generation fails when ZKP is matched
			let sessionTranscriptBytes = sessionTranscript.encode(options: CBOROptions())
			let zkDocument = try zkSystem.generateProof(
				zkSystemSpec: zkSpec,
				docBytes: docBytes,
				x: nil,
				y: nil,
				sessionTranscriptBytes: sessionTranscriptBytes,
				timestamp: Date()
			)
			zkDocuments.append(zkDocument)
			zkpDocumentIds.append(docIdsFiltered[index])
			documentIds.removeAll { $0 == docIdsFiltered[index] }
		}
		guard !zkDocuments.isEmpty else { return (deviceResponse, documentIds, zkpDocumentIds) }
		let transformedResponse = DeviceResponse(
			documents: documents2,
			zkDocuments: zkDocuments,
			documentErrors: deviceResponse.documentErrors,
			status: deviceResponse.status
		)
		return (transformedResponse, documentIds, zkpDocumentIds)
	}

	public static func getSingleDocumentDeviceResponse(document: Document) -> DeviceResponse {
		return DeviceResponse(documents: [document], documentErrors: nil, status: 0)
	}

	#if os(iOS)

	/// Check if BLE access is allowed, and if not, present a dialog that opens settings
	/// - Parameters:
	///   - vc: The view controller that will present the settings
	///   - action: The action to perform
	@MainActor
	public static func checkBleAccess(
		_ vc: UIViewController,
		action: @MainActor @escaping () -> Void
	) {
		switch CBManager.authorization {
		case .denied:
			// "Denied, request permission from settings"
			presentSettings(vc, msg: NSLocalizedString("Bluetooth access is denied", comment: ""))
		case .restricted:
			logger.warning("Restricted, device owner must approve")
		case .allowedAlways:
			// "Authorized, proceed"
			action()
		case .notDetermined:
			action()
		@unknown default:
			logger.info("Unknown authorization status")
		}
	}

	/// Check if camera permission is granted.
	/// If not, ask the user to go to Settings and allow access.
	/// - Parameters:
	///   - vc:  The view controller that will present the settings
	///   - action: The action to perform
	@MainActor
	public static func checkCameraAccess(
		_ vc: UIViewController,
		action: @MainActor @escaping () -> Void
	) {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .denied:
			// "Denied, request permission from settings"
			presentSettings(vc, msg: NSLocalizedString("Camera access is denied", comment: ""))
		case .restricted:
			logger.warning("Restricted, device owner must approve")
		case .authorized:
			// "Authorized, proceed"
			action()
		case .notDetermined:
			AVCaptureDevice.requestAccess(for: .video) { success in
				if success {
					Task { @MainActor in action() }
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
	public static func presentSettings(
		_ vc: UIViewController,
		msg: String
	) {
		let alertTitle = NSLocalizedString("error", comment: "")
		let alertController = UIAlertController(
			title: alertTitle,
			message: msg,
			preferredStyle: .alert
		)
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

	#endif

	public static func getPrivateKeys(
		_ docKeyInfos: [String: Data?],
		_ documentKeyIndexes: [String: Int]
	) async throws -> [String: CoseKeyPrivate] {
		let privateKeyObjects: [String: CoseKeyPrivate] = try await Dictionary(
			uniqueKeysWithValues: docKeyInfos.asyncCompactMap {
			guard let docKeyInfo = DocKeyInfo(from: $0.value),
				let keyIndex = documentKeyIndexes[$0.key]
			else { return nil }
			let secureArea = SecureAreaRegistry.shared.get(name: docKeyInfo.secureAreaName)
			let (_, curve) = try await secureArea.getInfoAndCurve(id: $0.key)
			let coseKeyPrivate = try await CoseKeyPrivate(
				privateKeyId: $0.key,
				index: keyIndex,
				secureArea: secureArea,
				curve: curve
			)
			return ($0.key, coseKeyPrivate)
		})
		return privateKeyObjects
	}

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

extension Optional where Wrapped: Collection {
    public var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}
