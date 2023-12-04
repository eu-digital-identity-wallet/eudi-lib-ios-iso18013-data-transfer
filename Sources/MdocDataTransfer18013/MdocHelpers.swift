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

public typealias RequestItems = [String: [String: [String]]]

/// Helper methods
public class MdocHelpers {
	
	public static func initializeData(parameters: [String: Any]) -> (docs: [DeviceResponse], devicePrivateKey: CoseKeyPrivate?, iaca: [SecCertificate]?)? {
		var docs: [DeviceResponse]?
		var devicePrivateKey: CoseKeyPrivate?
		var iaca: [SecCertificate]?
		if let d = parameters[InitializeKeys.document_json_data.rawValue] as? [Data] {
			// load json sample data here
			let sampleData = d.compactMap { $0.decodeJSON(type: SignUpResponse.self) }
			docs = sampleData.compactMap { $0.deviceResponse }
			devicePrivateKey = sampleData.compactMap { $0.devicePrivateKey }.first
		} else if let drs = parameters[InitializeKeys.document_signup_response_obj.rawValue] as? [DeviceResponse], let dpk = parameters[InitializeKeys.device_private_key_obj.rawValue] as? CoseKeyPrivate {
			docs = drs
			devicePrivateKey = dpk
		} else if let drsData = parameters[InitializeKeys.document_signup_response_data.rawValue] as? [Data], let dpk = parameters[InitializeKeys.device_private_key_data.rawValue] as? Data {
			docs = drsData.compactMap({ DeviceResponse(data: [UInt8]($0))})
			devicePrivateKey = CoseKeyPrivate(privateKeyx963Data: dpk, crv: .p256)
		}
		if let i = parameters[InitializeKeys.trusted_certificates.rawValue] as? [Data] {
			iaca = i.compactMap {	SecCertificateCreateWithData(nil, $0 as CFData) }
		}
		guard let docs else { return nil }
		return (docs, devicePrivateKey, iaca)
	}
	
	public static func getDeviceResponseToSend(deviceRequest: DeviceRequest?, deviceResponses: [DeviceResponse], selectedItems: RequestItems? = nil, sessionEncryption: SessionEncryption? = nil, eReaderKey: CoseKey? = nil, devicePrivateKey: CoseKeyPrivate? = nil) throws -> (response: DeviceResponse, validRequestItems: RequestItems, errorRequestItems: RequestItems)? {
		let documents = deviceResponses.flatMap { $0.documents! }
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
				let itemsReqSet = Set(reqElementIdentifiers).subtracting(IsoMdlModel.self.moreThan2AgeOverElementIdentifiers(reqDocType, reqNamespace, SimpleAgeAttest(namespaces: issuerNs.nameSpaces), reqElementIdentifiers))
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
			let errors: Errors? = nsErrorsToAdd.count == 0 ? nil : Errors(errors: nsErrorsToAdd)
			if nsItemsToAdd.count > 0 {
				let issuerAuthToAdd = doc.issuerSigned.issuerAuth
				let issToAdd = IssuerSigned(issuerNameSpaces: IssuerNameSpaces(nameSpaces: nsItemsToAdd), issuerAuth: issuerAuthToAdd)
				var devSignedToAdd: DeviceSigned? = nil
				if let eReaderKey, let sessionEncryption, let devicePrivateKey {
					let authKeys = CoseKeyExchange(publicKey: eReaderKey, privateKey: devicePrivateKey)
					let mdocAuth = MdocAuthentication(transcript: sessionEncryption.transcript, authKeys: authKeys)
					guard let devAuth = try mdocAuth.getDeviceAuthForTransfer(docType: reqDocType) else {logger.error("Cannot create device auth"); return nil }
					devSignedToAdd = DeviceSigned(deviceAuth: devAuth)
				}
				let docToAdd = Document(docType: reqDocType, issuerSigned: issToAdd, deviceSigned: devSignedToAdd, errors: errors)
				docFiltered.append(docToAdd)
				validReqItemsDocDict[reqDocType] = validReqItemsNsDict
			} else {
				docErrors.append([reqDocType: UInt64(0)])
			}
			errorReqItemsDocDict[reqDocType] = nsErrorsToAdd.mapValues { Array($0.keys) }
		} // end doc for
		let documentErrors: [DocumentError]? = docErrors.count == 0 ? nil : docErrors.map(DocumentError.init(docErrors:))
		let documentsToAdd = docFiltered.count == 0 ? nil : docFiltered
		let deviceResponseToSend = DeviceResponse(version: deviceResponses.first!.version, documents: documentsToAdd, documentErrors: documentErrors, status: 0)
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
	
	#endif
}
