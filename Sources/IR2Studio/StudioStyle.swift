import SwiftUI

enum StudioAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L10n.tr("Sistema")
        case .light: L10n.tr("Claro")
        case .dark: L10n.tr("Escuro")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct StudioPalette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    var background: Color { Color(studioHex: dark ? 0x1C1C22 : 0xF6F6F4) }
    var sidebar: Color { Color(studioHex: dark ? 0x25232D : 0xEEEDEB) }
    var panel: Color { Color(studioHex: dark ? 0x25252D : 0xFFFFFF) }
    var raised: Color { Color(studioHex: dark ? 0x302F38 : 0xF0F1EF) }
    var border: Color { Color(studioHex: dark ? 0x3C3B45 : 0xDDDEDA) }
    var text: Color { Color(studioHex: dark ? 0xF3F1F7 : 0x25272B) }
    var secondary: Color { Color(studioHex: dark ? 0xABA6B7 : 0x646972) }
    var accent: Color { Color(studioHex: dark ? 0x41D6C0 : 0x087F72) }
    var green: Color { Color(studioHex: dark ? 0x75D4AB : 0x25734E) }
    var red: Color { Color(studioHex: dark ? 0xF18F98 : 0xB63A50) }
}

extension Color {
    init(studioHex value: UInt32) {
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255, opacity: 1)
    }
}

struct StudioCaption: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.8)
    }
}

struct StudioButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let palette = StudioPalette(scheme: scheme)
        configuration.label
            .font(.custom("AvenirNext-DemiBold", size: 12))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(prominent ? (scheme == .dark ? Color(studioHex: 0x123E36) : .white) : palette.text)
            .background(prominent ? palette.accent : palette.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.border.opacity(prominent ? 0 : 0.7)))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct StudioKnob: View {
    let title: String
    @Binding var value: Double
    var maximum: Double = 100
    @Environment(\.colorScheme) private var scheme
    @State private var dragStart: Double?

    var body: some View {
        let palette = StudioPalette(scheme: scheme)
        VStack(spacing: 12) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2).foregroundStyle(palette.secondary)
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(palette.border, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * min(max(value / maximum, 0), 1))
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().fill(LinearGradient(colors: [palette.raised, palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(9)
                    .overlay(Circle().strokeBorder(palette.border, lineWidth: 1).padding(9))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.08), radius: 5, y: 3)
                Capsule().fill(palette.accent).frame(width: 3, height: 13)
                    .offset(y: -22).rotationEffect(.degrees(-135 + 270 * value / maximum))
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if dragStart == nil { dragStart = value }
                value = min(maximum, max(0, ((dragStart ?? value) - drag.translation.height * 0.65 + drag.translation.width * 0.35).rounded()))
            }.onEnded { _ in dragStart = nil })
            .help(L10n.format("Arraste para ajustar %@", title))
            .accessibilityHidden(true)
            Text("\(Int(value))").font(.custom("AvenirNext-DemiBold", size: 20)).monospacedDigit()
                .foregroundStyle(palette.text)
            Slider(value: $value, in: 0...maximum, step: 1) { Text(title) }.labelsHidden()
                .tint(palette.accent).accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }
}
