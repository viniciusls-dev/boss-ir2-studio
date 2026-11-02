import XCTest
@testable import IR2Studio

final class LocalizationTests: XCTestCase {
    func testSystemLanguageUsesSupportedPreferencesAndEnglishFallback() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["pt-PT", "en-US"]), .portuguese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "en-GB", "pt-BR"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["pt-BR"]), .english)
        XCTAssertEqual(AppLanguage.portuguese.resolved(preferredLanguages: ["en-US"]), .portuguese)
    }

    func testLanguagePreferenceKeepsNativeMenusInSyncAndCanReturnToSystem() throws {
        let suite = "IR2Studio.LocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        AppLanguage.english.save(in: defaults)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.preferenceKey), "en")
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["en"])
        AppLanguage.portuguese.save(in: defaults)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["pt-BR"])
        AppLanguage.system.save(in: defaults)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.preferenceKey), "system")
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
    }

    func testPackagedTranslationsAreCompleteAndPreserveFormatArguments() throws {
        func table(_ language: AppLanguage) throws -> [String: String] {
            let url = try XCTUnwrap(L10n.localizedBundle(for: language).url(forResource: "Localizable", withExtension: "strings"))
            let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            return try XCTUnwrap(value as? [String: String])
        }
        let english = try table(.english)
        let portuguese = try table(.portuguese)
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(portuguese.keys))
        let placeholders = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?[@dfuls]"#)
        func arguments(_ value: String) -> [String] {
            placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .compactMap { Range($0.range, in: value).map { String(value[$0]) } }.sorted()
        }
        for key in english.keys {
            let en = try XCTUnwrap(english[key])
            let pt = try XCTUnwrap(portuguese[key])
            XCTAssertFalse(en.isEmpty, key)
            XCTAssertFalse(pt.isEmpty, key)
            XCTAssertEqual(arguments(en), arguments(pt), key)
            XCTAssertEqual(L10n.string(key, language: .english), en, key)
            XCTAssertEqual(L10n.string(key, language: .portuguese), pt, key)
        }
        XCTAssertEqual(L10n.string("Modo de leitura", language: .english), "Read-only mode")
        XCTAssertEqual(L10n.string("Modo de leitura", language: .portuguese), "Modo de leitura")
    }
}
