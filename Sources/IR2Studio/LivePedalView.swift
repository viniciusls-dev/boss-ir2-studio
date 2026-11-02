import SwiftUI

struct LivePedalView: View {
    let onCapture: () -> Void
    @EnvironmentObject private var pedal: PedalStore
    @Environment(\.colorScheme) private var scheme
    @State private var viewedChannel = PedalChannel.green
    private var palette: StudioPalette { StudioPalette(scheme: scheme) }
    private let controls: [PedalParameter] = [.gain, .bass, .middle, .treble, .level, .ambience]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L10n.tr("Meu IR-2"), systemImage: "cable.connector").foregroundStyle(palette.secondary)
                Spacer()
                if pedal.busy { ProgressView().controlSize(.small) }
                if pedal.connected {
                    Button(L10n.tr("Desconectar")) { pedal.disconnect() }.buttonStyle(StudioButtonStyle())
                } else {
                    Button(L10n.tr("Conectar")) { pedal.connect() }.buttonStyle(StudioButtonStyle(prominent: true)).disabled(pedal.busy)
                }
            }
            .padding(.horizontal, 30).padding(.top, 40).padding(.bottom, 20)
            Rectangle().fill(palette.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 7) {
                            StudioCaption(title: L10n.tr("DIRETO DO PEDAL")).foregroundStyle(palette.accent)
                            Text(L10n.tr("Seu som, ao vivo.")).font(.custom("AvenirNext-DemiBold", size: 29))
                            Text(pedal.status).foregroundStyle(palette.secondary)
                        }
                        Spacer()
                        Button(action: onCapture) {
                            Label(L10n.tr("Salvar como preset"), systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(StudioButtonStyle()).disabled(pedal.snapshot == nil || pedal.stale || pedal.busy || !pedal.pending.isEmpty)
                    }
                    if let error = pedal.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(palette.red).font(.custom("AvenirNext-Medium", size: 12))
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let snapshot = pedal.snapshot {
                        connectionPanel
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                StudioCaption(title: L10n.tr("CANAIS")).foregroundStyle(palette.secondary)
                                Spacer()
                                Text(L10n.tr("Selecione para inspecionar")).font(.custom("AvenirNext-Regular", size: 11)).foregroundStyle(palette.secondary)
                            }
                            HStack(spacing: 12) {
                                ForEach(PedalChannel.allCases) { channel in channelCard(channel, snapshot: snapshot) }
                            }
                        }
                        amplifierPanel
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                StudioCaption(title: L10n.format("CONTROLES · %@", viewedChannel.title.uppercased())).foregroundStyle(palette.secondary)
                                Spacer()
                                Text(L10n.tr("Pedal · 0–127")).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
                            }
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(controls) { parameter in
                                    StudioKnob(title: parameter.title, value: binding(parameter), maximum: 127)
                                }
                            }
                            .disabled(!pedal.canEdit)
                            .padding(22).background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border.opacity(0.8)))
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(palette.accent)
                            Text(L10n.tr("Atualizações em tempo real")).foregroundStyle(palette.secondary)
                            Spacer()
                            if let date = pedal.lastRead {
                                Text(date, format: .dateTime.hour().minute().second()).monospacedDigit().foregroundStyle(palette.secondary)
                            }
                            Button(L10n.tr("Atualizar")) { pedal.refresh() }
                                .buttonStyle(StudioButtonStyle()).disabled(!pedal.connected || pedal.busy)
                        }
                        .font(.custom("AvenirNext-Regular", size: 11))
                        if pedal.pendingSelection != nil || !pedal.pending.isEmpty {
                            Label(L10n.tr("Confirmando as alterações por releitura…"), systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(palette.accent).font(.custom("AvenirNext-Regular", size: 12))
                        }
                    } else {
                        VStack(spacing: 18) {
                            Image(systemName: "cable.connector").font(.system(size: 48, weight: .light)).foregroundStyle(palette.accent)
                            Text(pedal.busy ? L10n.tr("Lendo seu IR-2…") : L10n.tr("Conecte seu pedal por USB."))
                                .font(.custom("AvenirNext-DemiBold", size: 22))
                            Text(L10n.tr("Use o modo USB VENDOR e o driver BOSS para macOS."))
                                .foregroundStyle(palette.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 80)
                    }
                }
                .padding(30)
            }
        }
        .onChange(of: pedal.snapshot?.selectedChannel, initial: true) { _, channel in
            if let channel { viewedChannel = channel }
        }
    }

    private var connectionPanel: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(pedal.editingEnabled ? L10n.tr("Edição do pedal habilitada") : L10n.tr("Modo de leitura"))
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                Text(pedal.editingEnabled ? L10n.tr("Os controles enviam alterações e confirmam o valor recebido.") : L10n.tr("Habilite a edição para ajustar o IR-2 por aqui."))
                    .font(.custom("AvenirNext-Regular", size: 11)).foregroundStyle(palette.secondary)
                Text(L10n.tr("Ligado ou em bypass: verifique o LED CHECK. Esse estado ainda não é lido pelo app."))
                    .font(.custom("AvenirNext-Regular", size: 11)).foregroundStyle(palette.secondary)
            }
            Spacer()
            Toggle(L10n.tr("Editar pedal"), isOn: Binding(get: { pedal.editingEnabled }, set: pedal.setEditing))
                .toggleStyle(.switch).fixedSize().disabled(!pedal.connected || pedal.stale)
        }
        .padding(18).background(palette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border))
    }

    private func channelCard(_ channel: PedalChannel, snapshot: PedalSnapshot) -> some View {
        let color = channel == .green ? palette.green : palette.red
        let selected = viewedChannel == channel
        let active = snapshot.selectedChannel == channel
        let amp = AmpType.allCases[snapshot.patch(channel).value(.amp)]
        return Button { viewedChannel = channel } label: {
            HStack(spacing: 12) {
                Text(channel == .green ? "A" : "B").font(.custom("AvenirNext-DemiBold", size: 16))
                    .foregroundStyle(color).frame(width: 36, height: 36)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title).font(.custom("AvenirNext-DemiBold", size: 13))
                    Text(amp.rawValue).font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.secondary)
                }
                Spacer()
                if active {
                    Text(L10n.tr("SELECIONADO")).font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color).padding(6).background(color.opacity(0.1), in: Capsule())
                }
            }
            .padding(14).background(selected ? color.opacity(0.05) : palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? color.opacity(0.65) : palette.border))
        }
        .buttonStyle(.plain).accessibilityLabel(L10n.format("Inspecionar canal %@", channel.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var amplifierPanel: some View {
        HStack(spacing: 16) {
            Image(systemName: "hifispeaker.fill").font(.system(size: 28)).foregroundStyle(palette.accent)
                .frame(width: 60, height: 60).background(palette.raised, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                StudioCaption(title: L10n.tr("AMPLIFICADOR")).foregroundStyle(palette.secondary)
                Text(AmpType.allCases[pedal.value(channel: viewedChannel, parameter: .amp)].rawValue)
                    .font(.custom("AvenirNext-DemiBold", size: 27)).tracking(1.5)
            }
            Spacer()
            if pedal.snapshot?.selectedChannel != viewedChannel {
                Button(L10n.format("Selecionar %@", viewedChannel.title)) { pedal.select(viewedChannel) }
                    .buttonStyle(StudioButtonStyle()).disabled(!pedal.canEdit || pedal.pendingSelection != nil)
            }
            Menu {
                Picker(L10n.tr("Amplificador do pedal"), selection: Binding(
                    get: { pedal.value(channel: viewedChannel, parameter: .amp) },
                    set: { pedal.setValue(channel: viewedChannel, parameter: .amp, value: $0) }
                )) {
                    ForEach(AmpType.allCases) { amp in Text(amp.rawValue).tag(amp.pedalValue) }
                }
            } label: { Text(L10n.tr("Trocar modelo")) }
            .menuStyle(.borderlessButton).fixedSize().disabled(!pedal.canEdit)
            .padding(12).background(palette.raised, in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(22).background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border.opacity(0.8)))
    }

    private func binding(_ parameter: PedalParameter) -> Binding<Double> {
        // Capture the channel in the binding so a physical channel switch cannot redirect an edit.
        let channel = viewedChannel
        return Binding(get: { Double(pedal.value(channel: channel, parameter: parameter)) },
                       set: { pedal.setValue(channel: channel, parameter: parameter, value: Int($0.rounded())) })
    }
}
