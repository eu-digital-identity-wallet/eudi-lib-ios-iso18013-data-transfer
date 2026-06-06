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
		verifierInfo: RequestVerifierInfo? = nil
	) {
		self.docDataFormats = docDataFormats
		self.itemsRequested = itemsRequested
		self.deviceRequestBytes = deviceRequestBytes
		self.transactionDataRequested = transactionDataRequested
		self.verifierInfo = verifierInfo
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

	/// default reader authentication result (if docType specific result is not available)
	public var defaultReaderAuthResult: ReaderAuthenticationResult? {
		readerAuthResults[""] ?? readerAuthResults.first?.value
	}

}
