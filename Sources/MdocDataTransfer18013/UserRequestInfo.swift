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
import MdocDataModel18013
@preconcurrency import SwiftyJSON

public struct UserRequestInfo: Sendable {
	public init(
		docDataFormats: [String: DocDataFormat],
		itemsRequested: RequestItems,
		deviceRequestBytes: Data? = nil,
		transactionDataRequested: RequestTransactionData? = nil,
		verifierInfo: RequestVerifierInfo? = nil,
		requestName: String? = nil
	) {
		self.docDataFormats = docDataFormats
		self.itemsRequested = itemsRequested
		self.deviceRequestBytes = deviceRequestBytes
		self.transactionDataRequested = transactionDataRequested
		self.verifierInfo = verifierInfo
		self.requestName = requestName
	}
	/// device request bytes (encoded cbor)
	public var deviceRequestBytes: Data?
	/// docType to format map
	public var docDataFormats: [String: DocDataFormat]
	/// items requested
	public var itemsRequested: RequestItems
	/// reader Authentication results (per doc type)
	public var readerAuthResults: [DocType: ReaderAuthenticationResult] = [:]
	/// transaction data requested
	public var transactionDataRequested: RequestTransactionData?
	/// verifier info for items requested (format and data)
	public var verifierInfo: RequestVerifierInfo?
	/// optional request name
	public var requestName: String?

	/// Reader identity shared by the request. A single result (including the request-wide
	/// OpenID result stored under an empty key) is returned unchanged. Multiple document
	/// results must all authenticate with the same leaf certificate to share an identity.
	public var defaultReaderAuthResult: ReaderAuthenticationResult? {
		guard let firstKey = readerAuthResults.keys.sorted().first,
			let result = readerAuthResults[firstKey] else { return nil }
		if readerAuthResults.count == 1 { return result }
		guard result.isValidated,
			let leaf = result.certificateChain?.first, !leaf.isEmpty,
			readerAuthResults.values.allSatisfy({ $0.isValidated && $0.certificateChain?.first == leaf })
		else { return nil }
		return result
	}

}
