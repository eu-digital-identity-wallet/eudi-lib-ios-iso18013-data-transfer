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

import Foundation
import CryptoKit
import Testing
import MdocDataModel18013
import MdocSecurity18013
import SwiftCBOR
@testable import MdocDataTransfer18013

struct SessionEncryptionTests {
    @Test(arguments: [DeviceAuthMethod.deviceSignature, .deviceMac])
    func consentPreviewDoesNotUseCredentialKey(method: DeviceAuthMethod) async throws {
        let fixture = try await Fixture()
        let storage = SessionTestKeyStorage()
        var key = try await CoseKeyPrivate(secureArea: SoftwareSecureArea.create(storage: storage), keyOptions: .init(curve: .P256))
        let publicKey = try await key.key
        let item = try IssuerSignedItem(cbor: .map([
            .utf8String("digestID"): .unsignedInt(0), .utf8String("random"): .byteString([0]),
            .utf8String("elementIdentifier"): .utf8String("family_name"), .utf8String("elementValue"): .utf8String("test")
        ]))
        let mso = MobileSecurityObject(version: "1.0", digestAlgorithm: "SHA-256", valueDigests: .init(valueDigests: [:]),
            deviceKey: publicKey, docType: IsoMdlModel.isoDocType,
            validityInfo: .init(signed: "2026-01-01T00:00:00Z", validFrom: "2026-01-01T00:00:00Z", validUntil: "2030-01-01T00:00:00Z"))
        let auth = IssuerAuth(mso: mso, msoRawData: mso.toCBOR(options: CBOROptions()).taggedEncoded.encode(),
            verifyAlgorithm: .es256, signature: Data(repeating: 0, count: 64), x5chain: [[0]], statusList: nil)
        let docs = ["credential": IssuerSigned(issuerNameSpaces: .init(nameSpaces: [IsoMdlModel.isoNamespace: [item]]), issuerAuth: auth)]
        let reads = await storage.reads
        let preview = try await fixture.decode(docs: docs, keys: ["credential": key], method: method).get()
        #expect(preview.isValidRequest)
        #expect(preview.userRequestInfo.itemsRequested[IsoMdlModel.isoDocType]?[IsoMdlModel.isoNamespace]?.map(\.elementIdentifier) == ["family_name"])
        #expect(await storage.reads == reads)
        // A cancelled preview stops here without any credential-key operation.
        // Explicit approval still generates device authentication using the selected data.
        let response = try await MdocHelpers.getDeviceResponseToSend(deviceRequest: preview.deviceRequest,
            issuerSigned: docs, docMetadata: [:],
            selectedItems: ["credential": [IsoMdlModel.isoNamespace: [.init(elementIdentifier: "family_name")]]],
            sessionEncryption: preview.sessionEncryption, eReaderKey: fixture.readerKey,
            privateKeyObjects: ["credential": key], dauthMethod: method, unlockData: [:], authenticationContext: ThreadSafeAuthContext())
        #expect(response?.deviceResponse.documents?.count == 1)
        #expect(await storage.reads > reads)
    }

    @Test func helperPreservesCountersAcrossByValueCalls() async throws {
        let fixture = try await Fixture()
        let first = try await MdocHelpers.getSessionDataToSend(sessionEncryption: fixture.session, status: .requestReceived, docToSend: .init(status: 0)).get()
        let second = try await MdocHelpers.getSessionDataToSend(sessionEncryption: fixture.session, status: .requestReceived, docToSend: .init(status: 0)).get()
        #expect(first.0 != second.0)
        #expect(try fixture.open(first.0, counter: 1) == first.1)
        #expect(try fixture.open(second.0, counter: 2) == second.1)
    }

