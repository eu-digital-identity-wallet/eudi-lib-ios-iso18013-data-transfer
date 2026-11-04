import Foundation
import MdocDataModel18013
import os

/// UUIDs already exposed over BLE must not identify a later presentation.
struct BleAdvertisingState {
    enum Admission: Equatable { case start, resume, alreadyActive }
    enum Failure: Error, Equatable { case invalidEngagement, presentationStillActive, reusedUUID }
    private struct Identity: Equatable {
        let uuid: UUID
        let area: ObjectIdentifier
        let keyID: String
        let index: Int
    }
    // Shared across transport instances for this process. Callers must also create a
    // fresh DeviceEngagement after application restart, rather than restoring an old UUID.
    private static let advertisedUUIDs = OSAllocatedUnfairLock(initialState: Set<UUID>())
    private var active: Identity?

    mutating func admit(_ engagement: DeviceEngagement, isAdvertising: Bool = true) throws -> Admission {
        guard !engagement.isSessionTerminated, let key = engagement.privateKey,
              let uuidString = engagement.ble_uuid, let uuid = UUID(uuidString: uuidString) else {
            throw Failure.invalidEngagement
        }
        let identity = Identity(uuid: uuid, area: ObjectIdentifier(key.secureArea), keyID: key.privateKeyId, index: key.index)
        if let active {
            guard active == identity else { throw Failure.presentationStillActive }
            return isAdvertising ? .alreadyActive : .resume
        }
        let fresh = Self.advertisedUUIDs.withLock { $0.insert(uuid).inserted }
        guard fresh else { throw Failure.reusedUUID }
        active = identity
        return .start
    }

    mutating func retire() { active = nil }
}
