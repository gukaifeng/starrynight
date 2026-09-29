import Foundation

struct EnvironmentPalette: Decodable, Identifiable, Sendable {
    let id, name, surface, accent: String
}
struct EnvironmentDescriptor: Decodable, Identifiable, Sendable {
    struct Display: Decodable, Sendable { let name, description, category, thumbnail: String; let order: Int }
    let id, packageId, packageVersion: String
    let display: Display
    let palettes: [EnvironmentPalette]
    private struct Catalog: Decodable { let schemaVersion, apiMajor: Int; let environments: [EnvironmentDescriptor] }
    static let all: [Self] = {
        guard let url = Bundle.main.url(forResource:"EnvironmentCatalog",withExtension:"json"),
              let data = try? Data(contentsOf:url), let catalog = try? JSONDecoder().decode(Catalog.self,from:data),
              catalog.schemaVersion == 1, catalog.apiMajor == 1, !catalog.environments.isEmpty else {
            preconditionFailure("Environment catalog is missing. Regenerate from validated scene packages.")
        }
        return catalog.environments.sorted { $0.display.order < $1.display.order }
    }()
    static func find(_ id: String) -> Self { all.first { $0.id == id } ?? all[0] }
}
struct EnvironmentCustomization: Codable, Equatable, Sendable {
    var palette = "original"
    var decorations = true
    var angle = 0.0
    var lightAngle = -35.0
    var lightHeight = 48.0
    var lightIntensity = 1.0
    var shadow = 0.75
}
