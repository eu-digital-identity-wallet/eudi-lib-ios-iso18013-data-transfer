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

/// A structure representing a request item for data transfer.
public struct RequestItem: Equatable, Hashable, Sendable {
		public init(elementIdentifier: String, displayName: String?, intentToRetain: Bool? = nil, isOptional: Bool? = nil) {
				self.elementIdentifier = elementIdentifier
				self.displayName = displayName
				self.intentToRetain = intentToRetain
				self.isOptional = isOptional
		}
	
		public init(elementIdentifier: String) {
				self.elementIdentifier = elementIdentifier
				self.displayName = nil
				self.intentToRetain = nil
				self.isOptional = nil
		}

		/// A unique identifier for the data element.
		/// This identifier is used to distinguish between different elements within the data transfer process.
		public let elementIdentifier: String
	  // display name
		public let displayName: String?
		/// Indicates whether the mdoc verifier intends to retain the received data element
		public let intentToRetain: Bool?
		/// Indicates whether the data element is optional.
		/// false or nil value of the property indicates the field is required
		public let isOptional: Bool?

		//implementation of Equatable and Hashable
		public static func == (lhs: RequestItem, rhs: RequestItem) -> Bool {
				return lhs.elementIdentifier == rhs.elementIdentifier
		}

		public func hash(into hasher: inout Hasher) {
				hasher.combine(elementIdentifier)
		}
}
