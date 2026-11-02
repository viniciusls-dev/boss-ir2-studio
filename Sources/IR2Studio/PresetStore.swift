import Foundation

@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [Preset] = [] {
        didSet { save() }
    }
    @Published var selectedID: UUID?
    @Published var selectedChannel: Int = 0

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IR2Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("presets.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = loaded
        } else {
            presets = [Preset(name: "Clean / Modern Rock")]
        }
        selectedID = presets.first?.id
    }

    var selectedIndex: Int? { presets.firstIndex { $0.id == selectedID } }

    func addPreset() {
        let preset = Preset(name: "Novo preset")
        presets.append(preset)
        selectedID = preset.id
    }

    func capture(_ snapshot: PedalSnapshot) {
        var preset = Preset(name: "Timbre do IR-2")
        preset.channelA = AmpSettings(patch: snapshot.green)
        preset.channelB = AmpSettings(patch: snapshot.red)
        presets.append(preset)
        selectedID = preset.id
        selectedChannel = snapshot.selectedChannel.rawValue
    }

    func importPreset(data: Data) throws {
        var preset = try JSONDecoder().decode(Preset.self, from: data)
        _ = try preset.channelA.pedalPatch()
        _ = try preset.channelB.pedalPatch()
        preset.id = UUID()
        presets.append(preset)
        selectedID = preset.id
    }

    func deleteSelected() {
        guard let index = selectedIndex else { return }
        presets.remove(at: index)
        selectedID = presets.first?.id
    }

    func exportSelected(to url: URL) throws {
        guard let index = selectedIndex else { return }
        let data = try JSONEncoder.pretty.encode(presets[index])
        try data.write(to: url, options: .atomic)
    }

    private func save() {
        guard let data = try? JSONEncoder.pretty.encode(presets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
