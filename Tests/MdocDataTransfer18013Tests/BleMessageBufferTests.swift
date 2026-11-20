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
import Testing
@testable import MdocDataTransfer18013

struct BleMessageBufferTests {
    @Test func exactLimitAndSuccessiveMessages() throws {
        var buffer = BleMessageBuffer()
        let payload = Data(repeating: 7, count: BleMessageBuffer.maximumMessageSize)
        #expect(try buffer.append(payload, isFinal: false) == nil)
        #expect(try buffer.append(Data(), isFinal: true) == payload)
        #expect(buffer.data.isEmpty)
        #expect(try buffer.append(Data([9]), isFinal: true) == Data([9]))
        #expect(buffer.data.isEmpty)
    }

    @Test(arguments: [false, true]) func overflowReleasesPartialMessage(isFinal: Bool) throws {
        var buffer = BleMessageBuffer()
        _ = try buffer.append(Data(repeating: 7, count: BleMessageBuffer.maximumMessageSize), isFinal: false)
        #expect(throws: BleMessageBuffer.Failure.messageTooLarge) {
            try buffer.append(Data([8]), isFinal: isFinal)
        }
        #expect(buffer.data.isEmpty)
    }

    @Test func oversizedFirstFragmentIsRejected() {
        var buffer = BleMessageBuffer()
        #expect(throws: BleMessageBuffer.Failure.messageTooLarge) {
            try buffer.append(Data(repeating: 1, count: BleMessageBuffer.maximumMessageSize + 1), isFinal: true)
        }
        #expect(buffer.data.isEmpty)
    }

    @Test func teardownDiscardsIncompleteMessage() throws {
        var buffer = BleMessageBuffer()
        _ = try buffer.append(Data([1, 2]), isFinal: false)
        buffer.reset()
        #expect(buffer.data.isEmpty)
        #expect(try buffer.append(Data([3]), isFinal: true) == Data([3]))
    }
}

extension GattSessionTests {
    @Test func endlessContinuationAbortsOwnershipAtLimit() throws {
        var session = connected()
        let generation = session.generation
        let fragment = Data([1]) + Data(repeating: 42, count: 512)
        for _ in 0..<(BleMessageBuffer.maximumMessageSize / 512) {
            #expect(try session.write(fragment, characteristic: .clientToServer, central: owner, status: .started) == .fragment)
        }
        #expect(throws: BleMessageBuffer.Failure.messageTooLarge) {
            try session.write(Data([1, 42]), characteristic: .clientToServer, central: owner, status: .started)
        }
        #expect(session.readBuffer.isEmpty)
        #expect(session.centralID == nil)
        #expect(!session.ready)
        #expect(session.generation != generation)
        #expect(throws: GattSession.Rejection.unauthorized) {
            try session.write(Data([0, 42]), characteristic: .clientToServer, central: owner, status: .started)
        }
    }

    @Test func exactLimitServerMessageIsDelivered() throws {
        var session = connected()
        let payload = Data(repeating: 42, count: BleMessageBuffer.maximumMessageSize)
        #expect(try session.write(Data([0]) + payload, characteristic: .clientToServer, central: owner, status: .started) == .request(payload))
        #expect(session.readBuffer.isEmpty)
    }
}
