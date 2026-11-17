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

/// A State value from the reader must not crash the wallet.
struct BleStateTests {
	@Test func endRequestIsAccepted() throws {
		try MdocGattCentral.checkEndRequest(state: Data([0x02]))
	}

	@Test(arguments: [Data(), Data([0x02, 0x02])])
	func wrongLengthThrows(state: Data) {
		#expect(throws: NSError.self) { try MdocGattCentral.checkEndRequest(state: state) }
	}

	@Test func unknownStateThrows() {
		#expect(throws: NSError.self) { try MdocGattCentral.checkEndRequest(state: Data([0x01])) }
	}
}
