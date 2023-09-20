//
//  ElementViewModel.swift
//  Iso18013HolderDemo
//
//  Created by ffeli on 04/09/2023.
//  Copyright © 2023 EUDIW. All rights reserved.
//

import Foundation

public struct DocElementsViewModel: Identifiable {
	public var id: String { docType }
	public let docType: String
	public var isEnabled: Bool
	public var elements: [ElementViewModel]
}

func fluttenItemViewModels(_ nsItems: [String:[String]], valid isEnabled: Bool) -> [ElementViewModel] {
	nsItems.map { k,v in nsItemsToViewModels(k,v, isEnabled) }.flatMap {$0}
}

func nsItemsToViewModels(_ ns: String, _ items: [String], _ isEnabled: Bool) -> [ElementViewModel] {
	items.map { ElementViewModel(nameSpace: ns, elementIdentifier:$0, isEnabled: isEnabled) }
}

extension RequestItems {
	func toDocElementViewModels(valid: Bool) -> [DocElementsViewModel] {
		map { docType,nsItems in DocElementsViewModel(docType: docType, isEnabled: valid, elements: fluttenItemViewModels(nsItems, valid: valid)) }
	}
}

extension Array where Element == DocElementsViewModel {
	public var docSelectedDictionary: RequestItems { Dictionary(grouping: self, by: \.docType).mapValues { $0.first!.elements.filter(\.isSelected).nsDictionary } }

	func merging(with other: Self) -> Self {
		var res = Self()
		for otherDE in other {
			if let exist = first(where: { $0.docType == otherDE.docType})	{
				let newElements = (exist.elements + otherDE.elements).sorted(by: { $0.isEnabled && $1.isDisabled })
				res.append(DocElementsViewModel(docType: exist.docType, isEnabled: exist.isEnabled, elements: newElements))
			}
			else { res.append(otherDE) }
		}
		return res
	}
}

public struct ElementViewModel: Identifiable {
	public var id: String { "\(nameSpace)_\(elementIdentifier)" }
	public let nameSpace: String
	public let elementIdentifier: String
	public var isEnabled: Bool
	public var isDisabled: Bool { !isEnabled }
	public var isSelected = true
}

extension Array where Element == ElementViewModel {
	var nsDictionary: [String: [String]] { Dictionary(grouping: self, by: \.nameSpace).mapValues { $0.map(\.elementIdentifier)} }
}
