import Foundation
import MdocDataModel18013
import MdocSecurity18013

public struct InitializeTransferData: Sendable {

    public init(dataFormats: [String : String], documentData: [String : Data], privateKeyData: [String : String], trustedCertificates: [Data], deviceAuthMethod: String, docTypesToΙds: [String : String]) {
        self.dataFormats = dataFormats
        self.documentData = documentData
        self.privateKeyData = privateKeyData
        self.trustedCertificates = trustedCertificates
        self.deviceAuthMethod = deviceAuthMethod
        self.docTypesToΙds = docTypesToΙds
    }

    public let dataFormats: [String: String]
    /// doc-id to document data
    public let documentData: [String: Data]
    /// doc-id to private key secure area name
    public let privateKeyData: [String: String]
    /// trusted certificates
    public let trustedCertificates: [Data]
    /// device auth method
    public let deviceAuthMethod: String
    // document id to document type map
    public let docTypesToΙds: [String: String]

    public func toInitializeTransferInfo() -> InitializeTransferInfo {
        // filter data and private keys by format
        let documentObjects = documentData
        let dataFormats = Dictionary.init(uniqueKeysWithValues: dataFormats.map { k,v in (k, DocDataFormat(rawValue: v)) }).compactMapValues { $0 }    
        let privateKeyObjects = Dictionary.init(uniqueKeysWithValues: privateKeyData.map { k,v in (k, CoseKeyPrivate(privateKeyId: k, secureArea: SecureAreaRegistry.shared.get(name: v))) })
        let iaca = trustedCertificates.map { SecCertificateCreateWithData(nil, $0 as CFData)! }
        let deviceAuthMethod = DeviceAuthMethod(rawValue: deviceAuthMethod) ?? .deviceMac
        return InitializeTransferInfo(dataFormats: dataFormats, documentObjects: documentObjects, privateKeyObjects: privateKeyObjects, iaca: iaca, deviceAuthMethod: deviceAuthMethod, docTypesToΙds: docTypesToΙds)
    }
}

public struct InitializeTransferInfo {
    /// doc-id to data format
    public let dataFormats: [String: DocDataFormat]
    /// doc-id to document objects
    public let documentObjects: [String: Data]
    /// doc-id to private key objects
    public let privateKeyObjects: [String: CoseKeyPrivate]
    /// trusted certificates
    public let iaca: [SecCertificate]
    /// device auth method
    public let deviceAuthMethod: DeviceAuthMethod
        // document id to document type map
    public let docTypesToΙds: [String: String]
}