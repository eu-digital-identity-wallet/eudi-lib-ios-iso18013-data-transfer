//
//  TransferDelegateObject.swift
//  Iso18013HolderDemo

import Foundation
import SwiftUI

public class DefaultTransferDelegate: ObservableObject, MdocOfflineDelegate {
	public init(readerCertIsserMessage: String? = nil, readerCertValidationMessage: String? = nil, hasError: Bool = false, errorMessage: String = "", selectedRequestItems: [DocElementsViewModel] = [], handleSelected: @escaping (Bool, RequestItems?) -> Void = { _,_ in }) {
		self.readerCertIsserMessage = readerCertIsserMessage
		self.readerCertValidationMessage = readerCertValidationMessage
		self.hasError = hasError
		self.errorMessage = errorMessage
		self.selectedRequestItems = selectedRequestItems
		self.handleSelected = handleSelected
	}
	
	
	@Published public var readerCertIsserMessage: String?
	@Published public var readerCertValidationMessage: String?
	@Published public var hasError: Bool = false
	@Published public var errorMessage: String = ""
	@Published public var selectedRequestItems: [DocElementsViewModel] = []
	public var handleSelected: (Bool, RequestItems?) -> Void = { _,_ in }
	
	public func didChangeStatus(_ newStatus: TransferStatus) {
	}
	
	public func didReceiveRequest(_ request: [String: Any], handleSelected: @escaping (Bool, RequestItems?) -> Void) {
		self.handleSelected = handleSelected
		// show the items as checkboxes
		guard let validRequestItems = request[UserRequestKeys.valid_items_requested.rawValue] as? RequestItems else { return }
		guard let errorRequestItems = request[UserRequestKeys.error_items_requested.rawValue] as? RequestItems else { return }
		selectedRequestItems = validRequestItems.toDocElementViewModels(valid: true).merging(with: errorRequestItems.toDocElementViewModels(valid: false))
		if let readerAuthority = request[UserRequestKeys.reader_certificate_issuer.rawValue] as? String {
			let bAuthenticated = request[UserRequestKeys.reader_auth_validated.rawValue] as? Bool ?? false
			readerCertIsserMessage = "Reader Certificate Issuer:\n\(readerAuthority)\n\(bAuthenticated ? "Authenticated" : "NOT authenticated")\n\(request[UserRequestKeys.reader_certificate_validation_message.rawValue] as? String ?? "")"
		}
	}

	public func didFinishedWithError(_ error: Error) {
		hasError = true
		errorMessage = error.localizedDescription
	}
	
	
}
