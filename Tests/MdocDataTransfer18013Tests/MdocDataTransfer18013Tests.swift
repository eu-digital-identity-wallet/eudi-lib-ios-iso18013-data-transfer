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

import Testing
import Foundation
import MdocDataModel18013
import MdocSecurity18013
import SwiftCBOR
@testable import MdocDataTransfer18013

struct MdocDataTransfer18013Tests {
    @Test func statusOnlyErrorDoesNotRequireEncryption() async throws {
        // BLE prepares this fallback before preparing the real response. It must
        // not require a key or consume a counter for ciphertext that is discarded.
        let response = DeviceResponse(status: 0)
        let result = await MdocHelpers.getSessionDataToSend(
            sessionEncryption: nil, status: .error, docToSend: response)
        let (wireData, clearData) = try result.get()
        let cbor = try #require(try CBOR.decode(Array(wireData)))
        let sessionData = try SessionData(cbor: cbor)
        #expect(sessionData.status == 11)
        #expect(sessionData.data == nil)
        #expect(clearData == Data(response.toCBOR(options: CBOROptions()).encode()))
    }

    @Test func documentResponseStillRequiresEncryption() async {
        let result = await MdocHelpers.getSessionDataToSend(
            sessionEncryption: nil, status: .requestReceived,
            docToSend: DeviceResponse(status: 0))
        if case .success = result {
            Issue.record("A document response must not succeed without session encryption")
        }
    }
}
