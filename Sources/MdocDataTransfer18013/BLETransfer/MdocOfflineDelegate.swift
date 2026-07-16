//
//  MdocOfflineHandler.swift

import Foundation
import MdocDataModel18013
import MdocSecurity18013

/// delegate protocol for clients of the mdoc offline transfer manager
public protocol MdocOfflineDelegate: AnyObject {
	var deviceEngagement: DeviceEngagement? { get set }
	var deviceRequest: DeviceRequest? { get set }
	var sessionEncryption: SessionEncryption? { get set }
	var docs: [String: IssuerSigned]! { get set }
	var docMetadata: [String: Data?]! { get set }
	var trustValidator: any CertificateTrustValidator { get set }
	var privateKeyObjects: [String: CoseKeyPrivate]! { get set }
	var dauthMethod: DeviceAuthMethod { get set }
	var zkSystemRepository: ZkSystemRepository? { get set }
	var readerName: String? { get set }
	var qrCodePayload: String? { get set }
	var unlockData: [String: Data]! { get set }
	var deviceResponseBytes: Data? { get set }
	var responseMetadata: [Data?]! { get set }
	var zkpDocumentIds: [String]? { get set }
	func didChangeStatus(_ newStatus: TransferStatus)
	func didFinishedWithError(_ error: Error)
	func didReceiveRequest(_ data: Data)
	func didPoweredOn(isPeripheralManager: Bool)
	func didConnected(isPeripheral: Bool, deviceName: String?)
	 /// Called by the wallet to set the PSM channel number for L2CAP mode.
	func didPublishedPsmChannel(psm: UInt16?)
}


