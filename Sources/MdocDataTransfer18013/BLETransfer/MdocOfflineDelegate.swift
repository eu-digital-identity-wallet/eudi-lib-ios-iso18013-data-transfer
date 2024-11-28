//
//  MdocOfflineHandler.swift

import Foundation
import MdocDataModel18013
import MdocSecurity18013

/// delegate protocol for clients of the mdoc offline transfer manager
public protocol MdocOfflineDelegate: AnyObject {
	func didChangeStatus(_ newStatus: TransferStatus)
	func didFinishedWithError(_ error: Error)
	func didReceiveRequest(_ request: UserRequestInfo, handleSelected: @escaping (Bool, RequestItems?) async -> Void)
}


