import Foundation
import Testing
@testable import MdocDataTransfer18013

struct BleMainQueueTests {
    @Test @MainActor func nestedCallsRunInline() {
        let result = BleMainQueue.sync {
            BleMainQueue.sync {
                dispatchPrecondition(condition: .onQueue(.main))
                return 42
            }
        }
        #expect(result == 42)
    }

    @Test func backgroundCallsCompleteOnMainBeforeReturning() async {
        // This test fixture's mutable state is accessed only inside BleMainQueue.sync.
        final class State: @unchecked Sendable {
            var count = 0
        }
        let state = State()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for _ in 0..<100 {
                DispatchQueue.global().async(group: group) {
                    let value = BleMainQueue.sync {
                        dispatchPrecondition(condition: .onQueue(.main))
                        state.count += 1
                        return state.count
                    }
                    #expect(value > 0)
                }
            }
            group.notify(queue: .main) {
                #expect(state.count == 100)
                continuation.resume()
            }
        }
    }

    @Test func backgroundErrorsPropagate() async {
        enum Failure: Error { case expected }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                #expect(throws: Failure.expected) {
                    try BleMainQueue.sync {
                        dispatchPrecondition(condition: .onQueue(.main))
                        throw Failure.expected
                    }
                }
                continuation.resume()
            }
        }
    }
}
