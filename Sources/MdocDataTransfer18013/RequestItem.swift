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
	public init(elementPath: [String], displayNames: [String?], intentToRetain: Bool? = nil, isOptional: Bool? = nil) {
		self.elementPath = elementPath
		self.displayNames = displayNames
		self.intentToRetain = intentToRetain
		self.isOptional = isOptional
	}

	/// A unique identifier for the data element.
	/// This element path is used to distinguish between different elements within the data transfer process.
	public let elementPath: [String]

	/// A string representation of the element path
	public var elementIdentifier: String {
		elementPath.joined(separator: ".")
	}
	/// display names of the component paths (currently only the root display name is not-nil)
	public let displayNames: [String?]

	/// Indicates whether the mdoc verifier intends to retain the received data element
	public let intentToRetain: Bool?
	/// Indicates whether the data element is optional.
	/// false or nil value of the property indicates the field is required
	public let isOptional: Bool?

	///implementation of Equatable and Hashable
	public static func == (lhs: RequestItem, rhs: RequestItem) -> Bool {
		return lhs.elementPath == rhs.elementPath
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(elementPath)
	}
}

extension RequestItem {
	public init(elementPath: [String]) {
		self.init(elementPath: elementPath, displayNames: Array(repeating: nil, count: elementPath.count), intentToRetain: nil, isOptional: nil)
	}

	public init(elementIdentifier: String) {
		let elementPath = elementIdentifier.components(separatedBy: ".")
		self.init(elementPath: elementPath, displayNames: Array(repeating: nil, count: elementPath.count), intentToRetain: nil, isOptional: nil)
	}

	public init(elementIdentifier: String, displayName: String?, intentToRetain: Bool? = nil, isOptional: Bool? = nil) {
		self.init(elementPath: elementIdentifier.components(separatedBy: "."), displayNames: [displayName], intentToRetain: intentToRetain, isOptional: isOptional)
	}

}
