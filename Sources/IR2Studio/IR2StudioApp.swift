import AppKit
import SwiftUI

@main
struct IR2StudioApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    @StateObject private var store = PresetStore()
    @StateObject private var pedal = PedalStore(session: IR2Session(transport: IR2MIDITransport()))
    @AppStorage("studioAppearance") private var appearance = StudioAppearance.system.rawValue

    var body: some Scene {
        WindowGroup("IR-2 Studio") {
            ContentView()
                .environmentObject(store)
                .environmentObject(pedal)
                .environment(\.locale, L10n.locale)
                .frame(minWidth: 1000, minHeight: 700)
                .preferredColorScheme((StudioAppearance(rawValue: appearance) ?? .system).colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 780)
    }
}

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The Dock can show a generic icon for locally built bundles even when
        // Finder resolves CFBundleIconFile correctly. Set its live image too.
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApplication.shared.applicationIconImage = icon
    }
}
