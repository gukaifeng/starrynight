import Foundation

struct CharacterVoice: Codable, Identifiable, Equatable, Sendable {
    let id, title, detail, engine: String
    let speed: Double
}
struct SoundscapeTrack: Codable, Identifiable, Equatable, Sendable {
    let id, asset, title, detail, symbol: String
    // Optional additions keep schema 1 and saved legacy collection snapshots readable.
    let assetExtension, sourceModelID, sha256: String?
    let duration: Double?
    var resourceExtension: String { assetExtension ?? "wav" }
    var resourceURL: URL? { Bundle.main.url(forResource:asset,withExtension:resourceExtension) }
    var durationLabel: String? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return "\(Int(duration.rounded()))″ 循环"
    }
    func scoped(to scope:String) -> Self {
        Self(id:scope+"/"+id.split(separator:"/").last!,asset:asset,title:title,detail:detail,symbol:symbol,
             assetExtension:assetExtension,sourceModelID:sourceModelID,sha256:sha256,duration:duration)
    }
}
struct CharacterAudioPreferences: Codable, Equatable, Sendable {
    var enabled = true
    var trackID: String
    var volume = 0.28
    // Older archives used false as the default and did not distinguish an
    // explicit pause. Migrate that default once; current choices, including
    // pause, then survive every tab return, character switch and app restart.
    var autoplayVersion: Int? = 1
    var masterMuted: Bool? = nil
    var speechVolume: Double? = nil
    // Decode pre-0.51 preferences; there was never an authored effects player.
    // normalize retires these fields without changing speech or music choices.
    var effectsEnabled: Bool? = nil
    var effectsVolume: Double? = nil
    var volumeControlsVersion: Int? = nil
    var normalizedAutoplay: Self {
        guard autoplayVersion == nil else { return self }
        var value = self
        value.enabled = true; value.autoplayVersion = 1
        return value
    }
}

