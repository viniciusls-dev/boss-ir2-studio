import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: PresetStore
    @EnvironmentObject private var pedal: PedalStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("studioAppearance") private var appearance = StudioAppearance.system.rawValue
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    @State private var showExporter = false
    @State private var exportDocument = JSONDocument(data: Data())
    @State private var showBackupImporter = false
    @State private var showBackup = false
    @State private var loadedBackup: LoadedBackup?
    @State private var showImportError = false
    @State private var importError = ""
    @State private var showExportError = false
    @State private var exportError = ""
    @State private var showDeleteConfirmation = false
    @State private var showingPedal = true
    @State private var showPresetImporter = false

    private var palette: StudioPalette { StudioPalette(scheme: scheme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            Rectangle().fill(palette.border).frame(width: 1)
            VStack(spacing: 0) {
                if showingPedal {
                    LivePedalView {
                        if let snapshot = pedal.snapshot {
                            store.capture(snapshot)
                            showingPedal = false
                        }
                    }
                } else if let index = store.selectedIndex {
                    editor(for: index)
                } else {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .font(.custom("AvenirNext-Regular", size: 13))
        .tint(palette.accent)
        .task { pedal.connect() }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.data], onCompletion: readBackup)
        .fileImporter(isPresented: $showPresetImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                try store.importPreset(data: Data(contentsOf: url))
                showingPedal = false
            } catch { importError = error.localizedDescription; showImportError = true }
        }
        .sheet(isPresented: $showBackup) {
            if let loadedBackup { BackupView(backup: loadedBackup) }
        }
        .alert(L10n.tr("Não foi possível abrir o arquivo"), isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: { Text(importError) }
        .alert(L10n.tr("Não foi possível concluir a operação"), isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: { Text(exportError) }
        .confirmationDialog(L10n.tr("Excluir este preset local?"), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(L10n.tr("Excluir preset"), role: .destructive, action: store.deleteSelected)
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument,
                      contentType: .json, defaultFilename: "ir2-preset") { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
                showExportError = true
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path").font(.system(size: 27, weight: .medium)).foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("IR-2 Studio").font(.custom("AvenirNext-DemiBold", size: 21))
                    Text(L10n.tr("SEU SOM, EM FOCO")).font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(2).foregroundStyle(palette.secondary)
                }
            }
            .padding(.top, 44).padding(.bottom, 30)
            Button { showingPedal = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cable.connector").foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("Meu IR-2")).font(.custom("AvenirNext-DemiBold", size: 13))
                        Text(pedal.connected ? L10n.tr("Conectado por USB") : L10n.tr("Conexão USB"))
                            .font(.custom("AvenirNext-Regular", size: 10)).foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Circle().fill(pedal.connected && !pedal.stale ? palette.green : palette.secondary).frame(width: 6, height: 6)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(showingPedal ? palette.accent.opacity(0.12) : palette.raised.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(showingPedal ? palette.accent.opacity(0.23) : .clear))
            }
            .buttonStyle(.plain).padding(.bottom, 24)
            .accessibilityAddTraits(showingPedal ? .isSelected : [])
            HStack {
                StudioCaption(title: L10n.tr("PRESETS LOCAIS"))
                Spacer()
                Text(String(format: "%02d", store.presets.count)).monospacedDigit()
            }
            .foregroundStyle(palette.secondary).padding(.bottom, 14)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                        presetRow(preset, number: index + 1)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            Button { store.addPreset(); showingPedal = false } label: {
                Label(L10n.tr("Novo preset"), systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StudioButtonStyle()).padding(.top, 12)
            Button { showPresetImporter = true } label: {
                Label(L10n.tr("Importar preset JSON…"), systemImage: "square.and.arrow.down")
                    .font(.custom("AvenirNext-Regular", size: 11)).foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            }.buttonStyle(.plain)
            Rectangle().fill(palette.border).frame(height: 1).padding(.vertical, 22)
            StudioCaption(title: L10n.tr("BACKUP DO PEDAL")).foregroundStyle(palette.secondary).padding(.bottom, 12)
            Button { showBackupImporter = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "square.and.arrow.down").foregroundStyle(palette.accent)
                    Text(L10n.tr("Abrir backup .alb…"))
                    Spacer()
                }
            }
            .buttonStyle(StudioButtonStyle())
            if let loadedBackup {
                Button { showBackup = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                        Text(loadedBackup.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 9))
                    }
                    .font(.custom("AvenirNext-Regular", size: 11)).foregroundStyle(palette.secondary)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain).help(L10n.format("Ver backup: %@", loadedBackup.name))
            }
            Rectangle().fill(palette.border).frame(height: 1).padding(.vertical, 22)
            StudioCaption(title: L10n.tr("APARÊNCIA")).foregroundStyle(palette.secondary).padding(.bottom, 12)
            Picker(L10n.tr("Aparência"), selection: $appearance) {
                ForEach(StudioAppearance.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.bottom, 12)
            Picker(L10n.tr("Idioma"), selection: $language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: language) { _, value in
                (AppLanguage(rawValue: value) ?? .system).save()
            }
            if language != L10n.launchPreference.rawValue {
                Text(L10n.tr("Reabra o app para aplicar o idioma."))
                    .font(.custom("AvenirNext-Regular", size: 10))
                    .foregroundStyle(palette.secondary)
            }
            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 20)
        .background(palette.sidebar)
    }

    private func presetRow(_ preset: Preset, number: Int) -> some View {
        let selected = !showingPedal && store.selectedID == preset.id
        return Button {
            store.selectedID = preset.id
            showingPedal = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "waveform" : "slider.horizontal.3")
                    .foregroundStyle(selected ? palette.accent : palette.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name).font(.custom("AvenirNext-DemiBold", size: 12)).lineLimit(2)
                    Text("\(preset.channelA.amp.rawValue) / \(preset.channelB.amp.rawValue)")
                        .font(.system(size: 8, design: .monospaced)).tracking(0.4).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                Text(String(format: "%02d", number)).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(selected ? palette.accent : palette.secondary)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(selected ? palette.accent.opacity(0.12) : palette.raised.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? palette.accent.opacity(0.23) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).help(preset.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func editor(for index: Int) -> some View {
        let preset = $store.presets[index]
        let settings = store.selectedChannel == 0 ? preset.channelA : preset.channelB
        VStack(spacing: 0) {
            HStack {
                Label(L10n.tr("Biblioteca de timbres"), systemImage: "square.stack.3d.up")
                    .font(.custom("AvenirNext-Medium", size: 12)).foregroundStyle(palette.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(palette.secondary).frame(width: 6, height: 6)
                    Text(L10n.tr("Editor local")).font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(palette.secondary).padding(.horizontal, 10).padding(.vertical, 7)
                .background(palette.raised, in: Capsule())
            }
            .padding(.horizontal, 30).padding(.top, 40).padding(.bottom, 20)
            Rectangle().fill(palette.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            StudioCaption(title: L10n.tr("SEU PRÓXIMO TIMBRE")).foregroundStyle(palette.accent)
                            TextField(L10n.tr("Nome do preset"), text: preset.name)
                                .font(.custom("AvenirNext-DemiBold", size: 29)).textFieldStyle(.plain)
                                .accessibilityLabel(L10n.tr("Nome do preset"))
                        }
                        Spacer(minLength: 0)
                        Button(action: exportPreset) {
                            Label(L10n.tr("Exportar"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(StudioButtonStyle())
                        Button {
                            do { try pedal.apply(store.presets[index]) }
                            catch { exportError = error.localizedDescription; showExportError = true }
                        } label: {
                            Image(systemName: "arrow.up.forward.app").frame(width: 14, height: 14)
                        }
                        .buttonStyle(StudioButtonStyle(prominent: true))
                        .disabled(!pedal.canEdit || pedal.busy || !pedal.pending.isEmpty)
                        .help(L10n.tr("Aplicar os dois canais deste preset ao pedal"))
                        .accessibilityLabel(L10n.tr("Aplicar preset ao pedal"))
                        Menu {
                            Button(L10n.tr("Excluir preset…"), role: .destructive) { showDeleteConfirmation = true }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 18, height: 20)
                        }
                        .menuStyle(.borderlessButton).fixedSize().help(L10n.tr("Opções do preset"))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        StudioCaption(title: L10n.tr("CANAIS")).foregroundStyle(palette.secondary)
                        HStack(spacing: 12) {
                            channelCard(0, name: L10n.tr("Verde"), amp: preset.wrappedValue.channelA.amp.rawValue, color: palette.green)
                            channelCard(1, name: L10n.tr("Vermelho"), amp: preset.wrappedValue.channelB.amp.rawValue, color: palette.red)
                        }
                    }
                    amplifierPanel(settings: settings)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            StudioCaption(title: L10n.tr("CONTROLES")).foregroundStyle(palette.secondary)
                            Spacer()
                            Text(L10n.format("Preset local · 0–%@", String(Int(settings.wrappedValue.maximum)))).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
                        }
                        HStack(alignment: .top, spacing: 16) {
                            StudioKnob(title: "Gain", value: settings.gain, maximum: settings.wrappedValue.maximum)
                            StudioKnob(title: "Bass", value: settings.bass, maximum: settings.wrappedValue.maximum)
                            StudioKnob(title: "Middle", value: settings.middle, maximum: settings.wrappedValue.maximum)
                            StudioKnob(title: "Treble", value: settings.treble, maximum: settings.wrappedValue.maximum)
                            StudioKnob(title: "Level", value: settings.level, maximum: settings.wrappedValue.maximum)
                            StudioKnob(title: "Ambience", value: settings.ambience, maximum: settings.wrappedValue.maximum)
                        }
                        .padding(22).background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border.opacity(0.8)))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        StudioCaption(title: L10n.tr("NOTAS DO TIMBRE")).foregroundStyle(palette.secondary)
                        TextField(L10n.tr("Guitarra, captador, referência de música…"), text: preset.notes, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.plain).accessibilityLabel(L10n.tr("Notas do timbre"))
                            .padding(15).background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border.opacity(0.7)))
                    }
                }
                .padding(30)
            }
        }
    }

    private func channelCard(_ channel: Int, name: String, amp: String, color: Color) -> some View {
        let selected = store.selectedChannel == channel
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { store.selectedChannel = channel }
        } label: {
            HStack(spacing: 12) {
                Text(channel == 0 ? "A" : "B")
                    .font(.custom("AvenirNext-DemiBold", size: 16)).foregroundStyle(color)
                    .frame(width: 36, height: 36).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.custom("AvenirNext-DemiBold", size: 13))
                    Text(amp).font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? color : palette.border)
            }
            .padding(14).background(selected ? color.opacity(0.05) : palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? color.opacity(0.55) : palette.border))
        }
        .buttonStyle(.plain).accessibilityLabel(L10n.format("Canal %@", name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func amplifierPanel(settings: Binding<AmpSettings>) -> some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(palette.raised).frame(width: 66, height: 66)
                Image(systemName: "hifispeaker.fill").font(.system(size: 28, weight: .light)).foregroundStyle(palette.accent)
            }
            VStack(alignment: .leading, spacing: 7) {
                StudioCaption(title: L10n.tr("AMPLIFICADOR")).foregroundStyle(palette.secondary)
                Text(settings.wrappedValue.amp.rawValue)
                    .font(.custom("AvenirNext-DemiBold", size: 27)).tracking(1.5)
            }
            Spacer()
            Menu {
                Picker(L10n.tr("Amplificador"), selection: settings.amp) {
                    ForEach(AmpType.allCases) { amp in Text(amp.rawValue).tag(amp) }
                }
            } label: {
                HStack(spacing: 8) { Text(L10n.tr("Trocar modelo")); Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)) }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .font(.custom("AvenirNext-Medium", size: 12)).foregroundStyle(palette.secondary)
            .padding(12).background(palette.raised, in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(22).background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border.opacity(0.8)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive").foregroundStyle(palette.accent)
            Text(L10n.tr("Presets salvos neste Mac")).font(.custom("AvenirNext-Medium", size: 11))
            Spacer()
            Text(pedal.status).font(.custom("AvenirNext-Regular", size: 11)).foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 30).padding(.vertical, 13)
        .background(palette.panel).overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path").font(.system(size: 38)).foregroundStyle(palette.accent)
            Text(L10n.tr("Um novo som começa aqui.")).font(.custom("AvenirNext-DemiBold", size: 25))
            Text(L10n.tr("Crie um preset para explorar os dois canais.")).foregroundStyle(palette.secondary)
            Button(L10n.tr("Criar preset"), action: store.addPreset).buttonStyle(StudioButtonStyle(prominent: true))
        }
        .padding(30)
    }

    private func exportPreset() {
        guard let index = store.selectedIndex else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportDocument = JSONDocument(data: try encoder.encode(store.presets[index]))
            showExporter = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let snapshot = try IR2Backup(data: Data(contentsOf: url))
            loadedBackup = LoadedBackup(name: url.lastPathComponent, snapshot: snapshot)
            showBackup = true
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }
}

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
