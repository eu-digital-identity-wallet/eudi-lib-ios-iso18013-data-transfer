import CoreBluetooth
import Foundation
import SwiftCBOR
import Testing
@testable import MdocDataTransfer18013

struct ReaderIdentTests {
    private var engagement: [UInt8] {
        let key = CBOR.map([
            1: 2, -1: 1,
            -2: .byteString(Array(UInt8(0)...31)),
            -3: .byteString(Array(UInt8(32)...63))
        ])
        return CBOR.map([0: "1.0", 1: .array([1, .tagged(.encodedCBORDataItem, .byteString(key.encode()))])]).encode()
    }

    @Test func derivesIdentFromTaggedEncodedDeviceKey() throws {
        // Independently calculated with RFC 5869 HMAC-SHA256, empty salt,
        // info BLEIdent and IKM d818584b + the encoded COSE key above.
        let expected = Data([0x65, 0x6b, 0xbf, 0xc0, 0xf6, 0x64, 0xdc, 0x52,
                             0xbf, 0xcf, 0x57, 0x32, 0x50, 0xff, 0x77, 0xea])
        #expect(ReaderIdent.expected(engagement: engagement) == expected)
        #expect(ReaderIdent.matches(expected, engagement: engagement))
    }

    @Test func rejectsMissingMalformedAndMismatchedIdent() throws {
        let correct = try #require(ReaderIdent.expected(engagement: engagement))
        for value: Data? in [nil, Data(), Data(correct.prefix(15)), correct + Data([0]), Data(repeating: 0, count: 16)] {
            #expect(!ReaderIdent.matches(value, engagement: engagement))
        }
        var differentEngagement = engagement
        differentEngagement[differentEngagement.count - 1] ^= 1
        #expect(!ReaderIdent.matches(correct, engagement: differentEngagement))
    }

    @Test func rejectsMissingOrMalformedEngagement() {
        for bytes: [UInt8]? in [nil, [], [0xff], CBOR.map([:]).encode(), CBOR.map([1: .array([1, .byteString([1])])]).encode()] {
            #expect(ReaderIdent.expected(engagement: bytes) == nil)
            #expect(!ReaderIdent.matches(Data(repeating: 0, count: 16), engagement: bytes))
        }
    }

    @Test @MainActor func rejectionClearsCandidateStateWithoutEndingEngagement() {
        let central = MdocGattCentral(initializeBluetooth: false)
        central.hasReaderIdentity = true
        central.didSendStartRequest = true
        central.readBuffer = Data([1, 2])
        central.sendBuffer = [Data([3])]
        central.maximumCharacteristicSize = 100
        central.stateCharacteristic = CBMutableCharacteristic(type: CBUUID(string: "1234"), properties: [.notify], value: nil, permissions: [.readable])
        central.readCharacteristic = central.stateCharacteristic
        central.writeCharacteristic = central.stateCharacteristic
        central.rejectReaderCandidate()
        #expect(!central.hasReaderIdentity)
        #expect(!central.didSendStartRequest)
        #expect(central.readBuffer.isEmpty && central.sendBuffer.isEmpty)
        #expect(central.maximumCharacteristicSize == nil)
        #expect(central.stateCharacteristic == nil && central.readCharacteristic == nil && central.writeCharacteristic == nil)
        #expect(central.error == nil)
        central.stop()
    }
}
