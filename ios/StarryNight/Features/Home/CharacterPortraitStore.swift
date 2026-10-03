import UIKit
import Observation
import CryptoKit

/// Portraits are derived from saved appearance, never from a chat pose or camera gesture.
@MainActor @Observable
final class CharacterPortraitStore {
    private struct Entry: Codable { let key: String }
    private var images: [String:UIImage] = [:]
    private var keys: [String:String] = [:]
    private let directory: URL
    private(set) var clearing = false

    init(directory: URL? = nil) {
        self.directory = directory ?? CacheLocations.live.portraits
        let directory = self.directory
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let files = (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
        for file in files where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf:directory.appendingPathComponent(id + ".json")),
               let entry = try? JSONDecoder().decode(Entry.self,from:data),
               let image = UIImage(contentsOfFile:directory.appendingPathComponent(id + ".png").path) {
                keys[id] = entry.key; images[id] = image
            }
        }
    }
    static func key(model:ModelDescriptor,profile:CharacterProfile) -> String {
        // Neutral light and standing portrait: background, posture and chat preferences do not invalidate it.
        var studio = profile.resolvedStudio
        studio.posture = nil; studio.environments = nil; studio.room = "sunroom"
        studio.lightAngle = -35; studio.lightHeight = 48; studio.lightIntensity = 1; studio.shadow = 0.75
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let appearance = (try? encoder.encode(studio)) ?? Data()
        var data = Data(("portrait-v1|" + model.id + "|" + model.packageVersion + "|" + profile.accent + "|").utf8)
        data.append(appearance)
        return SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    }
    func hasCurrent(_ model:ModelDescriptor,profile:CharacterProfile) -> Bool {
        if UIImage(named:"Avatar_"+model.runtimeID.replacingOccurrences(of:"-",with:"_")) != nil {return true}
        return keys[model.id] == Self.key(model:model,profile:profile) && images[model.id] != nil
    }
    func image(_ model:ModelDescriptor,profile:CharacterProfile) -> UIImage? {
        if let avatar=UIImage(named:"Avatar_"+model.runtimeID.replacingOccurrences(of:"-",with:"_")) {return avatar}
        return hasCurrent(model,profile:profile) ? images[model.id] : nil
    }
    /// Unity writes only a SHA-256-named staging image; correlated host requests own the model mapping.
    func accept(model:ModelDescriptor,key:String) -> Bool {
        guard key.count == 64, key.allSatisfy({ $0.isHexDigit }) else { return false }
        let staging = directory.appendingPathComponent(key + ".png")
        defer { try? FileManager.default.removeItem(at:staging) }
        guard !clearing else { return false }
        guard let data = try? Data(contentsOf:staging), data.count < 4_000_000,
              let image = UIImage(data:data), image.size == CGSize(width:512,height:512) else { return false }
        do {
            try data.write(to:directory.appendingPathComponent(model.id + ".png"),options:.atomic)
            try JSONEncoder().encode(Entry(key:key)).write(to:directory.appendingPathComponent(model.id + ".json"),options:.atomic)
            images[model.id] = image; keys[model.id] = key
            return true
        } catch { return false }
    }
    func beginClearing() { clearing = true; images.removeAll(); keys.removeAll() }
    func endClearing() { images.removeAll(); keys.removeAll(); clearing = false }
}
