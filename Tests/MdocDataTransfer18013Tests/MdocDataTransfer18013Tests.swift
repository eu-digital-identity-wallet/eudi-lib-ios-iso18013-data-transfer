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
import MdocDataModel18013
import SwiftCBOR
@testable import MdocDataTransfer18013

struct MdocDataTransfer18013Tests {
	@Test(arguments: [false, true])
	func rejectsAmbiguousDocumentRequests(withSelectedItems: Bool) async throws {
		// Different element sets expose the first-request/last-verdict mismatch in either order.
		let broad = docRequest("org.iso.18013.5.1.mDL", elements: ["family_name", "portrait"])
		let narrow = docRequest("org.iso.18013.5.1.mDL", elements: ["family_name"])
		let requests = [
			[broad, narrow], [narrow, broad],
			[docRequest("unknown"), docRequest("unknown")],
			[docRequest("\u{00e9}"), docRequest("e\u{0301}")],
			[broad, docRequest("")], [docRequest(""), broad],
			[docRequest("")]
		]
		for documents in requests {
			let request = try deviceRequest(documents)
			do {
				_ = try await response(request, selectedItems: withSelectedItems ? [:] : nil)
				Issue.record("Accepted duplicate or empty docType")
			} catch {
				let error = error as NSError
				#expect(error.domain == "MdocHelpers")
				#expect(error.code == ErrorCode.requestDecodeError.rawValue)
			}
		}
	}

	@Test(arguments: [false, true])
	func acceptsUniqueDocumentRequests(withSelectedItems: Bool) async throws {
		for documents in [[docRequest("mdl")], [docRequest("mdl"), docRequest("pid")]] {
			let request = try deviceRequest(documents)
			let result = try await response(request, selectedItems: withSelectedItems ? [:] : nil)
			#expect(result != nil)
		}
	}

	@Test func acceptsSelectedItemsWithoutDeviceRequest() async throws {
		let result = try await response(nil, selectedItems: [:])
		#expect(result != nil)
	}

	@Test func preservesSingleAuthenticationResults() {
		for key in ["", "mdl"] {
			for isValidated in [false, true] {
				var request = requestInfo()
				request.readerAuthResults = [key: auth(isValidated, leaf: nil)]
				#expect(request.defaultReaderAuthResult?.isValidated == isValidated)
				#expect(request.defaultReaderAuthResult?.certificateIssuer == "Reader")
			}
		}
		#expect(requestInfo().defaultReaderAuthResult == nil)
	}

	@Test func doesNotPromoteOneDocumentsAuthenticationToTheWholeRequest() {
		for other in [auth(false), auth(false, leaf: nil), auth(true, leaf: Data([2])), auth(true, leaf: nil)] {
			var request = requestInfo()
			request.readerAuthResults = ["mdl": auth(true), "pid": other]
			#expect(request.defaultReaderAuthResult == nil)
			request.readerAuthResults = ["": auth(true), "mdl": other]
			#expect(request.defaultReaderAuthResult == nil)
		}
	}

	@Test func returnsSharedReaderOnlyWhenEveryDocumentAuthenticates() {
		var request = requestInfo()
		request.readerAuthResults = [
			"mdl": auth(true, authBytes: Data([1])),
			"pid": auth(true, authBytes: Data([2]))
		]
		#expect(request.defaultReaderAuthResult?.isValidated == true)
		#expect(request.defaultReaderAuthResult?.certificateChain?.first == Data([1]))
		// Selection is stable and signatures need not match across different ItemsRequests.
		#expect(request.defaultReaderAuthResult?.authBytes == Data([1]))
	}

	private func requestInfo() -> UserRequestInfo {
		UserRequestInfo(docDataFormats: [:], itemsRequested: [:])
	}

	private func auth(_ valid: Bool, leaf: Data? = Data([1]), authBytes: Data? = nil) -> ReaderAuthenticationResult {
		ReaderAuthenticationResult(isValidated: valid, certificateIssuer: "Reader", authBytes: authBytes, certificateChain: leaf.map { [$0] })
	}

	private func docRequest(_ type: String, elements: [String] = ["family_name"]) -> CBOR {
		let items: CBOR = .map([
			.utf8String("docType"): .utf8String(type),
			.utf8String("nameSpaces"): .map([
				.utf8String("org.iso.18013.5.1"): .map(
					.init(uniqueKeysWithValues: elements.map { (CBOR.utf8String($0), CBOR.boolean(false)) })
				)
			])
		])
		return .map([.utf8String("itemsRequest"): .tagged(.encodedCBORDataItem, .byteString(items.encode()))])
	}

	private func deviceRequest(_ documents: [CBOR]) throws -> DeviceRequest {
		try DeviceRequest(cbor: .map([
			.utf8String("version"): .utf8String("1.0"),
			.utf8String("docRequests"): .array(documents)
		]))
	}

	private func response(_ request: DeviceRequest?, selectedItems: RequestItems?) async throws -> DeviceResponse? {
		try await MdocHelpers.getDeviceResponseToSend(
			deviceRequest: request, issuerSigned: [:], docMetadata: [:], selectedItems: selectedItems,
			privateKeyObjects: [:], dauthMethod: .deviceSignature, unlockData: [:],
			authenticationContext: ThreadSafeAuthContext()
		)?.deviceResponse
	}
}
