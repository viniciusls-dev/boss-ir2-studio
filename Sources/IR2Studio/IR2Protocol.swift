import Foundation

enum PedalChannel: Int, CaseIterable, Identifiable, Codable {
    case green, red
    var id: Int { rawValue }
    var title: String { self == .green ? "Verde" : "Vermelho" }
    var address: UInt32 { self == .green ? 0x21000000 : 0x22000000 }
}

enum PedalParameter: Int, CaseIterable, Identifiable {
    case bass, middle, treble, level, gain, ambience, amp
    var id: Int { rawValue }
    var maximum: Int { self == .amp ? 10 : 127 }
    var title: String {
        switch self {
        case .bass: "Bass"
        case .middle: "Middle"
        case .treble: "Treble"
        case .level: "Level"
        case .gain: "Gain"
        case .ambience: "Ambience"
        case .amp: "Amplificador"
        }
    }
}

struct PedalPatch: Equatable {
    private(set) var bytes: [UInt8]
    init(bytes: [UInt8]) throws {
        guard bytes.count == 7, PedalParameter.allCases.allSatisfy({ Int(bytes[$0.rawValue]) <= $0.maximum }) else {
            throw IR2ProtocolError.invalidPatch
        }
        self.bytes = bytes
    }
    func value(_ parameter: PedalParameter) -> Int { Int(bytes[parameter.rawValue]) }
    mutating func set(_ parameter: PedalParameter, to value: Int) throws {
        guard (0...parameter.maximum).contains(value) else { throw IR2ProtocolError.invalidValue }
        bytes[parameter.rawValue] = UInt8(value)
    }
}

struct PedalSnapshot: Equatable {
    struct Update {
        let address: UInt32
        let bytes: [UInt8]
    }
    var green: PedalPatch
    var red: PedalPatch
    var selectedChannel: PedalChannel
    func patch(_ channel: PedalChannel) -> PedalPatch { channel == .green ? green : red }
    mutating func set(_ channel: PedalChannel, parameter: PedalParameter, value: Int) throws {
        if channel == .green { try green.set(parameter, to: value) }
        else { try red.set(parameter, to: value) }
    }

    /// Resolve the final selection first: recall bursts may send the active block before selection.
    func applying(_ updates: [Update]) -> Self {
        var result = self
        for update in updates where update.address == 0 && update.bytes.count == 1 {
            if let channel = PedalChannel(rawValue: Int(update.bytes[0])) { result.selectedChannel = channel }
        }
        for update in updates {
            let channel: PedalChannel
            let base: UInt32
            switch update.address {
            case 0x20000000...0x20000006: base = 0x20000000; channel = result.selectedChannel
            case 0x21000000...0x21000006: base = 0x21000000; channel = .green
            case 0x22000000...0x22000006: base = 0x22000000; channel = .red
            default: continue
            }
            let offset = Int(update.address - base)
            guard !update.bytes.isEmpty, offset + update.bytes.count <= 7 else { continue }
            var patch = result.patch(channel)
            do {
                for (index, byte) in update.bytes.enumerated() {
                    guard let parameter = PedalParameter(rawValue: offset + index) else { throw IR2ProtocolError.invalidValue }
                    try patch.set(parameter, to: Int(byte))
                }
                if channel == .green { result.green = patch } else { result.red = patch }
            } catch { continue } // Reject malformed events without publishing a partially updated patch.
        }
        return result
    }
}

enum IR2ProtocolError: LocalizedError {
    case invalidValue, invalidPatch, disconnected, notFound, ambiguousDevice, timeout, busy, unexpectedResponse, channelChanged, midi(Int32)
    var errorDescription: String? {
        switch self {
        case .invalidValue: "Valor fora da faixa aceita pelo IR-2."
        case .invalidPatch: "O pedal retornou parâmetros inesperados."
        case .disconnected: "O IR-2 está desconectado."
        case .notFound: "IR-2 não encontrado. Confira o cabo USB e o driver BOSS."
        case .ambiguousDevice: "Mais de um IR-2 foi encontrado. Conecte apenas um pedal."
        case .timeout: "O IR-2 não respondeu a tempo. Confira a conexão e tente novamente."
        case .busy: "Outra operação está em andamento."
        case .unexpectedResponse: "O valor relido do pedal não corresponde à alteração enviada. Atualize a leitura antes de tentar novamente."
        case .channelChanged: "O canal mudou durante a operação. Atualize a leitura antes de continuar a edição."
        case .midi(let status): "Falha na comunicação MIDI (\(status))."
        }
    }
}

