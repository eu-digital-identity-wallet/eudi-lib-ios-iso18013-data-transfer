import Foundation
import Testing
@testable import MdocDataTransfer18013

struct GattPeerStateTests {
    let peer = UUID()
    let other = UUID()
    func connected() -> GattPeerState {
        var state = GattPeerState()
        let subscribed1 = state.subscribe(peer, to: .response)
        #expect(subscribed1)
        let subscribed2 = state.subscribe(peer, to: .state)
        #expect(subscribed2)
        return state
    }

    @Test func writesBeforeSubscriptionsCannotStartOrBlockRealReader() throws {
        var state = GattPeerState()
        #expect(throws: GattPeerState.Failure.self) { try state.receive([.state(Data([1]))], from: other) }
        #expect(state.centralID == nil)
        let subscribed3 = state.subscribe(peer, to: .state)
        #expect(subscribed3)
        #expect(throws: GattPeerState.Failure.self) { try state.receive([.state(Data([1]))], from: peer) }
        let subscribed4 = state.subscribe(peer, to: .response)
        #expect(subscribed4)
        if case .started = try state.receive([.state(Data([1]))], from: peer) {} else { Issue.record("START rejected") }
    }

    @Test func duplicateAndMixedPeerSubscriptionsDoNotAuthorize() {
        var state = GattPeerState()
        let subscribed5 = state.subscribe(peer, to: .state)
        #expect(subscribed5)
        let subscribed6 = state.subscribe(peer, to: .state)
        #expect(subscribed6)
        #expect(!state.ready)
        let subscribed7 = state.subscribe(other, to: .response)
        #expect(!subscribed7)
        #expect(!state.accepts(peer))
        let subscribed8 = state.subscribe(peer, to: .response)
        #expect(subscribed8)
        #expect(state.accepts(peer))
        #expect(!state.accepts(other))
    }

    @Test func validRequestAndForeignWrites() throws {
        var state = connected()
        #expect(throws: GattPeerState.Failure.self) { try state.receive([.data(Data([0,9]))], from: peer) }
        _ = try state.receive([.state(Data([1]))], from: peer)
        for write in [GattPeerState.Write.state(Data([2])), .data(Data([0,9]))] {
            #expect(throws: GattPeerState.Failure.self) { try state.receive([write], from: other) }
        }
        _ = try state.receive([.data(Data([1,10]))], from: peer)
        if case .request(let data) = try state.receive([.data(Data([0,20]))], from: peer) {
            #expect(data == Data([10,20]))
        } else { Issue.record("No request delivered") }
        #expect(throws: GattPeerState.Failure.self) { try state.receive([.data(Data([0,30]))], from: peer) }
    }

    @Test func invalidBatchRollsBackEveryWrite() throws {
        var state = connected()
        #expect(throws: GattPeerState.Failure.self) {
            try state.receive([.state(Data([1])), .data(Data([7]))], from: peer)
        }
        _ = try state.receive([.state(Data([1]))], from: peer)
        #expect(throws: GattPeerState.Failure.self) {
            try state.receive([.data(Data([1,99])), .state(Data([2,0]))], from: peer)
        }
        if case .request(let data) = try state.receive([.data(Data([0,42]))], from: peer) {
            #expect(data == Data([42]))
        } else { Issue.record("No request delivered") }
    }

    @Test func teardownInvalidatesPeerAndPendingSendGeneration() throws {
        var state = connected()
        let generation = state.generation
        _ = try state.receive([.state(Data([2]))], from: peer)
        #expect(!state.accepts(peer))
        #expect(state.generation != generation)
        #expect(state.centralID == nil)
        let subscribed9 = state.subscribe(other, to: .response)
        #expect(subscribed9)
        let subscribed10 = state.subscribe(other, to: .state)
        #expect(subscribed10)
        #expect(state.accepts(other))
        #expect(!state.accepts(peer))
    }

    #if !os(watchOS)
    @Test func responseWithoutCentralReturnsErrorInsteadOfTrapping() {
        let server = MdocGattServer(peripheralManager: nil)
        server.sendData(Data([1,2]))
        #expect(server.error != nil)
        #expect(server.status == .error)
        #expect(server.sendBuffer.isEmpty)
        server.sendDataWithUpdates()
    }
    #endif
}
