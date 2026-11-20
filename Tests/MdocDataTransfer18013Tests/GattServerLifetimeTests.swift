#if !os(watchOS)
import Foundation
import Testing
import MdocDataModel18013
import MdocSecurity18013
@testable import MdocDataTransfer18013

struct GattServerLifetimeTests {
    @Test func teardownAfterCoordinatorReleaseIsRepeatable() {
        let server = MdocGattServer(initializeBluetooth: false)
        var coordinator: Coordinator? = Coordinator()
        server.delegate = coordinator
        coordinator = nil
        #expect(server.delegate == nil)
        server.sendBuffer = [Data([1, 2, 3])]
        server.advertising = true
        let generation = server.session.generation
        server.stop()
        server.stop()
        #expect(server.sendBuffer.isEmpty)
        #expect(server.remoteCentral == nil)
        #expect(!server.advertising)
        #expect(server.session.generation != generation)
    }

    @Test func teardownClearsLiveCoordinatorPayload() {
        let server = MdocGattServer(initializeBluetooth: false)
        let coordinator = Coordinator()
        coordinator.qrCodePayload = "presentation"
        server.delegate = coordinator
        server.stop()
        server.stop()
        #expect(coordinator.qrCodePayload == nil)
    }

    @Test func retainedBluetoothDelegateDoesNotRetainReleasedServer() {
        var server: MdocGattServer? = MdocGattServer(initializeBluetooth: false)
        let callbackDelegate = MdocGattServer.Delegate(server: server!)
        weak var releasedServer = server
        server = nil
        #expect(releasedServer == nil)
        // A late callback now observes nil instead of dereferencing an unowned object.
        #expect(callbackDelegate.server == nil)
    }
}

private final class Coordinator: MdocOfflineDelegate {
    var deviceEngagement: DeviceEngagement?
    var deviceRequest: DeviceRequest?
    var sessionEncryption: SessionEncryption?
    var docs: [String: IssuerSigned]!
    var docMetadata: [String: Data?]!
    var trustValidator: any CertificateTrustValidator = NoTrust()
    var privateKeyObjects: [String: CoseKeyPrivate]!
    var dauthMethod: DeviceAuthMethod = .deviceSignature
    var zkSystemRepository: ZkSystemRepository?
    var readerName: String?
    var qrCodePayload: String?
    var unlockData: [String: Data]!
    var deviceResponseBytes: Data?
    var responseMetadata: [Data?]!
    var zkpDocumentIds: [String]?
    func didChangeStatus(_ newStatus: TransferStatus) {}
    func didFinishedWithError(_ error: Error) {}
    func didReceiveRequest(_ data: Data) {}
    func didPoweredOn(isPeripheralManager: Bool) {}
    func didConnected(isPeripheral: Bool, deviceName: String?) {}
    func didPublishedPsmChannel(psm: UInt16?) {}
}

private struct NoTrust: CertificateTrustValidator {
    var docType: String?
    func createCertTrustPath(chain: [Data]) async -> [Data]? { nil }
    func validateCertTrustPath(chain: [Data]) async -> (Bool, String?) { (false, nil) }
}
#endif
