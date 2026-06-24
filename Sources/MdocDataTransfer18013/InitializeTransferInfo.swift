import Foundation
import MdocDataModel18013
import MdocSecurity18013

public struct InitializeTransferData: Sendable {

    public init(
        dataFormats: [String: String],
        documentData: [String: Data],
        documentKeyIndexes: [String: Int],
        docMetadata: [String: Data?],
        docDisplayNames: [String: [String: [String: String]]?],
        docKeyInfos: [String: Data?],
        iaca: [x5chain],
        deviceAuthMethod: String,
        idsToDocTypes: [String: String],
        hashingAlgs: [String: String],
		bleTransferMode: BleTransferMode,
		crlRevocationPolicy: RevocationPolicy,
        zkSystemRepository: ZkSystemRepository? = nil
    ) {
        self.dataFormats = dataFormats
        self.documentData = documentData
		self.documentKeyIndexes = documentKeyIndexes
		self.docMetadata = docMetadata
		self.docDisplayNames = docDisplayNames
        self.docKeyInfos = docKeyInfos
        self.iaca = iaca
        self.deviceAuthMethod = deviceAuthMethod
        self.idsToDocTypes = idsToDocTypes
		self.hashingAlgs = hashingAlgs
		self.bleTransferMode = bleTransferMode
		self.crlRevocationPolicy = crlRevocationPolicy
        self.zkSystemRepository = zkSystemRepository
    }
    /// doc-id to data format
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
    public let iaca: [x5chain]
    /// device auth method
    public let deviceAuthMethod: String
    /// document-id to document type map
    public let idsToDocTypes: [String: String]
	/// document-id to hashing algorithm
	var hashingAlgs: [String: String]
	/// BLE transfer mode
	public let bleTransferMode: BleTransferMode
	/// CRL revocation policy
	public let crlRevocationPolicy: RevocationPolicy
    // optional zk system repository
    public let zkSystemRepository: ZkSystemRepository?

	public func toInitializeTransferInfo() async throws -> InitializeTransferInfo {
        // filter data and private keys by format
        let keyInfosByDocument = docKeyInfos
        let privateKeyObjects: [String: CoseKeyPrivate] = try await MdocHelpers.getPrivateKeys(
            keyInfosByDocument,
            documentKeyIndexes
        )
		let documentObjects = documentData
		let docMetadata = docMetadata.compactMapValues { $0 }
        let dataFormatPairs = dataFormats.map { key, value in
            (key, DocDataFormat(rawValue: value))
        }
        let resolvedDataFormats = Dictionary(uniqueKeysWithValues: dataFormatPairs).compactMapValues { $0 }
        let deviceAuthMethod = DeviceAuthMethod(rawValue: deviceAuthMethod) ?? .deviceMac
        return InitializeTransferInfo(
            dataFormats: resolvedDataFormats,
            documentObjects: documentObjects,
            docMetadata: docMetadata,
            docDisplayNames: docDisplayNames,
            privateKeyObjects: privateKeyObjects,
            iaca: iaca,
            deviceAuthMethod: deviceAuthMethod,
            idsToDocTypes: idsToDocTypes,
            hashingAlgs: hashingAlgs,
            zkSystemRepository: zkSystemRepository
        )
    }
}

public struct InitializeTransferInfo {
    /// doc-id to data format
    public let dataFormats: [String: DocDataFormat]
    /// doc-id to document objects
    public let documentObjects: [String: Data]
	/// document-id to doc-metadata map
	public let docMetadata: [String: Data]
	/// doc-id to doc.fields display names
	public let docDisplayNames: [String: [String: [String: String]]?]
    /// doc-id to private key objects
    public let privateKeyObjects: [String: CoseKeyPrivate]
    /// trusted certificates
	public let iaca: [x5chain]
    /// device auth method
    public let deviceAuthMethod: DeviceAuthMethod
	// document-id to document type map
    public let idsToDocTypes: [String: DocType]
	// document-id to hashing algorithm
	public let hashingAlgs:[String: String]
    // optional zk system repository
    public let zkSystemRepository: ZkSystemRepository?
}
