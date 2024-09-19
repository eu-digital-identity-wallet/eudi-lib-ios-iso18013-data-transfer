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

public struct UserRequestInfo : Sendable {
	public init(validItemsRequested: RequestItems, errorItemsRequested: RequestItems? = nil, readerAuthValidated: Bool? = nil, readerCertificateIssuer: String? = nil, readerCertificateValidationMessage: String? = nil, readerLegalName: String? = nil) {
		self.validItemsRequested = validItemsRequested
		self.errorItemsRequested = errorItemsRequested
		self.readerAuthValidated = readerAuthValidated
		self.readerCertificateIssuer = readerCertificateIssuer
		self.readerCertificateValidationMessage = readerCertificateValidationMessage
		self.readerLegalName = readerLegalName
	}
	
	public var validItemsRequested: RequestItems
	public var errorItemsRequested: RequestItems?
	public var readerAuthValidated: Bool?
	public var readerCertificateIssuer: String?
	public var readerCertificateValidationMessage: String?
	public var readerLegalName: String?
}
