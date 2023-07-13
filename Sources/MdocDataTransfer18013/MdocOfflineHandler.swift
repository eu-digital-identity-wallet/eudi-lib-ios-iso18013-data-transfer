//
//  MdocOfflineHandler.swift

import Foundation
import Combine

public protocol MdocOfflineHandler {
	func setRequestData(_ data: Data) throws
	func getResponseData() throws -> Data
	var userAccepted: Future<Bool,Error> { get }
}
