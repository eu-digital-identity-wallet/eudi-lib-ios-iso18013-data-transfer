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
import MdocSecurity18013
import SwiftCBOR
@testable import MdocDataTransfer18013

struct SelectedItemsTests {
	private static let namespace = IsoMdlModel.isoNamespace
	private static let otherNamespace = "example.extra"

	@Test(arguments: [false, true])
	func emptySelectionsDiscloseNothing(withRequest: Bool) async throws {
		let fixture = try await Fixture()
		let request = withRequest ? try deviceRequest(["family_name"]) : nil
		for selection: [String: [RequestItem]] in [[:], [Self.namespace: []], [Self.namespace: [], Self.otherNamespace: []]] {
			let readsBefore = await fixture.storage.reads
			let result = try await fixture.respond(selected: ["doc-1": selection], request: request,
				deviceNamespaces: ["doc-1": DeviceNameSpaces(deviceNameSpaces: [:])], zkRepository: .init(systems: [RejectingZkSystem()]))
			#expect(result.response.documents?.isEmpty ?? true)
			#expect(result.response.zkDocuments?.isEmpty ?? true)
			#expect(result.valid.isEmpty)
			#expect(result.ids.isEmpty)
			#expect(result.metadata.isEmpty)
			#expect(await fixture.storage.reads == readsBefore)
		}
	}

	@Test func emptyOuterSelectionDisclosesNothing() async throws {
		let fixture = try await Fixture()
		let result = try await fixture.respond(selected: [:])
		#expect(result.response.documents == nil)
		#expect(result.ids.isEmpty)
		#expect(result.metadata.isEmpty)
	}

	@Test(arguments: [false, true])
	func explicitSelectionProducesOnlySelectedFields(withRequest: Bool) async throws {
		let fixture = try await Fixture()
		let request = withRequest ? try deviceRequest(["family_name", "portrait"]) : nil
		let result = try await fixture.respond(selected: ["doc-1": [Self.namespace: [.init(elementIdentifier: "family_name")], Self.otherNamespace: []]], request: request)
		let document = try #require(result.response.documents?.first)
		#expect(document.issuerSigned.issuerNameSpaces?.nameSpaces.keys.sorted() == [Self.namespace])
		#expect(document.issuerSigned.issuerNameSpaces?[Self.namespace]?.map(\.elementIdentifier) == ["family_name"])
		#expect(result.ids == ["doc-1"])
		#expect(result.metadata == [Data([1])])
		try fixture.verifySignature(document)
	}

	@Test(arguments: [false, true])
	func selectionIsBoundedByTheSuppliedRequest(allowFullDisclosure: Bool) async throws {
		let fixture = try await Fixture()
		let selected: RequestItems = ["doc-1": [
			Self.namespace: ["family_name", "portrait"].map(RequestItem.init(elementIdentifier:)),
			Self.otherNamespace: [.init(elementIdentifier: "address")]
		]]
		let result = try await fixture.respond(selected: selected, request: deviceRequest(["family_name"]), allowFullDisclosure: allowFullDisclosure)
		let document = try #require(result.response.documents?.first)
		#expect(document.issuerSigned.issuerNameSpaces?[Self.namespace]?.map(\.elementIdentifier) == ["family_name"])
		#expect(document.issuerSigned.issuerNameSpaces?[Self.otherNamespace] == nil)
		#expect(result.valid[IsoMdlModel.isoDocType]?[Self.namespace]?.first?.intentToRetain == true)
		#expect(result.errors[IsoMdlModel.isoDocType]?[Self.namespace]?.map(\.elementIdentifier) == ["portrait"])
		#expect(result.errors[IsoMdlModel.isoDocType]?[Self.otherNamespace]?.map(\.elementIdentifier) == ["address"])
		try fixture.verifySignature(document)
		// Without a DeviceRequest, the explicit selection remains the authority (OpenID4VP).
		let requestless = try await fixture.respond(selected: selected, allowFullDisclosure: allowFullDisclosure)
		#expect(requestless.response.documents?.first?.issuerSigned.issuerNameSpaces?[Self.namespace]?.count == 2)
		#expect(requestless.response.documents?.first?.issuerSigned.issuerNameSpaces?[Self.otherNamespace]?.count == 1)
	}

