import Foundation
import MdocDataModel18013
import MdocSecurity18013

public struct InitializeTransferData: Sendable {

	public init(dataFormats: [String: String], documentData: [String: Data], documentKeyIndexes: [String: Int], docMetadata: [String: Data?], docDisplayNames: [String: [String: [String: String]]?], docKeyInfos: [String: Data?], trustedCertificates: [Data], deviceAuthMethod: String, idsToDocTypes: [String: String], hashingAlgs: [String: String]) {
        self.dataFormats = dataFormats
        self.documentData = documentData
		self.documentKeyIndexes = documentKeyIndexes
		self.docMetadata = docMetadata
		self.docDisplayNames = docDisplayNames
        self.docKeyInfos = docKeyInfos
        self.trustedCertificates = trustedCertificates
        self.deviceAuthMethod = deviceAuthMethod
        self.idsToDocTypes = idsToDocTypes
		self.hashingAlgs = hashingAlgs
    }
    public let dataFormats: [String: String]
    /// doc-id to document data
    public let documentData: [String: Data]
	/// doc-id to document key indexes
	public let documentKeyIndexes: [String: Int]
	/// document-id to doc-metadata map
	public let docMetadata: [String: Data?]
	/// document-id to doc.fields display names
	public let docDisplayNames: [String: [String: [String: String]]?]
    /// doc-id to private key info
    public let docKeyInfos: [String: Data?]
    /// trusted certificates
    public let trustedCertificates: [Data]
    /// device auth method
    public let deviceAuthMethod: String
    /// document-id to document type map
    public let idsToDocTypes: [String: String]
	/// document-id to hashing algorithm
	var hashingAlgs: [String: String]

    public func toInitializeTransferInfo() -> InitializeTransferInfo {
        // filter data and private keys by format
		let privateKeyObjects: [String: CoseKeyPrivate] = Dictionary(uniqueKeysWithValues: docKeyInfos.compactMap {
			guard let dki = DocKeyInfo(from: $0.value)  else { return nil }
			guard let keyIndex = documentKeyIndexes[$0.key] else { return nil }
			return ($0.key, CoseKeyPrivate(privateKeyId: $0.key, index: keyIndex, secureArea: SecureAreaRegistry.shared.get(name: dki.secureAreaName)))
		})
		let documentObjects = documentData
		let docMetadata = docMetadata.compactMapValues { DocMetadata(from: $0) }
		let dataFormats = Dictionary(uniqueKeysWithValues: dataFormats.map { k,v in (k, DocDataFormat(rawValue: v)) }).compactMapValues { $0 }
        let iaca = trustedCertificates.map { SecCertificateCreateWithData(nil, $0 as CFData)! }
        let deviceAuthMethod = DeviceAuthMethod(rawValue: deviceAuthMethod) ?? .deviceMac
		return InitializeTransferInfo(dataFormats: dataFormats, documentObjects: documentObjects, docMetadata: docMetadata, docDisplayNames: docDisplayNames, privateKeyObjects: privateKeyObjects, iaca: iaca, deviceAuthMethod: deviceAuthMethod, idsToDocTypes: idsToDocTypes, hashingAlgs: hashingAlgs)
    }
}

public struct InitializeTransferInfo {
    /// doc-id to data format
    public let dataFormats: [String: DocDataFormat]
    /// doc-id to document objects
    public let documentObjects: [String: Data]
	/// document-id to doc-metadata map
	public let docMetadata: [String: DocMetadata]
	// doc-id to doc.fields display names
	public let docDisplayNames: [String: [String: [String: String]]?]
    /// doc-id to private key objects
    public let privateKeyObjects: [String: CoseKeyPrivate]
    /// trusted certificates
    public let iaca: [SecCertificate]
    /// device auth method
    public let deviceAuthMethod: DeviceAuthMethod
        // document-id to document type map
    public let idsToDocTypes: [String: String]
			// document-id to hashing algorithm
	public let hashingAlgs:[String: String]
}
