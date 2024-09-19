//
//  UserRequestData.swift
//
//  Created by ffeli on 20/09/2024.
//  Copyright © 2024 EUDIW. All rights reserved.
//


public struct UserRequestInfo : Sendable {
	public var validItemsRequested: RequestItems
	public var errorItemsRequested: RequestItems?
	public var readerAuthValidated: Bool?
	public var readerCertificateIssuer: String?
	public var readerCertificateValidationMessage: String?
	public var readerLegalName: String?
}