    @Test func statusOnlyErrorDoesNotConsumeAnEncryptionCounter() async throws {
        let fixture = try await Fixture()
        let error = try await MdocHelpers.getSessionDataToSend(sessionEncryption: fixture.session, status: .error, docToSend: .init(status: 0)).get()
        let status = try SessionData(cbor: #require(try CBOR.decode(Array(error.0))))
        #expect(status.data == nil)
        #expect(status.status == 11)
        let response = try await MdocHelpers.getSessionDataToSend(sessionEncryption: fixture.session, status: .requestReceived, docToSend: .init(status: 0)).get()
        #expect(try fixture.open(response.0, counter: 1) == response.1)
    }

    @Test func repeatedEstablishmentCannotResetTheSession() async throws {
        let fixture = try await Fixture()
        let decoded = try await fixture.decode().get()
        let response = try await MdocHelpers.getSessionDataToSend(sessionEncryption: decoded.sessionEncryption, status: .requestReceived, docToSend: .init(status: 0)).get()
        #expect(try fixture.open(response.0, counter: 1) == response.1)
        switch await fixture.decode() {
        case .success: Issue.record("Repeated establishment accepted")
        case let .failure(error): #expect((error as NSError).code == ErrorCode.sessionAlreadyEstablished.rawValue)
        }
        let fresh = try await Fixture()
        _ = try await fresh.decode().get()
    }

    @Test func concurrentEstablishmentsHaveOnlyOneWinner() async throws {
        let fixture = try await Fixture()
        async let first = fixture.decode()
        async let second = fixture.decode()
        let results = await [first, second]
        var accepted = 0
        for result in results {
            switch result {
            case .success: accepted += 1
            case let .failure(error): #expect((error as NSError).code == ErrorCode.sessionAlreadyEstablished.rawValue)
            }
        }
        #expect(accepted == 1)
    }

    @Test func failedEstablishmentCannotBeRetriedWithTheSameEngagement() async throws {
        let fixture = try await Fixture()
        let malformed = fixture.establishment(ciphertext: [0])
        if case .success = await fixture.decode(data: malformed) { Issue.record("Malformed ciphertext accepted") }
        switch await fixture.decode() {
        case .success: Issue.record("Consumed engagement was reused")
        case let .failure(error): #expect((error as NSError).code == ErrorCode.sessionAlreadyEstablished.rawValue)
        }
    }

    private struct Fixture: Sendable {
        typealias Decoded = (sessionEncryption: SessionEncryption, deviceRequest: DeviceRequest, userRequestInfo: UserRequestInfo, isValidRequest: Bool)
        let engagement: DeviceEngagement
        let session: SessionEncryption
        let readerKey: CoseKey
        let deviceSecret: SymmetricKey
        let readerSecret: SymmetricKey

        init() async throws {
            let area = SoftwareSecureArea.create(storage: SessionTestKeyStorage())
            var device = try #require(DeviceEngagement(supportsCentralClientMode: true, supportsPeripheralServerMode: true))
            try await device.makePrivateKey(secureArea: area, keyOptions: .init(curve: .P256))
            var reader = try await CoseKeyPrivate(secureArea: area, keyOptions: .init(curve: .P256))
            readerKey = try await reader.key
            let establishment = try SessionEstablishment(cbor: .map([
                .utf8String("eReaderKey"): readerKey.toCBOR(options: CBOROptions()).taggedEncoded,
                .utf8String("data"): .byteString([])
            ]))
            session = try #require(SessionEncryption(se: establishment, de: device, handOver: .null, authenticationContext: ThreadSafeAuthContext()))
            engagement = device
            var deviceKey = try #require(device.privateKey)
            let exchange = CoseKeyExchange(publicKey: try await deviceKey.key, privateKey: reader)
            let secret = try await exchange.makeEckaDHAgreement(authenticationContext: ThreadSafeAuthContext())
            deviceSecret = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: session.sessionTranscriptBytes, sharedInfo: Data("SKDevice".utf8), outputByteCount: 32)
            readerSecret = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: session.sessionTranscriptBytes, sharedInfo: Data("SKReader".utf8), outputByteCount: 32)
        }

        func establishment(ciphertext: [UInt8]) -> Data {
            Data(CBOR.map([
                .utf8String("eReaderKey"): readerKey.toCBOR(options: CBOROptions()).taggedEncoded,
                .utf8String("data"): .byteString(ciphertext)
            ]).encode())
        }

        func decode(data: Data? = nil, docs: [String: IssuerSigned] = [:], keys: [String: CoseKeyPrivate] = [:], method: DeviceAuthMethod = .deviceSignature) async -> Result<Decoded, Error> {
            do {
                let request: CBOR = .map([
                    .utf8String("docType"): .utf8String(IsoMdlModel.isoDocType),
                    .utf8String("nameSpaces"): .map([.utf8String(IsoMdlModel.isoNamespace): .map([.utf8String("family_name"): .boolean(false)])])
                ])
                let payload: CBOR = .map([
                    .utf8String("version"): .utf8String("1.0"),
                    .utf8String("docRequests"): .array([.map([.utf8String("itemsRequest"): request.taggedEncoded])])
                ])
                let box = try AES.GCM.seal(Data(payload.encode()), using: readerSecret, nonce: nonce(1, device: false))
                let encrypted = try #require(box.combined)
                return await MdocHelpers.decodeRequestAndInformUser(deviceEngagement: engagement, docs: docs, docMetadata: [:], trustValidator: NoReaderTrust(),
                    requestData: data ?? establishment(ciphertext: Array(encrypted.dropFirst(12))), privateKeyObjects: keys, dauthMethod: method,
                    unlockData: [:], readerKeyRawData: nil, handOver: .null, authenticationContext: ThreadSafeAuthContext())
            } catch { return .failure(error) }
        }

        func open(_ bytes: Data, counter: UInt32) throws -> Data {
            let message = try SessionData(cbor: #require(try CBOR.decode(Array(bytes))))
            let cipher = try #require(message.data)
            let box = try AES.GCM.SealedBox(combined: nonce(counter, device: true) + cipher)
            return try AES.GCM.open(box, using: deviceSecret)
        }

        func nonce(_ counter: UInt32, device: Bool) throws -> AES.GCM.Nonce {
            let bytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0, device ? 1 : 0,
                UInt8(truncatingIfNeeded: counter >> 24), UInt8(truncatingIfNeeded: counter >> 16),
                UInt8(truncatingIfNeeded: counter >> 8), UInt8(truncatingIfNeeded: counter)]
            return try AES.GCM.Nonce(data: bytes)
        }
    }
}

private struct NoReaderTrust: CertificateTrustValidator {
    var docType: String?
    func createCertTrustPath(chain: [Data]) async -> [Data]? { nil }
    func validateCertTrustPath(chain: [Data]) async -> (Bool, String?) { (false, nil) }
}

private actor SessionTestKeyStorage: SecureKeyStorage {
    private(set) var reads = 0
    var info: [String: [String: Data]] = [:]
    var data: [String: [Int: [String: Data]]] = [:]
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
