import Foundation

struct CharacterAction: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let semantic: String
    enum CodingKeys: String, CodingKey { case id, name = "label", symbol, semantic }
}
struct CharacterParameter: Identifiable, Decodable, Sendable {
    let id: String
    let label: String
    let kind: String
    let section: String
    let min: Double
    let max: Double
    let initial: Double
    let options: [String]
}
struct ModelDescriptor: Identifiable, Decodable, Sendable {
    struct Display: Decodable, Sendable {
        let name, originalName, description, invitation, tagline, symbol, thumbnail: String
        let cardIdentifier, openIdentifier, style: String
        let thumbnailScale: Double
        let order: Int
    }
    struct Compatibility: Decodable, Sendable { let required, optional: [String] }
    struct DeclaredAction: Decodable { let id, label, symbol, semantic: String; let button: Bool }
    let id: String
    let runtimeID: String
    let packageId: String
    let packageVersion: String
    let display: Display
    let compatibility: Compatibility
    let actions: [CharacterAction]
    let parameters: [CharacterParameter]
    let posture: PostureProfile?
    let performance: CharacterPerformanceProfile?
    var collectionSnapshot: CharacterCollection? = nil
    var authoredProfileSnapshot: CharacterProfile? = nil
    var collection: CharacterCollection { (collectionSnapshot ?? .builtin(self)).scoped(to:id) }
    // Listener preferences never replace the authored character definition.
    func conversationProfile(preserving personal:CharacterProfile?) -> CharacterProfile {
        var value = authoredProfileSnapshot ?? collection.initialProfile()
        value.autoSpeak = personal?.autoSpeak ?? true
        value.audio = personal?.audio ?? CharacterAudioPreferences(trackID:collection.defaultMusic)
        value.atmosphereEnabled = personal?.atmosphereEnabled
        value.atmosphereLevel = personal?.atmosphereLevel
        return collection.normalize(value)
    }
    var name: String { display.name }
    var originalName: String { display.originalName }
    var description: String { display.description }
    var thumbnail: String { display.thumbnail }
    var isLegacyHuman: Bool { supports("legacy.human-studio@1") }
    var isCustomizable: Bool { isLegacyHuman || !parameters.isEmpty }
    var cardIdentifier: String { display.cardIdentifier }
    var openIdentifier: String { display.openIdentifier }
    func supports(_ capability: String) -> Bool { (compatibility.required + compatibility.optional).contains(capability) }
    func availableActions(for preferences: PosturePreferences) -> [CharacterAction] {
        let normalized = preferences.normalized(self)
        guard let pose = posture?.poses.first(where:{ $0.id == normalized.id }) else { return actions.filter { collection.actions.contains($0.id) } }
        let supported = Set(pose.actions.map(\.action))
        return actions.filter { supported.contains($0.id) && collection.actions.contains($0.id) }
    }
    enum CodingKeys: String, CodingKey { case id, packageId, packageVersion, display, compatibility, actions, parameters, posture, performance }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(String.self,forKey:.id); runtimeID = id; packageId = try c.decode(String.self,forKey:.packageId)
        packageVersion = try c.decode(String.self,forKey:.packageVersion)
        display = try c.decode(Display.self,forKey:.display)
        compatibility = try c.decode(Compatibility.self,forKey:.compatibility)
        parameters = try c.decode([CharacterParameter].self,forKey:.parameters)
        let profile = try c.decodeIfPresent(PostureProfile.self,forKey:.posture)
        posture = profile?.poses.isEmpty == false ? profile : nil
        let importedPerformance = try c.decodeIfPresent(CharacterPerformanceProfile.self,forKey:.performance)
        performance = [1,2].contains(importedPerformance?.schemaVersion ?? 0) && importedPerformance?.options.isEmpty == false ? importedPerformance : nil
        let raw = try c.decode([DeclaredAction].self,forKey:.actions)
        actions = raw.filter(\.button).map { CharacterAction(id:$0.id,name:$0.label,symbol:$0.symbol,semantic:$0.semantic) }
    }
    private init(id:String,base:ModelDescriptor) {
        self.id = id; runtimeID = base.runtimeID; packageId = base.packageId; packageVersion = base.packageVersion
        display = base.display; compatibility = base.compatibility; actions = base.actions
        parameters = base.parameters; posture = base.posture; performance = base.performance
    }
    func instance(id:String, collection:CharacterCollection? = nil, authoredProfile:CharacterProfile? = nil) -> Self {
        var value = Self(id:id,base:self)
        value.collectionSnapshot = collection ?? self.collection
        value.authoredProfileSnapshot = authoredProfile ?? authoredProfileSnapshot
        return value
    }
    private struct Catalog: Decodable { let schemaVersion, apiMajor: Int; let characters: [ModelDescriptor] }
    static let all: [ModelDescriptor] = {
        guard let url = Bundle.main.url(forResource:"CharacterCatalog",withExtension:"json"),
              let data = try? Data(contentsOf:url), let catalog = try? JSONDecoder().decode(Catalog.self,from:data),
              catalog.schemaVersion == 1, catalog.apiMajor == 1, !catalog.characters.isEmpty else {
            preconditionFailure("Character catalog is missing or incompatible. Regenerate the host from the validated character packages.")
        }
        return catalog.characters.sorted { $0.display.order < $1.display.order }
    }()
    // Existing navigation/test entry points. Production catalog and controls are fully data driven.
    static var defaultCharacter: Self { all.first { $0.id == "anime-kipfel" } ?? all[0] }
    static var robot: Self { all.first { $0.id == "studio-robot" }! }
    static var miku: Self { all.first { $0.id == "hatsune-miku" }! }
    static var human: Self { all.first { $0.id == "real-woman" }! }
}