/// Only the small parameter blocks are exposed for writing. No IR, flash or reset commands.
/// Protocol facts corroborated by the installed BOSS Loader and a hardware capture; see docs/USB.md.
enum IR2SysEx {
    static let identityRequest: [UInt8] = [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]
    static let header: [UInt8] = [0xF0, 0x41, 0x10, 0x01, 0x05, 0x09]
    static var liveUpdates: [UInt8] { data(address: 0x7F000001, bytes: [1]) }

    enum Message: Equatable {
        case identity
        case data(address: UInt32, bytes: [UInt8])
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        UInt8((128 - bytes.reduce(0) { $0 + Int($1) } % 128) & 127)
    }

    static func addressBytes(_ address: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8((address >> $0) & 255) }
    }

    static func read(address: UInt32, count: Int) throws -> [UInt8] {
        // The app reads setup (1), active patch (7), or either stored channel (7).
        guard [UInt32(0), 0x20000000, 0x21000000, 0x22000000].contains(address),
              count == (address == 0 ? 1 : 7) else { throw IR2ProtocolError.invalidValue }
        return request(address: address, count: count)
    }

    static func readParameter(channel: PedalChannel, parameter: PedalParameter) -> [UInt8] {
        request(address: channel.address + UInt32(parameter.rawValue), count: 1)
    }

    private static func request(address: UInt32, count: Int) -> [UInt8] {
        let payload = addressBytes(address) + [0, 0, 0, UInt8(count)]
        return header + [0x11] + payload + [checksum(payload), 0xF7]
    }

    static func write(channel: PedalChannel, parameter: PedalParameter, value: Int) throws -> [UInt8] {
        guard (0...parameter.maximum).contains(value) else { throw IR2ProtocolError.invalidValue }
        return data(address: channel.address + UInt32(parameter.rawValue), bytes: [UInt8(value)])
    }

    static func select(_ channel: PedalChannel) -> [UInt8] {
        data(address: 0, bytes: [UInt8(channel.rawValue)])
    }

    static func recall(_ channel: PedalChannel) -> [UInt8] {
        data(address: 0x7F000100, bytes: [0, UInt8(channel.rawValue)])
    }

    static func writeActive(parameter: PedalParameter, value: Int) throws -> [UInt8] {
        guard (0...parameter.maximum).contains(value) else { throw IR2ProtocolError.invalidValue }
        return data(address: 0x20000000 + UInt32(parameter.rawValue), bytes: [UInt8(value)])
    }

    static func readActiveParameter(_ parameter: PedalParameter) -> [UInt8] {
        request(address: 0x20000000 + UInt32(parameter.rawValue), count: 1)
    }

    // Internal encoder is also used to create recorded responses in the protocol tests.
    static func data(address: UInt32, bytes: [UInt8]) -> [UInt8] {
        let payload = addressBytes(address) + bytes
        return header + [0x12] + payload + [checksum(payload), 0xF7]
    }

    static func parse(_ bytes: [UInt8]) -> Message? {
        if bytes.count >= 15, Array(bytes.prefix(10)) == [0xF0,0x7E,0x10,0x06,0x02,0x41,0x09,0x05,0,0],
           bytes.last == 0xF7, bytes.dropFirst().dropLast().allSatisfy({ $0 < 128 }) { return .identity }
        guard bytes.count >= 14, Array(bytes.prefix(6)) == header, bytes[6] == 0x12, bytes.last == 0xF7,
              bytes.dropFirst().dropLast().allSatisfy({ $0 < 128 }),
              bytes[7..<bytes.count-1].reduce(0, { $0 + Int($1) }) % 128 == 0 else { return nil }
        let address = bytes[7..<11].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return .data(address: address, bytes: Array(bytes[11..<bytes.count-2]))
    }
}

/// Reassembles SysEx across Core MIDI packets; real-time bytes may interrupt SysEx.
struct SysExStream {
    private var buffer: [UInt8] = []
    mutating func append(_ bytes: [UInt8]) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte == 0xF0 { buffer = [byte]; continue }
            guard !buffer.isEmpty else { continue }
            if byte == 0xF7 {
                buffer.append(byte); messages.append(buffer); buffer.removeAll(keepingCapacity: true)
            } else if byte >= 0x80 || buffer.count >= 1024 {
                buffer.removeAll(keepingCapacity: true)
            } else { buffer.append(byte) }
        }
        return messages
    }
}
