import Foundation
import CryptoKit
import Security
import Testing
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013
@testable import MdocDataTransfer18013

struct DeviceAuthenticationConfigurationTests {
    func configuration(_ method: String) -> InitializeTransferData {
        InitializeTransferData(dataFormats: [:], documentData: [:], documentKeyIndexes: [:], docMetadata: [:],
            docDisplayNames: [:], docKeyInfos: [:], trustValidator: AuthTrustValidator(), deviceAuthMethod: method,
            idsToDocTypes: [:], hashingAlgs: [:], bleTransferMode: .server)
    }

    @Test(arguments: ["", "deviceSignatur", "DeviceSignature", " deviceSignature", "deviceSignature ", "unsupported"])
    func invalidMethodThrows(_ method: String) async {
        await #expect(throws: (any Error).self) { try await configuration(method).toInitializeTransferInfo() }
    }

    @Test(arguments: [DeviceAuthMethod.deviceMac, .deviceSignature])
    func validMethodIsPreserved(_ method: DeviceAuthMethod) async throws {
        let result = try await configuration(method.rawValue).toInitializeTransferInfo()
        #expect(result.deviceAuthMethod == method)
    }

    @Test func storedPurposeSurvivesCopiesAndRejectsSwitchingMethods() async throws {
        for method in [DeviceAuthMethod.deviceMac, .deviceSignature] {
            let storage = AuthKeyStorage()
            let area = SoftwareSecureArea.create(storage: storage)
            let purpose: KeyPurpose = method == .deviceSignature ? .signing : .keyAgreement
            let key = try await CoseKeyPrivate(secureArea: area, keyOptions: KeyOptions(keyPurposes: [purpose]))
            try await MdocHelpers.validateDeviceAuthenticationKey(key, method: method)
            let recreated = CoseKeyPrivate(privateKeyId: key.privateKeyId, index: key.index, secureArea: area, curve: .P256)
            let other: DeviceAuthMethod = method == .deviceSignature ? .deviceMac : .deviceSignature
            await #expect(throws: (any Error).self) { try await MdocHelpers.validateDeviceAuthenticationKey(recreated, method: other) }
            #expect(await storage.reads == 0)
            try await MdocHelpers.validateDeviceAuthenticationKey(recreated, method: method)
        }
    }

    @Test func missingAndDualPurposesFailClosed() async throws {
        for purposes: [KeyPurpose]? in [nil, [], KeyPurpose.allCases] {
            let storage = AuthKeyStorage()
            let key = try await CoseKeyPrivate(secureArea: SoftwareSecureArea.create(storage: storage), keyOptions: KeyOptions(keyPurposes: purposes))
            for method in [DeviceAuthMethod.deviceMac, .deviceSignature] {
                await #expect(throws: (any Error).self) { try await MdocHelpers.validateDeviceAuthenticationKey(key, method: method) }
            }
            #expect(await storage.reads == 0)
        }
    }

    @Test func conflictingDeclarationsAndInvalidIndexesAreRejected() async throws {
        let storage = AuthKeyStorage()
        let area = SoftwareSecureArea.create(storage: storage)
        let key = try await CoseKeyPrivate(secureArea: area, keyOptions: KeyOptions(keyPurposes: [.signing]))
        var record = try await storage.readKeyInfo(id: key.privateKeyId)
        var info = try await area.getKeyBatchInfo(id: key.privateKeyId)
        info.keyPurpose = [.keyAgreement]
        record[kSecValueData as String] = info.toData()
        try await storage.writeKeyInfo(id: key.privateKeyId, dict: record)
        for method in [DeviceAuthMethod.deviceMac, .deviceSignature] {
            await #expect(throws: (any Error).self) { try await MdocHelpers.validateDeviceAuthenticationKey(key, method: method) }
        }
        info.keyPurpose = [.signing]
        record[kSecValueData as String] = info.toData()
        try await storage.writeKeyInfo(id: key.privateKeyId, dict: record)
        try await MdocHelpers.validateDeviceAuthenticationKey(key, method: .deviceSignature)
        let invalid = CoseKeyPrivate(privateKeyId: key.privateKeyId, index: 1, secureArea: area, curve: .P256)
        await #expect(throws: (any Error).self) { try await MdocHelpers.validateDeviceAuthenticationKey(invalid, method: .deviceSignature) }
    }

