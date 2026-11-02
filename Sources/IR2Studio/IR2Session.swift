import Foundation

/// One request at a time, checked identity/checksum/address, and bounded timeouts.
@MainActor
final class IR2Session {
    var onParameterUpdate: ((PedalSnapshot.Update) -> Void)?
    var onDisconnect: (() -> Void)?
    private let transport: IR2Transport
    private let timeout: Duration
    private var stream = SysExStream()
    private var pending: Pending?
    private var deadline: Task<Void, Never>?
    private(set) var connected = false

    private struct Pending {
        let id: UUID
        let address: UInt32? // nil = identity
        var values: [UInt8?]
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    init(transport: IR2Transport, timeout: Duration = .seconds(2)) {
        self.transport = transport
        self.timeout = timeout
        transport.onBytes = { [weak self] in self?.receive($0) }
        transport.onDisconnect = { [weak self] in
            self?.disconnect()
            self?.onDisconnect?()
        }
    }

    func connect() async throws -> String {
        disconnect()
        let name = try transport.open()
        do {
            _ = try await request(IR2SysEx.identityRequest, address: nil, count: 0)
            // Volatile editor communication mode used by the official Loader to enable reports.
            try transport.send(IR2SysEx.liveUpdates)
            connected = true
            return name
        } catch { disconnect(); throw error }
    }

    func disconnect() {
        connected = false
        finish(.failure(IR2ProtocolError.disconnected))
        transport.close()
        stream = SysExStream()
    }

    func snapshot() async throws -> PedalSnapshot {
        guard connected else { throw IR2ProtocolError.disconnected }
        for _ in 0..<2 {
            let before = try await read(address: 0, count: 1)
            let green = try await read(address: PedalChannel.green.address, count: 7)
            let red = try await read(address: PedalChannel.red.address, count: 7)
            let active = try await activePatch()
            let after = try await read(address: 0, count: 1)
            guard before == after else { continue }
            guard let channel = PedalChannel(rawValue: Int(after[0])) else { throw IR2ProtocolError.invalidPatch }
            return try PedalSnapshot(green: channel == .green ? active : PedalPatch(bytes: green),
                                     red: channel == .red ? active : PedalPatch(bytes: red), selectedChannel: channel)
        }
        throw IR2ProtocolError.channelChanged
    }

    func activePatch() async throws -> PedalPatch {
        guard connected else { throw IR2ProtocolError.disconnected }
        return try await PedalPatch(bytes: read(address: 0x20000000, count: 7))
    }

    func write(channel: PedalChannel, parameter: PedalParameter, value: Int) async throws {
        try Task.checkCancellation()
        guard connected else { throw IR2ProtocolError.disconnected }
        guard pending == nil else { throw IR2ProtocolError.busy }
        try transport.send(IR2SysEx.write(channel: channel, parameter: parameter, value: value))
        let actual = try await request(IR2SysEx.readParameter(channel: channel, parameter: parameter),
                                       address: channel.address + UInt32(parameter.rawValue), count: 1)
        guard actual == [UInt8(value)] else { throw IR2ProtocolError.unexpectedResponse }
        // Stored-channel writes do not update the sounding block on this device.
        let selection = try await read(address: 0, count: 1)
        if selection == [UInt8(channel.rawValue)] {
            try Task.checkCancellation()
            try transport.send(IR2SysEx.writeActive(parameter: parameter, value: value))
            let sounding = try await request(IR2SysEx.readActiveParameter(parameter),
                                              address: 0x20000000 + UInt32(parameter.rawValue), count: 1)
            guard sounding == [UInt8(value)] else { throw IR2ProtocolError.unexpectedResponse }
            guard try await read(address: 0, count: 1) == selection else { throw IR2ProtocolError.channelChanged }
        }
    }

    func select(_ channel: PedalChannel) async throws {
        try Task.checkCancellation()
        guard connected else { throw IR2ProtocolError.disconnected }
        guard pending == nil else { throw IR2ProtocolError.busy }
        let stored = try await read(address: channel.address, count: 7)
        try Task.checkCancellation()
        try transport.send(IR2SysEx.select(channel))
        try transport.send(IR2SysEx.recall(channel))
        try await Task.sleep(for: .milliseconds(120))
        let actual = try await read(address: 0, count: 1)
        guard actual == [UInt8(channel.rawValue)] else { throw IR2ProtocolError.unexpectedResponse }
        guard try await activePatch().bytes == stored else { throw IR2ProtocolError.unexpectedResponse }
    }

    private func read(address: UInt32, count: Int) async throws -> [UInt8] {
        try await request(IR2SysEx.read(address: address, count: count), address: address, count: count)
    }

    private func request(_ bytes: [UInt8], address: UInt32?, count: Int) async throws -> [UInt8] {
        try Task.checkCancellation()
        guard pending == nil else { throw IR2ProtocolError.busy }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                pending = Pending(id: id, address: address, values: Array(repeating: nil, count: count), continuation: continuation)
                deadline = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard self?.pending?.id == id else { return }
                    self?.finish(.failure(IR2ProtocolError.timeout))
                }
                do { try transport.send(bytes) }
                catch { finish(.failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.pending?.id == id else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func receive(_ bytes: [UInt8]) {
        for frame in stream.append(bytes) {
            guard let message = IR2SysEx.parse(frame) else { continue }
            switch message {
            case .identity:
                if let pending, pending.address == nil { finish(.success([])) }
            case .data(let address, let bytes):
                if connected { onParameterUpdate?(PedalSnapshot.Update(address: address, bytes: bytes)) }
                guard var pending, let expected = pending.address else {
                    continue
                }
                var matched = false
                for (offset, byte) in bytes.enumerated() {
                    let position = Int64(address) + Int64(offset) - Int64(expected)
                    if position >= 0, position < pending.values.count {
                        pending.values[Int(position)] = byte
                        matched = true
                    }
                }
                if matched {
                    self.pending = pending
                    if pending.values.allSatisfy({ $0 != nil }) { finish(.success(pending.values.compactMap { $0 })) }
                }
            }
        }
    }

    private func finish(_ result: Result<[UInt8], Error>) {
        guard let pending else { return }
        self.pending = nil
        deadline?.cancel(); deadline = nil
        pending.continuation.resume(with: result)
    }
}