/// A collection owns its option IDs. Physical files may be shared read-only,
/// but no selection or editable value is stored in this catalog.
struct CharacterCollection: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id, version, modelID, modelPackageID, modelPackageVersion: String
    let actions, environments: [String]
    let voices: [CharacterVoice]
    let music: [SoundscapeTrack]
    let defaultEnvironment, defaultVoice, defaultMusic: String
    let scopeID: String?
    let previewOnly: Bool?
    var optionScope: String { scopeID ?? modelID }

    var availableEnvironments: [EnvironmentDescriptor] {
        environments.compactMap { id in EnvironmentDescriptor.all.first { $0.id == id } }
    }
    func voice(_ id: String?) -> CharacterVoice {
        voices.first { $0.id == migratedOptionID(id) } ?? voices.first { $0.id == defaultVoice }!
    }
    private func migratedOptionID(_ input:String?) -> String? {
        guard let input else { return nil }
        if input.hasPrefix(optionScope+"/") { return input }
        // Existing created-role preferences used the base role prefix. Other roles'
        // or siblings' selections deliberately cannot migrate across this boundary.
        if optionScope != modelID, input.hasPrefix(modelID+"/") {
            return optionScope+"/"+input.dropFirst(modelID.count+1)
        }
        return input
    }
    /// Preserve the authored environment/action/voice snapshot, while upgrading old
    /// shared two-song snapshots to this base role's current private music library.
    /// No model.collection access here: callers may use this from that property.
    func scoped(to characterID:String) -> Self {
        let latest = Self.all.first { $0.modelID == modelID }
        let sourceMusic = latest?.music ?? music
        if characterID == modelID, scopeID == nil, sourceMusic == music { return self }
        func remap(_ value:String) -> String {
            guard let last=value.split(separator:"/").last else { return "" }
            return characterID+"/"+last
        }
        let mappedMusic = sourceMusic.map { $0.scoped(to:characterID) }
        let musicDefault = mappedMusic.contains(where:{ $0.id == remap(defaultMusic) }) ? remap(defaultMusic) : remap(latest?.defaultMusic ?? defaultMusic)
        return Self(schemaVersion:schemaVersion,id:"app.starry.collections."+characterID,version:latest?.version ?? version,
            modelID:modelID,modelPackageID:modelPackageID,modelPackageVersion:modelPackageVersion,
            actions:actions,environments:environments,
            voices:voices.map { CharacterVoice(id:remap($0.id),title:$0.title,detail:$0.detail,engine:$0.engine,speed:$0.speed) },
            music:mappedMusic,defaultEnvironment:defaultEnvironment,defaultVoice:remap(defaultVoice),defaultMusic:musicDefault,
            scopeID:characterID,previewOnly:previewOnly)
    }
    func normalize(_ input: CharacterStudio) -> CharacterStudio {
        var studio = input.normalized
        if !environments.contains(studio.room) { studio.selectEnvironment(defaultEnvironment) }
        studio.environments = studio.environments?.filter { environments.contains($0.key) }
        return studio.normalized
    }
    func normalize(_ input: CharacterProfile) -> CharacterProfile {
        var profile = input; profile.normalize()
        profile.studio = normalize(profile.resolvedStudio)
        profile.voiceID = voice(profile.voiceID).id
        var audio = (profile.audio ?? CharacterAudioPreferences(trackID:defaultMusic)).normalizedAutoplay
        // Convert legacy toggles into visible zero-volume values once. Raising a
        // slider can then always produce sound: there is no hidden mute gate.
        if audio.volumeControlsVersion == nil {
            let allMuted = audio.masterMuted == true
            if allMuted || !audio.enabled { audio.volume = 0 }
            if allMuted || !profile.autoSpeak { audio.speechVolume = 0 }
            audio.volumeControlsVersion = 1
        }
        audio.masterMuted = false; audio.enabled = true
        audio.effectsEnabled = nil; audio.effectsVolume = nil
        profile.autoSpeak = true
        audio.trackID = migratedOptionID(audio.trackID) ?? defaultMusic
        if !music.contains(where:{ $0.id == audio.trackID }) { audio.trackID = defaultMusic }
        audio.volume = audio.volume.isFinite ? min(1,max(0,audio.volume)) : 0.28
        audio.speechVolume = audio.speechVolume.map { $0.isFinite ? min(1,max(0,$0)) : 1 }
        if previewOnly == true { audio.volume = 0; audio.speechVolume = 0; profile.autoSpeak = false }
        profile.audio = audio
        return profile
    }
    func initialProfile() -> CharacterProfile {
        var profile = CharacterProfile.initial(modelID)
        var studio = profile.resolvedStudio; studio.selectEnvironment(defaultEnvironment)
        profile.studio = studio
        return normalize(profile)
    }
    func isCompatible(with model:ModelDescriptor) -> Bool {
        if previewOnly == true {
            return schemaVersion == 1 && modelID == model.runtimeID && modelPackageID == model.packageId &&
                modelPackageVersion == model.packageVersion && !environments.isEmpty &&
                environments.contains(defaultEnvironment) && voices.count == 1 && music.isEmpty &&
                defaultMusic.isEmpty && voices[0].id == defaultVoice &&
                Set(actions).isSubset(of:Set(model.actions.map(\.id)))
        }
        return schemaVersion == 1 && modelID == model.runtimeID && modelPackageID == model.packageId &&
        !environments.isEmpty && Set(environments).isSubset(of:Set(EnvironmentDescriptor.all.map(\.id))) &&
        environments.contains(defaultEnvironment) && !voices.isEmpty && !music.isEmpty &&
        voices.contains(where:{ $0.id == defaultVoice }) && music.contains(where:{ $0.id == defaultMusic }) &&
        Set(actions).isSubset(of:Set(model.actions.map(\.id))) &&
        Set(voices.map(\.id)).count == voices.count && Set(music.map(\.id)).count == music.count &&
        // Legacy saved collections still name the old offline provider. New
        // collections declare the live AI voice service; both are readable.
        voices.allSatisfy { ["melo-zh-v1", "aliyun-character-v1"].contains($0.engine) && $0.speed.isFinite && (0.7...1.4).contains($0.speed) } &&
        voices.allSatisfy { $0.id.hasPrefix(optionScope+"/") } &&
        music.allSatisfy { track in
            guard track.id.hasPrefix(optionScope+"/"), track.resourceURL != nil else { return false }
            // Read compatibility for old persisted snapshots; scoped(to:) upgrades
            // these assets before playback without replacing other frozen options.
            if track.sourceModelID == nil { return ["IslandAfternoon","MoonlitTide"].contains(track.asset) && track.resourceExtension == "wav" }
            return track.sourceModelID == modelID && track.resourceExtension == "caf" &&
                track.asset.hasPrefix("Music_"+modelID.replacingOccurrences(of:"-",with:"_")+"_") &&
                track.sha256?.count == 64 && (track.duration ?? 0) > 0
        }
    }
    private struct Catalog: Decodable { let schemaVersion:Int; let collections:[CharacterCollection] }
    static let all: [CharacterCollection] = {
        guard let url = Bundle.main.url(forResource:"CharacterCollections",withExtension:"json"),
              let data = try? Data(contentsOf:url), let catalog = try? JSONDecoder().decode(Catalog.self,from:data),
              catalog.schemaVersion == 1 else { preconditionFailure("Missing character collections") }
        return catalog.collections
    }()
    static func builtin(_ model:ModelDescriptor) -> Self {
        guard let pack = all.first(where:{ $0.modelID == model.runtimeID }), pack.isCompatible(with:model) else {
            preconditionFailure("Invalid character collection for " + model.runtimeID)
        }
        return pack
    }
}

/// Pure local adapter: search is limited to public/owned catalog input, never other accounts' records.
enum CharacterSearch {
    static func matches(_ query:String,model:ModelDescriptor,profile:CharacterProfile,authorName:String = "") -> Bool {
        let terms = query.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:.current)
            .split(whereSeparator: { $0.isWhitespace })
        let text = [profile.name,profile.personality,profile.tone,profile.background,model.originalName,model.description,model.display.tagline,authorName]
            .joined(separator:" ").folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:.current)
        return terms.allSatisfy { text.contains($0) }
    }
}