	@Test func unrequestedCredentialDisclosesNothing() async throws {
		let fixture = try await Fixture()
		let result = try await fixture.respond(selected: ["doc-1": [Self.namespace: [.init(elementIdentifier: "family_name")]]],
			request: deviceRequest(["family_name"], docType: "other.credential"))
		#expect(result.response.documents == nil)
		#expect(result.ids.isEmpty)
		#expect(result.metadata.isEmpty)
	}

	@Test func missingSelectedFieldsRemainErrors() async throws {
		let fixture = try await Fixture()
		let result = try await fixture.respond(selected: ["doc-1": [Self.namespace: ["family_name", "missing"].map(RequestItem.init(elementIdentifier:))]])
		#expect(result.response.documents?.first?.issuerSigned.issuerNameSpaces?[Self.namespace]?.map(\.elementIdentifier) == ["family_name"])
		#expect(result.errors[IsoMdlModel.isoDocType]?[Self.namespace]?.map(\.elementIdentifier) == ["missing"])
	}

	@Test(arguments: [false, true], [false, true])
	func selectedAgeAttestationsAreMinimised(withRequest: Bool, allowFullDisclosure: Bool) async throws {
		let fixture = try await Fixture()
		let elements = ["family_name", "age_over_18", "age_over_21", "age_over_65"]
		let request = withRequest ? try deviceRequest(elements) : nil
		let result = try await fixture.respond(selected: ["doc-1": [Self.namespace: elements.map(RequestItem.init(elementIdentifier:))]], request: request, allowFullDisclosure: allowFullDisclosure)
		let items = try #require(result.response.documents?.first?.issuerSigned.issuerNameSpaces?[Self.namespace])
		#expect(items.contains { $0.elementIdentifier == "family_name" })
		#expect(items.filter { $0.elementIdentifier.hasPrefix("age_over_") }.count == 2)
	}

	@Test(arguments: [false, true])
	func nilSelectionPreservesRequestDrivenPreview(allowFullDisclosure: Bool) async throws {
		let fixture = try await Fixture()
		let result = try await fixture.respond(selected: nil, request: deviceRequest(["family_name"]), allowFullDisclosure: allowFullDisclosure)
		#expect(result.response.documents?.first?.issuerSigned.issuerNameSpaces?[Self.namespace]?.map(\.elementIdentifier) == ["family_name"])
	}

	@Test func omittedDocumentsDoNotShiftResponseMetadata() async throws {
		let fixture = try await Fixture()
		let result = try await fixture.respond(selected: ["doc-1": [:], "doc-2": [Self.namespace: [.init(elementIdentifier: "family_name")]]], secondDocument: true)
		#expect(result.response.documents?.count == 1)
		#expect(result.ids == ["doc-2"])
		#expect(result.metadata == [Data([2])])
	}

	@Test(arguments: ["requestless", "narrow-request", "unrelated-request"])
	func fullDisclosureRequiresExplicitOptIn(mode: String) async throws {
		let fixture = try await Fixture()
		let request: DeviceRequest? = switch mode {
		case "narrow-request": try deviceRequest(["family_name"])
		case "unrelated-request": try deviceRequest(["family_name"], docType: "other.credential")
		default: nil
		}
		let result = try await fixture.respond(selected: ["doc-1": [:]], request: request, allowFullDisclosure: true)
		let document = try #require(result.response.documents?.first)
		let actual = document.issuerSigned.issuerNameSpaces?.nameSpaces.mapValues { $0.map(\.elementIdentifier).sorted() }
		let expected = fixture.credential.issuerNameSpaces?.nameSpaces.mapValues { $0.map(\.elementIdentifier).sorted() }
		#expect(actual == expected)
		#expect(result.ids == ["doc-1"])
		#expect(result.metadata == [Data([1])])
		try fixture.verifySignature(document)
	}

	@Test func fullDisclosureOptionDoesNotExpandEmptyArraysOrOuterMap() async throws {
		let fixture = try await Fixture()
		for selected: RequestItems in [[:], ["doc-1": [Self.namespace: []]], ["doc-1": [Self.namespace: [], Self.otherNamespace: []]]] {
			let readsBefore = await fixture.storage.reads
			let result = try await fixture.respond(selected: selected, allowFullDisclosure: true)
			#expect(result.response.documents == nil)
			#expect(result.ids.isEmpty)
			#expect(result.metadata.isEmpty)
			#expect(await fixture.storage.reads == readsBefore)
		}
	}

