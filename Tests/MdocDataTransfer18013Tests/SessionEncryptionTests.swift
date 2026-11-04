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
#if !os(watchOS)
import CoreBluetooth
#endif
import CryptoKit
import Testing
import MdocDataModel18013
import MdocSecurity18013
import SwiftCBOR
@testable import MdocDataTransfer18013

struct SessionEncryptionTests {
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
        let storage = SessionTestKeyStorage()
        let fixture = try await Fixture(storage: storage)
        let malformed = fixture.establishment(ciphertext: [0])
        if case .success = await fixture.decode(data: malformed) { Issue.record("Malformed ciphertext accepted") }
        #expect(await storage.deletedIDs == [fixture.engagement.privateKey!.privateKeyId])
        switch await fixture.decode() {
        case .success: Issue.record("Consumed engagement was reused")
        case let .failure(error): #expect((error as NSError).code == ErrorCode.sessionAlreadyEstablished.rawValue)
        }
    }

    @Test func engagementTerminationRevokesSessionCopiesAndFutureDecode() async throws {
        let fixture = try await Fixture()
        var copy = fixture.session
        fixture.engagement.invalidateSession()
        await #expect(throws: SessionEncryptionError.sessionTerminated) { try await copy.encrypt([1]) }
        await #expect(throws: (any Error).self) { try await fixture.decode().get() }
        let fresh = try await Fixture()
        _ = try await fresh.decode().get()
    }

    #if !os(watchOS)
    @Test(arguments: [0, 1, 2])
    func serverTerminalPathsClearStateAndDeleteOnlyOldKey(_ path: Int) async throws {
        let storage = SessionTestKeyStorage()
        let fixture = try await Fixture(storage: storage)
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        server.sendBuffer = [Data([1,2])]
        if path == 0 { server.stop() }
        else if path == 1 { server.finishResponse() }
        else { server.error = NSError(domain: "test", code: 1) }
        #expect(delegate.deviceEngagement == nil)
        #expect(delegate.sessionEncryption == nil)
        #expect(delegate.qrCodePayload == nil)
        #expect(server.sendBuffer.isEmpty)
        #expect(server.remoteCentral == nil)
        #expect(fixture.engagement.isSessionTerminated)
        var copy = fixture.session
        await #expect(throws: SessionEncryptionError.sessionTerminated) { try await copy.encrypt([1]) }
        // Explicit cleanup is idempotent, even after the delegate has gone away.
        server.delegate = nil
        server.stop()
    }

    @Test func completedServerStillReportsDisconnectAndIgnoresOldPeerAfterRestart() async throws {
        let fixture = try await Fixture()
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        let oldPeer = UUID()
        _ = server.peerState.subscribe(oldPeer, to: .state)
        _ = server.peerState.subscribe(oldPeer, to: .response)
        server.finishResponse()
        #expect(server.status == .responseSent)
        #expect(delegate.sessionEncryption == nil)
        server.didUnsubscribe(oldPeer)
        #expect(server.status == .disconnected)
        let fresh = try await Fixture()
        delegate.deviceEngagement = fresh.engagement
        delegate.sessionEncryption = fresh.session
        server.status = .qrEngagementReady
        server.completedCentralID = oldPeer
        server.didUnsubscribe(oldPeer)
        #expect(server.status == .qrEngagementReady)
        #expect(!fresh.engagement.isSessionTerminated)
    }
    #endif

    @Test(arguments: [0, 1, 2])
    func centralTerminalPathsClearBuffersAndNegotiation(_ path: Int) async throws {
        let fixture = try await Fixture()
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let central = MdocGattCentral(centralManager: nil)
        central.delegate = delegate
        central.readBuffer = Data([9])
        central.sendBuffer = [Data([8])]
        central.hasReaderIdentity = true
        central.didSendStartRequest = true
        central.maximumCharacteristicSize = 200
        if path == 0 { central.stop() }
        else if path == 1 { central.finishResponse() }
        else { central.error = NSError(domain: "test", code: 1) }
        #expect(delegate.deviceEngagement == nil)
        #expect(delegate.sessionEncryption == nil)
        #expect(central.readBuffer.isEmpty && central.sendBuffer.isEmpty)
        #expect(!central.hasReaderIdentity && !central.didSendStartRequest)
        #expect(central.maximumCharacteristicSize == nil)
        #expect(fixture.engagement.isSessionTerminated)
        central.delegate = nil
        central.stop()
    }

    @Test func delayedDeletionCannotClearReplacementEngagement() async throws {
        let storage = SessionTestKeyStorage()
        let old = try await Fixture(storage: storage)
        let delegate = CleanupDelegate(engagement: old.engagement, session: old.session)
        await storage.pauseDeletion()
        let deletion = try #require(clearMdocSession(delegate))
        await storage.waitForDeletion()
        let replacement = try await Fixture()
        delegate.deviceEngagement = replacement.engagement
        delegate.sessionEncryption = replacement.session
        delegate.qrCodePayload = "replacement"
        await storage.resumeDeletion()
        await deletion.value
        #expect(delegate.deviceEngagement?.privateKey?.privateKeyId == replacement.engagement.privateKey?.privateKeyId)
        #expect(delegate.qrCodePayload == "replacement")
        #expect(!replacement.engagement.isSessionTerminated)
        #expect(await storage.deletedIDs == [old.engagement.privateKey!.privateKeyId])
        var session = replacement.session
        #expect(try await session.encrypt([1]) != nil)
    }

    @Test func teardownDuringDecodeRejectsInFlightResult() async throws {
        let storage = SessionTestKeyStorage()
        let fixture = try await Fixture(storage: storage)
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: nil)
        await storage.pauseRead()
        async let result = fixture.decode()
        await storage.waitForRead()
        let deletion = clearMdocSession(delegate)
        await storage.resumeRead()
        if case .success = await result { Issue.record("Terminated request returned a live session") }
        await deletion?.value
        #expect(fixture.engagement.isSessionTerminated)
    }

    #if !os(watchOS)
    @Test func advertisingPauseAndConsentRemainSubjectToTimeout() async throws {
        let fixture = try await Fixture()
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let clock = TimeoutTestClock()
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        server.monitorInactivity(using: clock.makeTimer())
        server.stopBleAdvertising()
        clock.advance(300)
        clock.deliver()
        #expect(fixture.engagement.isSessionTerminated)
        #expect(delegate.sessionEncryption == nil)
        #expect(delegate.errors.count == 1)
        #expect((delegate.errors.first as NSError?)?.code == ErrorCode.bleSessionTimeout.rawValue)
    }

    @Test func bothRolesShareDeadlineAndNotifyTimeoutOnlyOnce() async throws {
        let fixture = try await Fixture()
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let key = try #require(fixture.engagement.privateKey)
        #expect(SessionInactivityTimeout.shared(for: key) === SessionInactivityTimeout.shared(for: key))
        let clock = TimeoutTestClock()
        let timer = clock.makeTimer()
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        let central = MdocGattCentral(centralManager: nil)
        central.delegate = delegate
        server.monitorInactivity(using: timer)
        central.monitorInactivity(using: timer)
        central.readBuffer = Data([1])
        clock.advance(299)
        server.inactivityTimer?.activity()
        clock.advance(1)
        clock.deliver()
        #expect(!fixture.engagement.isSessionTerminated)
        #expect(delegate.errors.isEmpty)
        clock.advance(299)
        clock.deliver()
        #expect(fixture.engagement.isSessionTerminated)
        #expect(central.readBuffer.isEmpty)
        #expect(server.inactivityTimer == nil && central.inactivityTimer == nil)
        #expect(delegate.errors.count == 1)
    }

    @Test func stoppingOneRoleEndsItsSiblingWithoutReportingTimeout() async throws {
        let fixture = try await Fixture()
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let clock = TimeoutTestClock()
        let timer = clock.makeTimer()
        let server = MdocGattServer(peripheralManager: nil)
        let central = MdocGattCentral(centralManager: nil)
        server.delegate = delegate
        central.delegate = delegate
        server.monitorInactivity(using: timer)
        central.monitorInactivity(using: timer)
        central.readBuffer = Data([9])
        server.stop()
        #expect(server.inactivityTimer == nil && central.inactivityTimer == nil)
        #expect(central.readBuffer.isEmpty)
        #expect(fixture.engagement.isSessionTerminated)
        clock.advance(300)
        clock.deliver()
        #expect(delegate.errors.isEmpty)
    }

    @Test func stoppedTimerCannotInvalidateReplacementEngagement() async throws {
        let old = try await Fixture()
        let delegate = CleanupDelegate(engagement: old.engagement, session: old.session)
        let clock = TimeoutTestClock()
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        server.monitorInactivity(using: clock.makeTimer())
        server.stop()
        let fresh = try await Fixture()
        delegate.deviceEngagement = fresh.engagement
        delegate.sessionEncryption = fresh.session
        server.monitorInactivity(using: clock.makeTimer())
        clock.advance(299)
        clock.deliver()
        #expect(!fresh.engagement.isSessionTerminated)
        #expect(delegate.errors.isEmpty)
        server.stop()
        clock.advance(1)
        clock.deliver()
        #expect(delegate.errors.isEmpty)
    }
    #endif

    @Test func freshAdvertisingIsAdmittedOnceAndLiveStartsAreIdempotent() async throws {
        let fixture = try await Fixture()
        var state = BleAdvertisingState()
        let first = try state.admit(fixture.engagement)
        let second = try state.admit(fixture.engagement)
        #expect(first == .start)
        #expect(second == .alreadyActive)
        state.retire()
        #expect(throws: BleAdvertisingState.Failure.reusedUUID) { try state.admit(fixture.engagement) }
        var anotherTransport = BleAdvertisingState()
        #expect(throws: BleAdvertisingState.Failure.reusedUUID) { try anotherTransport.admit(fixture.engagement) }
    }

    @Test func liveAdvertisingPauseCanResumeWithoutRetiringTheEngagement() async throws {
        let fixture = try await Fixture()
        var state = BleAdvertisingState()
        _ = try state.admit(fixture.engagement)
        let resumed = try state.admit(fixture.engagement, isAdvertising: false)
        #expect(resumed == .resume)
        let duplicate = try state.admit(fixture.engagement, isAdvertising: true)
        #expect(duplicate == .alreadyActive)
        #expect(!fixture.engagement.isSessionTerminated)
    }

    @Test func newKeyOnOldEngagementCannotReuseAdvertisedUUID() async throws {
        let fixture = try await Fixture()
        var state = BleAdvertisingState()
        _ = try state.admit(fixture.engagement)
        state.retire()
        var reused = fixture.engagement
        reused.invalidateSession()
        try await reused.makePrivateKey(secureArea: SoftwareSecureArea.create(storage: SessionTestKeyStorage()), keyOptions: .init(curve: .P256))
        #expect(!reused.isSessionTerminated)
        #expect(reused.ble_uuid == fixture.engagement.ble_uuid)
        #expect(throws: BleAdvertisingState.Failure.reusedUUID) { try state.admit(reused) }
        let fresh = try await Fixture()
        let admitted = try state.admit(fresh.engagement)
        #expect(admitted == .start)
    }

    #if !os(watchOS)
    @Test func stoppedEngagementCannotBeAdvertisedAgain() async throws {
        let fixture = try await Fixture()
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        _ = try server.advertisingState.admit(fixture.engagement)
        server.advertisedEngagement = fixture.engagement
        server.stop()
        delegate.deviceEngagement = fixture.engagement
        server.startBleAdvertising() // Must reject before touching the absent manager.
        #expect(server.error != nil)
        #expect(!server.advertising)
        #expect(delegate.deviceEngagement == nil)
    }

    @Test func missingKeyCannotBeAdvertised() throws {
        let engagement = try #require(DeviceEngagement(supportsCentralClientMode: false, supportsPeripheralServerMode: true))
        let delegate = CleanupDelegate(engagement: engagement, session: nil)
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        server.startBleAdvertising()
        #expect(server.error != nil)
        #expect(!server.advertising)
    }

    @Test func responseKeepsNotificationServicesUntilUnsubscribe() async throws {
        let fixture = try await Fixture()
        let delegate = CleanupDelegate(engagement: fixture.engagement, session: fixture.session)
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        let peer = UUID()
        _ = server.peerState.subscribe(peer, to: .state)
        _ = server.peerState.subscribe(peer, to: .response)
        server.stateCharacteristic = CBMutableCharacteristic(type: MdocGattServer.MdocServiceCharacteristic.state.uuid, properties: [.notify], value: nil, permissions: [])
        server.server2ClientCharacteristic = CBMutableCharacteristic(type: MdocGattServer.MdocServiceCharacteristic.server2Client.uuid, properties: [.notify], value: nil, permissions: [])
        server.finishResponse()
        #expect(fixture.engagement.isSessionTerminated)
        #expect(server.stateCharacteristic != nil && server.server2ClientCharacteristic != nil)
        server.didUnsubscribe(peer)
        #expect(server.stateCharacteristic == nil && server.server2ClientCharacteristic == nil)
    }

    @Test func admittedEngagementCleanupCannotDeleteReplacement() async throws {
        let old = try await Fixture()
        let fresh = try await Fixture()
        let delegate = CleanupDelegate(engagement: fresh.engagement, session: fresh.session)
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        _ = try server.advertisingState.admit(old.engagement)
        server.advertisedEngagement = old.engagement
        await server.terminateSession()?.value
        #expect(old.engagement.isSessionTerminated)
        #expect(!fresh.engagement.isSessionTerminated)
        #expect(delegate.deviceEngagement?.privateKey?.privateKeyId == fresh.engagement.privateKey?.privateKeyId)
        #expect(delegate.sessionEncryption != nil)
    }

    @Test func replacingEngagementEndsOldTimerWithoutClearingNewSession() async throws {
        let old = try await Fixture()
        let delegate = CleanupDelegate(engagement: old.engagement, session: old.session)
        let server = MdocGattServer(peripheralManager: nil)
        server.delegate = delegate
        server.advertisedEngagement = old.engagement
        let clock = TimeoutTestClock()
        server.monitorInactivity(using: clock.makeTimer())
        clock.advance(100)
        let fresh = try await Fixture()
        delegate.deviceEngagement = fresh.engagement
        delegate.sessionEncryption = fresh.session
        server.monitorInactivity(using: clock.makeTimer())
        #expect(old.engagement.isSessionTerminated)
        #expect(!fresh.engagement.isSessionTerminated)
        clock.advance(200)
        clock.deliver()
        #expect(!fresh.engagement.isSessionTerminated)
        #expect(delegate.sessionEncryption != nil)
        server.stop()
    }
    #endif

    private struct Fixture: Sendable {
        typealias Decoded = (sessionEncryption: SessionEncryption, deviceRequest: DeviceRequest, userRequestInfo: UserRequestInfo, isValidRequest: Bool)
        let engagement: DeviceEngagement
        let session: SessionEncryption
        let readerKey: CoseKey
        let deviceSecret: SymmetricKey
        let readerSecret: SymmetricKey

        init(storage: SessionTestKeyStorage = SessionTestKeyStorage()) async throws {
            let area = SoftwareSecureArea.create(storage: storage)
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

        func decode(data: Data? = nil) async -> Result<Decoded, Error> {
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
                return await MdocHelpers.decodeRequestAndInformUser(deviceEngagement: engagement, docs: [:], docMetadata: [:], trustValidator: NoReaderTrust(),
                    requestData: data ?? establishment(ciphertext: Array(encrypted.dropFirst(12))), privateKeyObjects: [:], dauthMethod: .deviceSignature,
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
    var info: [String: [String: Data]] = [:]
    var data: [String: [Int: [String: Data]]] = [:]
    func readKeyInfo(id: String) async throws -> [String: Data] { info[id] ?? [:] }
    private var readPaused = false
    private var readContinuation: CheckedContinuation<Void, Never>?
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    private var deletionPaused = false
    private var deletionContinuation: CheckedContinuation<Void, Never>?
    private var deletionWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var deletedIDs: [String] = []
    func pauseRead() { readPaused = true }
    func waitForRead() async {
        if readContinuation == nil { await withCheckedContinuation { readWaiters.append($0) } }
    }
    func resumeRead() { readContinuation?.resume(); readContinuation = nil }
    func pauseDeletion() { deletionPaused = true }
    func waitForDeletion() async {
        if deletionContinuation == nil { await withCheckedContinuation { deletionWaiters.append($0) } }
    }
    func resumeDeletion() { deletionContinuation?.resume(); deletionContinuation = nil }
    func readKeyData(id: String, index: Int, authenticationContext: ThreadSafeAuthContext) async throws -> [String: Data] {
        if readPaused {
            readPaused = false
            await withCheckedContinuation { continuation in
                readContinuation = continuation
                readWaiters.forEach { $0.resume() }; readWaiters.removeAll()
            }
        }
        return data[id]?[index] ?? [:]
    }
    func writeKeyInfo(id: String, dict: [String: Data]) async throws { info[id] = dict }
    func writeKeyDataBatch(id: String, startIndex: Int, dicts: [[String: Data]], keyOptions: KeyOptions?) async throws {
        for (offset, dict) in dicts.enumerated() { data[id, default: [:]][startIndex + offset] = dict }
    }
    func deleteKeyBatch(id: String, startIndex: Int, batchSize: Int) async throws {
        if deletionPaused {
            deletionPaused = false
            await withCheckedContinuation { continuation in
                deletionContinuation = continuation
                deletionWaiters.forEach { $0.resume() }; deletionWaiters.removeAll()
            }
        }
        deletedIDs.append(id)
        for index in startIndex..<(startIndex + batchSize) { data[id]?[index] = nil }
    }
    func deleteKeyInfo(id: String) async throws { info[id] = nil }
}

private final class CleanupDelegate: MdocOfflineDelegate {
    var deviceEngagement: DeviceEngagement?
    var deviceRequest: DeviceRequest?
    var sessionEncryption: SessionEncryption?
    var docs: [String: IssuerSigned]! = [:]
    var docMetadata: [String: Data?]! = [:]
    var trustValidator: any CertificateTrustValidator = NoReaderTrust()
    var privateKeyObjects: [String: CoseKeyPrivate]! = [:]
    var dauthMethod: DeviceAuthMethod = .deviceSignature
    var zkSystemRepository: ZkSystemRepository?
    var readerName: String?
    var qrCodePayload: String? = "old"
    var unlockData: [String: Data]! = [:]
    var deviceResponseBytes: Data? = Data([1])
    var responseMetadata: [Data?]! = []
    var zkpDocumentIds: [String]?
    init(engagement: DeviceEngagement, session: SessionEncryption?) {
        deviceEngagement = engagement
        sessionEncryption = session
    }
    func didChangeStatus(_ newStatus: TransferStatus) {}
    var errors: [Error] = []
    func didFinishedWithError(_ error: Error) { errors.append(error) }
    func didReceiveRequest(_ data: Data) {}
    func didPoweredOn(isPeripheralManager: Bool) {}
    func didConnected(isPeripheral: Bool, deviceName: String?) {}
    func didPublishedPsmChannel(psm: UInt16?) {}
}
