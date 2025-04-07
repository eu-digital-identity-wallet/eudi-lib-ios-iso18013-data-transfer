/*
Copyright (c) 2023 European Commission

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

public struct UserRequestInfo : Sendable {
	public init(docDataFormats: [String: DocDataFormat], itemsRequested: RequestItems, docMetadata: [String: Data], deviceRequestBytes: Data? = nil, readerAuthBytes: Data? = nil, certificateChain: [Data]? = nil, readerAuthValidated: Bool? = nil, readerCertificateIssuer: String? = nil, readerCertificateValidationMessage: String? = nil, readerLegalName: String? = nil) {
		self.docDataFormats = docDataFormats
		self.itemsRequested = itemsRequested
		self.docMetadata = docMetadata
		self.readerAuthValidated = readerAuthValidated
		self.readerCertificateIssuer = readerCertificateIssuer
		self.readerCertificateValidationMessage = readerCertificateValidationMessage
		self.readerLegalName = readerLegalName
		self.deviceRequestBytes = deviceRequestBytes
        self.readerAuthBytes = readerAuthBytes
		self.certificateChain = certificateChain
	}
	/// docType to format map
	public var docDataFormats: [String: DocDataFormat]
	/// items requested
	public var itemsRequested: RequestItems
	/// requested doc-ids to metadata map
	public var docMetadata: [String: Data]
	/// reader authentication from verifer validated
	public var readerAuthValidated: Bool?
	/// reader certificate issuer (issuer common name)
	public var readerCertificateIssuer: String?
	/// reader certificate validation message
	public var readerCertificateValidationMessage: String?
	/// reader legal name
	public var readerLegalName: String?
	/// device request bytes (encoded cbor)
	public var deviceRequestBytes: Data?
	/// reader authentication bytes (encoded cbor)
	public var readerAuthBytes: Data?
 	/// certificate chain (base64 pem encoded)
	public var certificateChain: [Data]?
}
