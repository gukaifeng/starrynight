import Foundation

/// The host displays authored choices; runtime asset paths and bindings stay in Unity.
struct CharacterPerformanceProfile: Decodable, Sendable {
    struct Group: Decodable, Identifiable, Sendable {
        let id, label: String
        let symbol: String?
        var resolvedSymbol: String {
            if let symbol, !symbol.isEmpty { return symbol }
            return ["expression":"face.smiling","pose":"figure.stand","hands":"hand.raised",
                    "ears":"ear","tail":"wind","appearance":"tshirt"][id] ?? "sparkles"
        }
    }
    struct Option: Decodable, Identifiable, Sendable {
        let id, group, label, kind: String
        let description: String?
        let duration: Double?
        let loop: Bool?
        let defaultOn: Bool?
        var isToggle: Bool { kind == "toggle" }
    }
    let schemaVersion: Int
    let groups: [Group]
    let options: [Option]

    func isDefault(group: String, selections: Set<String>) -> Bool {
        let choices = options.filter { $0.group == group }
        let actual = selections.intersection(Set(choices.map(\.id)))
        return actual == Set(choices.filter { $0.defaultOn == true }.map(\.id))
    }
}
