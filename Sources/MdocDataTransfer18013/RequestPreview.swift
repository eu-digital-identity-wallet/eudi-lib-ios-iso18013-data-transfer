import Foundation
import MdocDataModel18013

extension MdocHelpers {
    struct RequestPreview {
        var validRequestItems = RequestItems()
        var errorRequestItems = RequestItems()
        var documentIds: [String] = []
        var responseMetadata: [Data?] = []
        var isValidRequest: Bool { !documentIds.isEmpty }
    }

    static func validateRequestedDocTypes(_ request: DeviceRequest) throws {
        var types = Set<DocType>()
        for document in request.docRequests {
            let type = document.itemsRequest.docType
            guard !type.isEmpty, types.insert(type).inserted else {
                throw makeError(code: .requestDecodeError)
            }
        }
    }

    /// Resolve availability for consent without keys, authentication, or a DeviceResponse.
    static func previewRequest(
        _ request: DeviceRequest,
        issuerSigned: [String: IssuerSigned],
        docMetadata: [String: Data]
    ) throws -> RequestPreview {
        try validateRequestedDocTypes(request)
        var result = RequestPreview()
        for document in request.docRequests {
            let type = document.itemsRequest.docType
            guard let (id, credential) = issuerSigned.first(where: { $0.value.issuerAuth.mso.docType == type }) else {
                result.errorRequestItems[type] = [:]
                continue
            }
            guard let namespaces = credential.issuerNameSpaces else {
                throw makeError(code: .requestDecodeError)
            }
            var available = [NameSpace: [RequestItem]]()
            var missing = [NameSpace: [RequestItem]]()
            for (namespace, requested) in document.itemsRequest.requestNameSpaces.nameSpaces {
                guard let items = namespaces[namespace] else {
                    missing[namespace] = requested.elementIdentifiers.map(RequestItem.init(elementIdentifier:))
                    continue
                }
                var identifiers = Set(requested.elementIdentifiers)
                identifiers.subtract(IsoMdlModel.moreThan2AgeOverElementIdentifiers(
                    type, namespace,
                    SimpleAgeAttest(namespaces: namespaces.nameSpaces, namespace: namespace),
                    Array(identifiers)))
                let matches = items.filter { identifiers.contains($0.elementIdentifier) }
                if !matches.isEmpty {
                    available[namespace] = matches.map {
                        RequestItem(elementIdentifier: $0.elementIdentifier,
                            intentToRetain: requested.dataElements[$0.elementIdentifier], isOptional: nil)
                    }
                }
                let absent = identifiers.subtracting(items.map(\.elementIdentifier))
                if !absent.isEmpty {
                    missing[namespace] = absent.map(RequestItem.init(elementIdentifier:))
                }
            }
            result.errorRequestItems[type] = missing
            if !available.isEmpty {
                result.validRequestItems[type] = available
                result.documentIds.append(id)
                result.responseMetadata.append(docMetadata[id])
            }
        }
        return result
    }
}
