/*
Copyright (c) 2026 European Commission

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
import Foundation

/// Transport ownership is independent of encrypted payload authentication.
/// Accessed on the peripheral manager's serial callback queue.
struct GattSession {
    enum Characteristic: Hashable { case state, serverToClient, clientToServer }
    enum WriteResult: Equatable { case started, ended, fragment, request(Data) }
    enum Rejection: Error, Equatable { case unauthorized, invalidState, invalidValue }

    private(set) var generation = UUID()
    private(set) var centralID: UUID?
    private(set) var subscriptions: Set<Characteristic> = []
    private(set) var readBuffer = Data()

    var ready: Bool { subscriptions == [.state, .serverToClient] }

    mutating func subscribe(_ characteristic: Characteristic, central: UUID, status: TransferStatus) -> Bool {
        guard status == .qrEngagementReady,
              characteristic == .state || characteristic == .serverToClient,
              centralID == nil || centralID == central else { return false }
        centralID = central
        subscriptions.insert(characteristic)
        return true
    }

    func acceptsUnsubscribe(_ characteristic: Characteristic, central: UUID) -> Bool {
        centralID == central && subscriptions.contains(characteristic)
    }

    mutating func write(_ value: Data, characteristic: Characteristic, central: UUID, status: TransferStatus) throws -> WriteResult {
        guard centralID == central, ready else { throw Rejection.unauthorized }
        switch characteristic {
        case .state:
            guard value.count == 1, let byte = value.first, byte == 1 || byte == 2 else { throw Rejection.invalidValue }
            if byte == 1 {
                guard status == .connected else { throw Rejection.invalidState }
                readBuffer.removeAll()
                return .started
            }
            guard [.connected, .started, .requestReceived, .userSelected, .responseSent].contains(status) else { throw Rejection.invalidState }
            return .ended
        case .clientToServer:
            guard status == .started else { throw Rejection.invalidState }
            guard let byte = value.first, byte == 0 || byte == 1 else { throw Rejection.invalidValue }
            readBuffer.append(value.dropFirst())
            if byte == 0 {
                let request = readBuffer
                readBuffer.removeAll()
                return .request(request)
            }
            return .fragment
        case .serverToClient:
            throw Rejection.invalidValue
        }
    }

    mutating func reset() { self = Self() }
}
