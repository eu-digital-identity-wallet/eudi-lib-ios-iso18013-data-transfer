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
