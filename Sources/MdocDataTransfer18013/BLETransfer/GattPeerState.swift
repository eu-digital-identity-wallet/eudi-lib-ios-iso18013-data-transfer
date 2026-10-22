import Foundation

/// Authorization and framing state shared by the GATT callbacks. A batch commits atomically.
struct GattPeerState {
    enum Channel: Hashable { case state, response }
    enum Write { case state(Data), data(Data) }
    enum Event { case started, request(Data), ended }
    enum Failure: Error { case unauthorized, invalidWrite }
    private(set) var centralID: UUID?
    private var channels: Set<Channel> = []
    private var started = false
    private var completed = false
    private var buffer = Data()
    private(set) var generation = UUID()

    var ready: Bool { channels == [.state, .response] }

    mutating func subscribe(_ central: UUID, to channel: Channel) -> Bool {
        guard centralID == nil || centralID == central else { return false }
        centralID = central
        channels.insert(channel)
        return true
    }

    func accepts(_ central: UUID) -> Bool { ready && centralID == central }

    mutating func reset() { self = Self() }

    mutating func receive(_ writes: [Write], from central: UUID) throws -> Event? {
        guard accepts(central) else { throw Failure.unauthorized }
        var candidate = self
        var event: Event?
        for write in writes {
            // No further command may follow a complete request or END in one batch.
            if case .request = event { throw Failure.invalidWrite }
            if case .ended = event { throw Failure.invalidWrite }
            switch write {
            case .state(let value):
                guard value.count == 1 else { throw Failure.invalidWrite }
                switch value.first! {
                case 1:
                    guard !candidate.started && !candidate.completed else { throw Failure.invalidWrite }
                    candidate.started = true
                    candidate.buffer.removeAll()
                    event = .started
                case 2:
                    candidate.reset()
                    event = .ended
                default: throw Failure.invalidWrite
                }
            case .data(let value):
                guard candidate.started, !candidate.completed,
                      let marker = value.first, marker == 0 || marker == 1 else { throw Failure.invalidWrite }
                candidate.buffer.append(value.dropFirst())
                if marker == 0 {
                    event = .request(candidate.buffer)
                    candidate.buffer.removeAll()
                    candidate.completed = true
                }
            }
        }
        self = candidate
        return event
    }
}
