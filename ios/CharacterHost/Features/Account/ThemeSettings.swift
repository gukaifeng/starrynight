import Foundation
import Observation

@MainActor @Observable final class ThemeSettings {
    static let shared = ThemeSettings()
    var paletteID: String { didSet { save() } }
    var style: String { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "jinban.theme.v1"
    var solid: Bool { style == "solid" }
    init(defaults:UserDefaults? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--companion-testing")
        self.defaults = defaults ?? (testing ? UserDefaults(suiteName:"com.modelspace.theme.testing")! : .standard)
        if testing && !ProcessInfo.processInfo.arguments.contains("--keep-companion-data") { self.defaults.removeObject(forKey:key) }
        let saved = self.defaults.dictionary(forKey:key)
        paletteID = saved?["palette"] as? String ?? "silver"
        style = saved?["style"] as? String == "solid" ? "solid" : "glass"
    }
    private func save() {
        defaults.set(["palette":paletteID,"style":style],forKey:key)
        NotificationCenter.default.post(name:.themeChanged,object:nil)
    }
}
extension Notification.Name { static let themeChanged = Notification.Name("jinban.theme.changed") }
