import SwiftUI

struct LoadedBackup {
    let name: String
    let snapshot: IR2Backup
}

struct BackupView: View {
    let backup: LoadedBackup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var palette: StudioPalette { StudioPalette(scheme: scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        StudioCaption(title: "BACKUP DO PEDAL").foregroundStyle(palette.accent)
                        Text("Seu som, registrado.").font(.custom("AvenirNext-DemiBold", size: 27))
                        Label(backup.name, systemImage: "doc.text")
                            .foregroundStyle(palette.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 14, height: 14) }
                        .buttonStyle(StudioButtonStyle()).keyboardShortcut(.cancelAction).help("Fechar backup")
                        .accessibilityLabel("Fechar backup")
                }
                HStack(spacing: 8) {
                    Circle().fill(backup.snapshot.selectedChannel == .green ? palette.green : palette.red).frame(width: 6, height: 6)
                    Text("Canal selecionado: \(backup.snapshot.selectedChannel.rawValue)")
                        .font(.custom("AvenirNext-Medium", size: 12))
                    Spacer()
                    Text("LEITURA DO ARQUIVO").font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1).foregroundStyle(palette.secondary)
                }
                HStack(spacing: 14) {
                    gainCard("Verde", letter: "A", gain: backup.snapshot.greenGain, color: palette.green)
                    gainCard("Vermelho", letter: "B", gain: backup.snapshot.redGain, color: palette.red)
                }
                Text("Valores gravados no arquivo, sem conversão para a posição física dos botões.")
                    .font(.custom("AvenirNext-Regular", size: 12)).foregroundStyle(palette.secondary)
                Rectangle().fill(palette.border).frame(height: 1)
                DisclosureGroup("Parâmetros brutos dos canais") {
                    Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 9) {
                        GridRow {
                            Text("ÍNDICE")
                            Text("VERDE · HEX")
                            Text("VERMELHO · HEX")
                        }
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(palette.secondary)
                        ForEach(0..<7, id: \.self) { index in
                            GridRow {
                                Text("\(index) — \(PedalParameter(rawValue: index)?.title ?? "Parâmetro")")
                                Text(hex(backup.snapshot.greenParameters[index]))
                                Text(hex(backup.snapshot.redParameters[index]))
                            }
                            .foregroundStyle(index == 4 ? palette.accent : palette.text)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).padding(.top, 16)
                }
                .tint(palette.accent)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(palette.accent)
                    Text("Esta leitura é do momento do backup. Os valores não são atualizados ao vivo e não alteram seus presets locais.")
                        .font(.custom("AvenirNext-Regular", size: 12)).foregroundStyle(palette.secondary)
                }
            }
            .padding(32)
        }
        .frame(width: 640, height: 620)
        .font(.custom("AvenirNext-Regular", size: 13))
        .foregroundStyle(palette.text).background(palette.background)
    }

    private func gainCard(_ channel: String, letter: String, gain: UInt8, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Canal \(channel)", systemImage: "circle.fill")
                    .font(.custom("AvenirNext-Medium", size: 12)).foregroundStyle(color)
                Spacer()
                Text(letter).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
            }
            Text("\(gain)").font(.custom("AvenirNext-Medium", size: 64)).monospacedDigit()
            HStack {
                StudioCaption(title: "GAIN").foregroundStyle(palette.secondary)
                Spacer()
                Text("0x\(hex(gain))").font(.system(size: 12, design: .monospaced)).foregroundStyle(color)
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border))
    }

    private func hex(_ value: UInt8) -> String { String(format: "%02X", value) }
}
