//
//  MdocOfflineHandler.swift

import Foundation
import Combine
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013

public protocol MdocOfflineDelegate: AnyObject {
	func didChangeStatus(_ newStatus: TransferStatus)
	func didFinishedWithError(_ error: Error)
	func didReceiveRequest(_ request: DeviceRequest, handleAccept: @escaping (Bool) -> Void)
}


