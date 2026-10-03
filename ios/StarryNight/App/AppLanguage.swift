import Foundation
import Observation
import SwiftUI
import UIKit

enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case simplified = "zh-Hans", traditional = "zh-Hant", english = "en"
    var id: String { rawValue }
    var nativeName: String { switch self { case .simplified: "简体中文"; case .traditional: "繁體中文"; case .english: "English" } }
    var locale: Locale { Locale(identifier: rawValue) }
    static func resolve(_ preference: String, preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        if let explicit = Self(rawValue: preference) { return explicit }
        // The primary system language determines the fallback, not a secondary
        // language from the user's keyboard list.
        let primary = (preferredLanguages.first ?? "").lowercased().replacingOccurrences(of: "_", with: "-")
        if primary == "en" || primary.hasPrefix("en-") { return .english }
        if primary.hasPrefix("zh") {
            return primary.contains("hant") || (!primary.contains("hans") && ["tw", "hk", "mo"].contains(primary.split(separator:"-").last.map(String.init) ?? "")) ? .traditional : .simplified
        }
        return .simplified
    }
}

@MainActor @Observable final class AppLanguageSettings {
    static let shared = AppLanguageSettings()
    nonisolated static let key = "starry.app.language.v1"
    var selection: String {
        didSet { defaults.set(selection, forKey: Self.key); NotificationCenter.default.post(name: .appLanguageChanged, object: nil) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    private var systemLanguages: [String]
    var resolved: AppLanguage { AppLanguage.resolve(selection, preferredLanguages: systemLanguages) }
    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults; systemLanguages = preferredLanguages
        selection = defaults.string(forKey: Self.key) ?? "system"
        if selection != "system" && AppLanguage(rawValue: selection) == nil { selection = "system" }
    }
    func refreshSystemLanguage() { systemLanguages = Locale.preferredLanguages }
}

extension Notification.Name { static let appLanguageChanged = Notification.Name("starry.app.language.changed") }

/// For UIKit and dynamic UI labels only. Character names, user text, model
/// metadata and transcripts remain verbatim; never pass them through a lookup.
enum L10n {
    static var language: AppLanguage { AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguageSettings.key) ?? "system") }
    static func bundle(_ language: AppLanguage) -> Bundle {
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
    @MainActor static func text(_ key: String) -> String { bundle(AppLanguageSettings.shared.resolved).localizedString(forKey: key, value: key, table: nil) }
    @MainActor static func format(_ key: String, _ arguments: CVarArg...) -> String { String(format: text(key), locale: AppLanguageSettings.shared.resolved.locale, arguments: arguments) }
}

struct AppLanguageRoot<Content: View>: View {
    let content: Content
    var body: some View {
        content.environment(\.locale, AppLanguageSettings.shared.resolved.locale)
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in AppLanguageSettings.shared.refreshSystemLanguage() }
    }
}

/// Each UIKit-hosted window/panel needs its own locale environment. Updating
/// locale preserves view identity and in-flight chat tasks.
class LanguageHostingController<Content: View>: UIHostingController<AppLanguageRoot<Content>> {
    var content: Content { didSet { rootView = AppLanguageRoot(content: content) } }
    init(rootView: Content) { content = rootView; super.init(rootView: AppLanguageRoot(content: rootView)) }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct AppLanguageSettingsView: View {
    @Bindable private var settings = AppLanguageSettings.shared
    var body: some View {
        List {
            Section {
                option("system", name: L10n.text("跟随系统"), detail: settings.resolved.nativeName)
                ForEach(AppLanguage.allCases) { language in option(language.rawValue, name: language.nativeName) }
            } footer: {
                Text("系统语言不在支持范围时使用简体中文。界面立即切换；角色保留原有说话语言，不同语言的回复可在气泡中翻译。")
            }.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden).background(Theme.background)
            .foregroundStyle(Theme.ink).tint(Theme.accent)
            .navigationTitle("语言").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("appLanguageSettings")
    }
    private func option(_ id: String, name: String, detail: String? = nil) -> some View {
        Button { settings.selection = id } label: {
            HStack(spacing:12) {
                Text(verbatim:name)
                Spacer()
                if let detail { Text(verbatim:detail).font(.caption).foregroundStyle(Theme.secondary) }
                Image(systemName:"checkmark").font(.system(size:13,weight:.semibold)).opacity(settings.selection == id ? 1 : 0)
            }.padding(.vertical,6).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("language-" + id)
            .accessibilityAddTraits(settings.selection == id ? .isSelected : [])
    }
}
