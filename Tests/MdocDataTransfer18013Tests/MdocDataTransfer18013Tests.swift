 /*
 * Copyright (c) 2023 European Commission
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */

import XCTest
@testable import MdocDataTransfer18013

final class MdocDataTransfer18013Tests: XCTestCase {
	// XCTest Documenation
	// https://developer.apple.com/documentation/xctest
	// Defining Test Cases and Test Methods
	// https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
	
	func test_uuids() {
		XCTAssertEqual(MdocServiceCharacteristic.state.uuid.uuidString, "00000001-A123-48CE-896B-4C76973373E6")
		XCTAssertEqual(MdocServiceCharacteristic.client2Server.uuid.uuidString, "00000002-A123-48CE-896B-4C76973373E6")
		XCTAssertEqual(MdocServiceCharacteristic.server2Client.uuid.uuidString, "00000003-A123-48CE-896B-4C76973373E6")
	}
}
