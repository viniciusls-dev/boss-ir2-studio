import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", portuguese = "pt-BR"
    var id: String { rawValue }
    static let preferenceKey = "studioLanguage"

    var title: String {
        switch self {
        case .system: L10n.tr("Sistema")
        case .english: "English"
        case .portuguese: "Português"
        }
    }

    func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let code = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if code == "pt" || code.hasPrefix("pt-") { return .portuguese }
            if code == "en" || code.hasPrefix("en-") { return .english }
        }
        return .english
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
        // macOS reads this app-specific preference at launch for its menus and panels.
        if self == .system { defaults.removeObject(forKey: "AppleLanguages") }
        else { defaults.set([rawValue], forKey: "AppleLanguages") }
    }
}

enum L10n {
    // Keep the interface, generated messages, and native macOS controls in the same
    // language for the whole session. A preference change takes effect next launch.
    static let launchPreference = AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.preferenceKey) ?? "") ?? .system
    static let language = launchPreference.resolved(preferredLanguages: Locale.preferredLanguages)
    static let locale = Locale(identifier: language.rawValue)

    static let resourceBundle = Bundle.module

    static func localizedBundle(for language: AppLanguage) -> Bundle {
        let resolved = language == .system ? Self.language : language
        guard let url = resourceBundle.url(forResource: resolved.rawValue, withExtension: "lproj"),
              let bundle = Bundle(url: url) else {
            preconditionFailure("Missing IR2Studio language resources")
        }
        return bundle
    }

    static func tr(_ key: String) -> String { string(key, language: language) }

    static func string(_ key: String, language: AppLanguage) -> String {
        localizedBundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: locale, arguments: arguments)
    }
}
