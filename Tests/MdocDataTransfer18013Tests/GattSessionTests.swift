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

struct GattSessionTests {
    let owner = UUID()
    let stranger = UUID()

    func connected() -> GattSession {
        var session = GattSession()
        let subscribed1 = session.subscribe(.state, central: owner, status: .qrEngagementReady)
        #expect(subscribed1)
        let subscribed2 = session.subscribe(.serverToClient, central: owner, status: .qrEngagementReady)
        #expect(subscribed2)
        return session
    }

    @Test func subscriptionsCannotBeCombinedOrCountedTwice() {
        var session = GattSession()
        let subscribed3 = !session.subscribe(.clientToServer, central: stranger, status: .qrEngagementReady)
        #expect(subscribed3)
        #expect(session.centralID == nil)
        let subscribed4 = session.subscribe(.state, central: owner, status: .qrEngagementReady)
        #expect(subscribed4)
        let subscribed5 = session.subscribe(.state, central: owner, status: .qrEngagementReady)
        #expect(subscribed5)
        #expect(!session.ready)
        let subscribed6 = !session.subscribe(.serverToClient, central: stranger, status: .qrEngagementReady)
        #expect(subscribed6)
        #expect(session.centralID == owner)
        #expect(!session.ready)
        let subscribed7 = session.subscribe(.serverToClient, central: owner, status: .qrEngagementReady)
        #expect(subscribed7)
        #expect(session.ready)
        let subscribed8 = !session.subscribe(.state, central: stranger, status: .connected)
        #expect(subscribed8)
    }

    @Test func unrelatedCentralCannotModifyActiveRequest() throws {
        var session = connected()
        #expect(try session.write(Data([1]), characteristic: .state, central: owner, status: .connected) == .started)
        #expect(try session.write(Data([1, 10]), characteristic: .clientToServer, central: owner, status: .started) == .fragment)
        for bytes: [UInt8] in [[1], [2]] {
            #expect(throws: GattSession.Rejection.unauthorized) {
                try session.write(Data(bytes), characteristic: .state, central: stranger, status: .started)
            }
        }
        for bytes: [UInt8] in [[1, 99], [0, 99]] {
            #expect(throws: GattSession.Rejection.unauthorized) {
                try session.write(Data(bytes), characteristic: .clientToServer, central: stranger, status: .started)
            }
        }
        #expect(!session.acceptsUnsubscribe(.state, central: stranger))
        #expect(session.centralID == owner)
        #expect(session.readBuffer == Data([10]))
        #expect(try session.write(Data([0, 20]), characteristic: .clientToServer, central: owner, status: .started) == .request(Data([10, 20])))
        #expect(session.readBuffer.isEmpty)
    }

    @Test func writesRequireSubscriptionsAndValidPhase() throws {
        var session = GattSession()
        #expect(throws: GattSession.Rejection.unauthorized) {
            try session.write(Data([1]), characteristic: .state, central: owner, status: .qrEngagementReady)
        }
        session = connected()
        for status in [TransferStatus.connected, .qrEngagementReady, .requestReceived, .responseSent, .disconnected, .error] {
            #expect(throws: GattSession.Rejection.invalidState) {
                try session.write(Data([0, 10]), characteristic: .clientToServer, central: owner, status: status)
            }
        }
        _ = try session.write(Data([1, 10]), characteristic: .clientToServer, central: owner, status: .started)
        #expect(throws: GattSession.Rejection.invalidState) {
            try session.write(Data([1]), characteristic: .state, central: owner, status: .started)
        }
        #expect(session.readBuffer == Data([10]))
        for bytes: [UInt8] in [[], [1, 2], [3]] {
            #expect(throws: GattSession.Rejection.invalidValue) {
                try session.write(Data(bytes), characteristic: .state, central: owner, status: .connected)
            }
        }
        #expect(session.readBuffer == Data([10]))
    }

    @Test func teardownClearsOwnershipAndReassembly() throws {
        var session = connected()
        _ = try session.write(Data([1, 10]), characteristic: .clientToServer, central: owner, status: .started)
        #expect(session.acceptsUnsubscribe(.state, central: owner))
        #expect(!session.acceptsUnsubscribe(.clientToServer, central: owner))
        #expect(try session.write(Data([2]), characteristic: .state, central: owner, status: .started) == .ended)
        let oldGeneration = session.generation
        session.reset()
        #expect(session.generation != oldGeneration)
        #expect(session.centralID == nil)
        #expect(session.subscriptions.isEmpty)
        #expect(session.readBuffer.isEmpty)
        #expect(!session.acceptsUnsubscribe(.state, central: owner))
        let subscribed9 = session.subscribe(.serverToClient, central: stranger, status: .qrEngagementReady)
        #expect(subscribed9)
        #expect(!session.ready)
    }
}
