import Foundation

/// A read-only projection of the experimentally mapped fields, not a restore-file validator.
struct IR2Backup: Equatable {
    enum Channel: String {
        case green = "Verde"
        case red = "Vermelho"
    }

    let selectedChannel: Channel
    let greenParameters: [UInt8]
    let redParameters: [UInt8]

    var greenGain: UInt8 { greenParameters[4] }
    var redGain: UInt8 { redParameters[4] }

    init(data: Data) throws {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ReadError.invalidStructure
        }
        guard envelope.device == "IR-2" else { throw ReadError.unsupportedDevice }
        guard envelope.formatRev == "0000" else { throw ReadError.unsupportedRevision }
        guard let setup = envelope.system["SETUP%COM"], setup.count == 1,
              let channel = UInt8(setup[0], radix: 16), Self.isHexByte(setup[0]), channel <= 1 else {
            throw ReadError.invalidField("SETUP%COM")
        }
        guard envelope.userPatch.count == 2 else { throw ReadError.invalidField("userPatch") }
        let patches = try envelope.userPatch.map { patch -> [UInt8] in
            guard let values = patch["PATCH%COM"], values.count == 7,
                  values.allSatisfy(Self.isHexByte) else {
                throw ReadError.invalidField("PATCH%COM")
            }
            return try values.map { value in
                guard let byte = UInt8(value, radix: 16) else { throw ReadError.invalidField("PATCH%COM") }
                return byte
            }
        }
        selectedChannel = channel == 0 ? .green : .red
        greenParameters = patches[0]
        redParameters = patches[1]
    }

    private static func isHexByte(_ value: String) -> Bool {
        value.utf8.count == 2 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private struct Envelope: Decodable {
        let device: String
        let formatRev: String
        let system: [String: [String]]
        let userPatch: [[String: [String]]]
    }

    enum ReadError: LocalizedError, Equatable {
        case invalidStructure
        case unsupportedDevice
        case unsupportedRevision
        case invalidField(String)

        var errorDescription: String? {
            switch self {
            case .invalidStructure: "O arquivo não contém uma estrutura de backup IR-2 reconhecida."
            case .unsupportedDevice: "Este backup não pertence a um BOSS IR-2."
            case .unsupportedRevision: "A revisão deste backup ainda não é compatível com o leitor."
            case .invalidField(let field): "O campo \(field) está ausente ou contém valores inesperados."
            }
        }
    }
}
