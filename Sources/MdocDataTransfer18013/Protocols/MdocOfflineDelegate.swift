//
//  MdocOfflineHandler.swift

import Foundation
import Combine
import SwiftCBOR
import MdocDataModel18013
import MdocSecurity18013

public typealias UserAcceptHandler = (Bool) -> Void

public protocol MdocOfflineDelegate: AnyObject {
	func didChangeStatus(_ newStatus: TransferStatus)
	func didReceiveRequest(_ request: DeviceRequest, handleAccept: UserAcceptHandler)
}