	@Test func fullDisclosureOptionAppliesOnlyToEmptyDocumentEntries() async throws {
		let fixture = try await Fixture()
		let result = try await fixture.respond(selected: ["doc-1": [:], "doc-2": [Self.namespace: [.init(elementIdentifier: "family_name")]]],
			secondDocument: true, allowFullDisclosure: true)
		let documents = try #require(result.response.documents)
		#expect(documents.count == 2)
		for (index, id) in result.ids.enumerated() {
			let fields = try #require(documents[index].issuerSigned.issuerNameSpaces?.nameSpaces)
			if id == "doc-1" {
				#expect(fields.values.reduce(0) { $0 + $1.count } == 7)
				#expect(result.metadata[index] == Data([1]))
			} else {
				#expect(fields.keys.sorted() == [Self.namespace])
				#expect(fields[Self.namespace]?.map(\.elementIdentifier) == ["family_name"])
				#expect(result.metadata[index] == Data([2]))
			}
		}
	}

	private func deviceRequest(_ elements: [String], docType: String = IsoMdlModel.isoDocType) throws -> DeviceRequest {
		let items: CBOR = .map([
			.utf8String("docType"): .utf8String(docType),
			.utf8String("nameSpaces"): .map([.utf8String(Self.namespace): .map(.init(uniqueKeysWithValues: elements.map { (CBOR.utf8String($0), CBOR.boolean(true)) }))])
		])
		return try DeviceRequest(cbor: .map([
			.utf8String("version"): .utf8String("1.0"),
			.utf8String("docRequests"): .array([.map([.utf8String("itemsRequest"): .tagged(.encodedCBORDataItem, .byteString(items.encode()))])])
		]))
	}

	private struct Fixture {
		let storage: SelectionKeyStorage
		let key: CoseKeyPrivate
		let publicKey: CoseKey
		let credential: IssuerSigned
		let transcript = SessionTranscript(handOver: .null)

		init() async throws {
			storage = SelectionKeyStorage()
			var privateKey = try await CoseKeyPrivate(secureArea: SoftwareSecureArea.create(storage: storage), keyOptions: KeyOptions(curve: .P256))
			publicKey = try await privateKey.key
			key = privateKey
			let names = ["family_name", "portrait", "document_number", "age_over_18", "age_over_21", "age_over_65"]
			let items = try names.enumerated().map { index, name in
				try IssuerSignedItem(cbor: .map([
					.utf8String("digestID"): .unsignedInt(UInt64(index)), .utf8String("random"): .byteString([0]),
					.utf8String("elementIdentifier"): .utf8String(name),
					.utf8String("elementValue"): name.hasPrefix("age_over_") ? .boolean(name != "age_over_65") : .utf8String("test")
				]))
			}
			let address = try IssuerSignedItem(cbor: .map([
				.utf8String("digestID"): .unsignedInt(0), .utf8String("random"): .byteString([0]),
				.utf8String("elementIdentifier"): .utf8String("address"), .utf8String("elementValue"): .utf8String("test")
			]))
			let mso = MobileSecurityObject(version: "1.0", digestAlgorithm: "SHA-256", valueDigests: .init(valueDigests: [:]), deviceKey: publicKey,
				docType: IsoMdlModel.isoDocType, validityInfo: .init(signed: "2026-01-01T00:00:00Z", validFrom: "2026-01-01T00:00:00Z", validUntil: "2030-01-01T00:00:00Z"))
			// Issuer trust is outside this helper's boundary; use a synthetic stored credential.
			let issuerAuth = IssuerAuth(mso: mso, msoRawData: mso.toCBOR(options: CBOROptions()).taggedEncoded.encode(), verifyAlgorithm: .es256,
				signature: Data(repeating: 0, count: 64), x5chain: [], statusList: nil)
			credential = IssuerSigned(issuerNameSpaces: .init(nameSpaces: [SelectedItemsTests.namespace: items, SelectedItemsTests.otherNamespace: [address]]), issuerAuth: issuerAuth)
		}

