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

/// Encapsulates reader authentication validation results
public struct ReaderAuthenticationResult: Sendable {
	/// Whether reader auth was validated successfully
	/// - `true`: reader auth was present and validated successfully
	/// - `false`: reader auth was absent, certificate was malformed, or validation failed
	public let isValidated: Bool
	/// reader certificate issuer (issuer common name)
	public let certificateIssuer: String?
	/// reader certificate validation message
	public let  validationMessage: String?
	/// reader legal name
	public let legalName: String?
	/// reader authentication bytes (encoded cbor)
	public let authBytes: Data?
	/// certificate chain (base64 pem encoded)
	public let certificateChain: [Data]?

	public init(
		isValidated: Bool,
		certificateIssuer: String? = nil,
		validationMessage: String? = nil,
		legalName: String? = nil,
		authBytes: Data? = nil,
		certificateChain: [Data]? = nil
	) {
        self.isValidated = isValidated
        self.certificateIssuer = certificateIssuer
        self.validationMessage = validationMessage
        self.legalName = legalName
        self.authBytes = authBytes
        self.certificateChain = certificateChain
    }
}