    @Test(arguments: [DeviceAuthMethod.deviceMac, .deviceSignature])
    func responseBoundaryRejectsOppositePurposeAndAuthenticatesDedicatedKey(_ method: DeviceAuthMethod) async throws {
        let storage = AuthKeyStorage()
        let purpose: KeyPurpose = method == .deviceSignature ? .signing : .keyAgreement
        var key = try await CoseKeyPrivate(secureArea: SoftwareSecureArea.create(storage: storage), keyOptions: KeyOptions(keyPurposes: [purpose]))
        let publicKey = try await key.key
        let mso = MobileSecurityObject(version: "1.0", digestAlgorithm: "SHA-256", valueDigests: .init(valueDigests: [:]), deviceKey: publicKey,
            docType: IsoMdlModel.isoDocType, validityInfo: .init(signed: "2026-01-01T00:00:00Z", validFrom: "2026-01-01T00:00:00Z", validUntil: "2030-01-01T00:00:00Z"))
        let issuerAuth = IssuerAuth(mso: mso, msoRawData: mso.toCBOR(options: CBOROptions()).taggedEncoded.encode(), verifyAlgorithm: .es256,
            signature: Data(repeating: 0, count: 64), x5chain: [], statusList: nil)
        let item = try IssuerSignedItem(cbor: .map([.utf8String("digestID"): .unsignedInt(0), .utf8String("random"): .byteString([0]),
            .utf8String("elementIdentifier"): .utf8String("family_name"), .utf8String("elementValue"): .utf8String("test")]))
        let credential = IssuerSigned(issuerNameSpaces: .init(nameSpaces: ["org.iso.18013.5.1": [item]]), issuerAuth: issuerAuth)
        let readerPublicKey = CoseKey(crv: .P256, x963Representation: P256.KeyAgreement.PrivateKey().publicKey.x963Representation)
        func respond(_ method: DeviceAuthMethod) async throws -> DeviceResponse? {
            try await MdocHelpers.getDeviceResponseToSend(deviceRequest: nil, issuerSigned: ["doc": credential], docMetadata: [:],
                selectedItems: ["doc": ["org.iso.18013.5.1": [.init(elementIdentifier: "family_name")]]], eReaderKey: readerPublicKey, privateKeyObjects: ["doc": key],
                sessionTranscript: SessionTranscript(handOver: .null), dauthMethod: method, unlockData: [:], authenticationContext: ThreadSafeAuthContext())?.deviceResponse
        }
        let reads = await storage.reads
        await #expect(throws: (any Error).self) { try await respond(method == .deviceMac ? .deviceSignature : .deviceMac) }
        #expect(await storage.reads == reads)
        let response = try #require(try await respond(method))
        #expect(response.documents?.count == 1)
        #expect(await storage.reads > reads)
    }
}

private struct AuthTrustValidator: CertificateTrustValidator {
    var docType: String?
    func createCertTrustPath(chain: [Data]) async -> [Data]? { chain }
    func validateCertTrustPath(chain: [Data]) async -> (Bool, String?) { (true, nil) }
}

private actor AuthKeyStorage: SecureKeyStorage {
	private var info: [String: [String: Data]] = [:]
	private var data: [String: [Int: [String: Data]]] = [:]
	private(set) var reads = 0

	func readKeyInfo(id: String) async throws -> [String: Data] { info[id] ?? [:] }
	func readKeyData(id: String, index: Int, authenticationContext: ThreadSafeAuthContext) async throws -> [String: Data] {
		reads += 1
		return data[id]?[index] ?? [:]
	}
	func writeKeyInfo(id: String, dict: [String: Data]) async throws { info[id] = dict }
	func writeKeyDataBatch(id: String, startIndex: Int, dicts: [[String: Data]], keyOptions: KeyOptions?) async throws {
		for (offset, dict) in dicts.enumerated() { data[id, default: [:]][startIndex + offset] = dict }
	}
	func deleteKeyBatch(id: String, startIndex: Int, batchSize: Int) async throws {
		for index in startIndex..<(startIndex + batchSize) { data[id]?[index] = nil }
	}
	func deleteKeyInfo(id: String) async throws { info[id] = nil }
}
