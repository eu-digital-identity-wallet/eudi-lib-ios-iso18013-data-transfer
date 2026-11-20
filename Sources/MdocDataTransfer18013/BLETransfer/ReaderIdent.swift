import CryptoKit
import Foundation
import SwiftCBOR

/// ISO 18013-5 BLE Ident binds a candidate to the advertised engagement.
/// It is not reader authentication: the derivation input is public engagement data.
enum ReaderIdent {
    static func expected(engagement: [UInt8]?) -> Data? {
        // Use the actual QR engagement rather than re-encoding the public COSE key.
        guard let engagement,
              let cbor = try? CBOR.decode(engagement),
              case let .map(fields) = cbor,
              case let .array(security)? = fields[1], security.count == 2,
              case .unsignedInt(1) = security[0],
              case let .tagged(tag, .byteString(keyBytes)) = security[1],
              tag == CBOR.Tag(rawValue: 24), !keyBytes.isEmpty else { return nil }
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(security[1].encode())),
            salt: Data(), info: Data("BLEIdent".utf8), outputByteCount: 16)
        return key.withUnsafeBytes { Data($0) }
    }

    static func matches(_ received: Data?, engagement: [UInt8]?) -> Bool {
        guard let received, received.count == 16, let expected = expected(engagement: engagement) else { return false }
        return received == expected
    }
}
