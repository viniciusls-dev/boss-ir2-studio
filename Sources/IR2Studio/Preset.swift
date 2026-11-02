import Foundation

enum AmpType: String, CaseIterable, Codable, Identifiable {
    case clean = "CLEAN", twin = "TWN", tweed = "TWEED", diamond = "DIAMOND", crunch = "CRUNCH"
    case brit = "BRIT", hiGain = "HI-GAIN", slDn = "SLDN", brown = "BROWN", modded = "MODDED", rfier = "RFIER"
    var id: String { rawValue }
    var pedalValue: Int { Self.allCases.firstIndex(of: self)! }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        // Migrate labels from the original offline prototype, which had no hardware mapping.
        if value == "ACOUSTIC" { self = .clean }
        else if value == "TWD" { self = .tweed }
        else if let amp = Self(rawValue: value) { self = amp }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Amplificador desconhecido") }
    }
}

struct AmpSettings: Codable, Equatable {
    enum Scale: String, Codable { case local100, pedal127 }
    var amp: AmpType = .clean
    var gain: Double = 30
    var bass: Double = 64
    var middle: Double = 64
    var treble: Double = 64
    var level: Double = 64
    var ambience: Double = 64
    var scale: Scale = .pedal127
    var maximum: Double { scale == .local100 ? 100 : 127 }

    init(amp: AmpType = .clean, gain: Double = 30) { self.amp = amp; self.gain = gain }
    init(patch: PedalPatch) {
        amp = AmpType.allCases[patch.value(.amp)]
        gain = Double(patch.value(.gain)); bass = Double(patch.value(.bass))
        middle = Double(patch.value(.middle)); treble = Double(patch.value(.treble))
        level = Double(patch.value(.level)); ambience = Double(patch.value(.ambience))
        scale = .pedal127
    }

    func pedalPatch() throws -> PedalPatch {
        let values = [bass, middle, treble, level, gain, ambience]
        guard values.allSatisfy({ $0.isFinite && (0...maximum).contains($0) }) else { throw IR2ProtocolError.invalidValue }
        return try PedalPatch(bytes: values.map { UInt8(($0 / maximum * 127).rounded()) } + [UInt8(amp.pedalValue)])
    }

    private enum CodingKeys: String, CodingKey { case amp, gain, bass, middle, treble, level, ambience, scale }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amp = try c.decode(AmpType.self, forKey: .amp)
        scale = try c.decodeIfPresent(Scale.self, forKey: .scale) ?? .local100
        gain = try c.decode(Double.self, forKey: .gain)
        bass = try c.decode(Double.self, forKey: .bass)
        middle = try c.decode(Double.self, forKey: .middle)
        treble = try c.decode(Double.self, forKey: .treble)
        level = try c.decode(Double.self, forKey: .level)
        ambience = try c.decodeIfPresent(Double.self, forKey: .ambience) ?? (scale == .local100 ? 50 : 64)
        _ = try pedalPatch()
    }
}

struct Preset: Identifiable, Codable {
    var id = UUID()
    var name: String
    var notes: String = ""
    var channelA = AmpSettings()
    var channelB = AmpSettings(amp: .brown, gain: 65)
}