		func respond(selected: RequestItems?, request: DeviceRequest? = nil, secondDocument: Bool = false, deviceNamespaces: RequestDeviceNameSpaces? = nil, zkRepository: ZkSystemRepository? = nil, allowFullDisclosure: Bool = false) async throws
			-> (response: DeviceResponse, valid: RequestItems, errors: RequestItems, metadata: [Data?], ids: [String]) {
			let docs = secondDocument ? ["doc-1": credential, "doc-2": credential] : ["doc-1": credential]
			let result = try #require(try await MdocHelpers.getDeviceResponseToSend(deviceRequest: request, issuerSigned: docs,
				docMetadata: ["doc-1": Data([1]), "doc-2": Data([2])], selectedItems: selected, allowFullDisclosureForEmptySelection: allowFullDisclosure,
				privateKeyObjects: ["doc-1": key, "doc-2": key], sessionTranscript: transcript, dauthMethod: .deviceSignature,
				unlockData: [:], zkSpecsRequested: zkRepository.map { [IsoMdlModel.isoDocType: $0.getAllZkSystemSpecs()] },
				zkSystemRepository: zkRepository, deviceNameSpacesRequested: deviceNamespaces, authenticationContext: ThreadSafeAuthContext()))
			let decoded = try DeviceResponse(data: result.deviceResponse.encode(options: CBOROptions()))
			return (decoded, result.validRequestItems, result.errorRequestItems, result.responseMetadata, result.documentIds)
		}

		func verifySignature(_ document: Document) throws {
			guard case let .map(signed) = document.deviceSigned.toCBOR(options: CBOROptions()),
				case let .map(map) = signed[.utf8String("deviceAuth")],
				let signatureCbor = map[.utf8String("deviceSignature")], let signature = Cose(type: .sign1, cbor: signatureCbor)
			else { Issue.record("Missing device signature"); return }
			let payload: CBOR = .array([.utf8String("DeviceAuthentication"), transcript.toCBOR(options: CBOROptions()),
				.utf8String(IsoMdlModel.isoDocType), CBOR.map([:]).taggedEncoded])
			#expect(try signature.validateDetachedCoseSign1(payloadData: Data(payload.taggedEncoded.encode()), publicKey_x963: publicKey.x963Representation))
		}
	}
}

private struct RejectingZkSystem: ZkSystemProtocol {
	let name = "selection-test"
	var systemSpecs: [ZkSystemSpec] { [.init(zkSystemId: name, system: name, params: [:])] }
	func getMatchingSystemSpec(zkSystemSpecs: [ZkSystemSpec], numAttributesRequested: Int64) -> ZkSystemSpec? { zkSystemSpecs.first }
	func generateProof(zkSystemSpec: ZkSystemSpec, docBytes: [UInt8], x: String?, y: String?, sessionTranscriptBytes: [UInt8], timestamp: Date) throws -> ZkDocument {
		Issue.record("Empty selection reached proof generation")
		throw NSError(domain: "SelectedItemsTests", code: 1)
	}
	func verifyProof(zkDocument: ZkDocument, zkSystemSpec: ZkSystemSpec, sessionTranscriptBytes: [UInt8]) throws {
		throw NSError(domain: "SelectedItemsTests", code: 1)
	}
}

private actor SelectionKeyStorage: SecureKeyStorage {
	private var info: [String: [String: Data]] = [:]
	private var data: [String: [Int: [String: Data]]] = [:]
	private(set) var reads = 0

	func readKeyInfo(id: String) async throws -> [String: Data] { info[id] ?? [:] }
	func readKeyData(id: String, index: Int, authenticationContext: ThreadSafeAuthContext) async throws -> [String: Data] {
		reads += 1
		return data[id]?[index] ?? [:]
	}
	func writeKeyInfo(id: String, dict: [String: Data]) async throws { info[id] = dict }
	func writeKeyDataBatch(id: String, startIndex: Int, dicts: [[String: Data]], keyOptions: KeyOptions?) async throws {
		for (offset, dict) in dicts.enumerated() { data[id, default: [:]][startIndex + offset] = dict }
	}
	func deleteKeyBatch(id: String, startIndex: Int, batchSize: Int) async throws {
		for index in startIndex..<(startIndex + batchSize) { data[id]?[index] = nil }
	}
	func deleteKeyInfo(id: String) async throws { info[id] = nil }
}
