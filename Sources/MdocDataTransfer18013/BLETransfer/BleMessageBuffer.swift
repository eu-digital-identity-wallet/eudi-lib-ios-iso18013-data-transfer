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

/// Resource policy for one incoming BLE message (excluding fragment prefixes).
/// This is an implementation limit, not an ISO 18013-5 protocol limit.
struct BleMessageBuffer {
    static let maximumMessageSize = 256 * 1024

    enum Failure: LocalizedError, Equatable {
        case messageTooLarge

        var errorDescription: String? {
            "BLE message exceeds the 256 KiB receive limit"
        }
    }

    private(set) var data = Data()

    mutating func append(_ payload: Data, isFinal: Bool) throws -> Data? {
        guard payload.count <= Self.maximumMessageSize - data.count else {
            reset()
            throw Failure.messageTooLarge
        }
        data.append(payload)
        guard isFinal else { return nil }
        let message = data
        reset()
        return message
    }

    mutating func reset() { data = Data() }
}
