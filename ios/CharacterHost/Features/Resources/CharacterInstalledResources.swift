import Foundation
import os

/// Only hash-verified release directories enter this registry. Read from speech
/// and music queues without doing disk scans or waiting on the main thread.
enum CharacterInstalledResources {
    private static let releases=OSAllocatedUnfairLock(initialState:[String:URL]())
    private struct Metadata:Decodable {let opening:CharacterOpenings.Package;let atmosphere:CharacterAtmosphere}
    static func register(_ id:String,release:URL) {
        releases.withLock {$0[id]=release.appendingPathComponent("content")}
        if let data=try? Data(contentsOf:release.appendingPathComponent("content/metadata/character.json")),
           let metadata=try? JSONDecoder().decode(Metadata.self,from:data),
           metadata.opening.characterID==id,metadata.atmosphere.id==id {
            CharacterOpenings.register(metadata.opening);CharacterAtmosphere.register(metadata.atmosphere)
        }
    }
    static func clear() {releases.withLock {$0.removeAll()};CharacterOpenings.clearInstalled();CharacterAtmosphere.clearInstalled()}
    static func image(_ name:String,characterID:String)->URL? {
        guard ["cover","avatar"].contains(name) else{return nil}
        return releases.withLock {items in
            guard let root=items[characterID] else{return nil}
            return ["png","jpg","jpeg"].map {root.appendingPathComponent("media/"+name+"."+$0)}.first {FileManager.default.fileExists(atPath:$0.path)}
        }
    }
    static func resource(_ name:String,extension ext:String)->URL? {
        guard CharacterDownloadStore.safeRelativePath(name+"."+ext),!name.contains("/") else {return nil}
        return releases.withLock {items in
            items.values.lazy.map {$0.appendingPathComponent("media/"+name+"."+ext)}.first {FileManager.default.fileExists(atPath:$0.path)}
        }
    }
}

enum CharacterDeliveryPolicy {
    private struct Policy:Decodable {let downloadOnly:[String]}
    private static let initial:Set<String> = {
        guard let url=Bundle.main.url(forResource:"CharacterDelivery",withExtension:"json"),
              let value=try? JSONDecoder().decode(Policy.self,from:Data(contentsOf:url)) else{return []}
        return Set(value.downloadOnly)
    }()
    private static let remote=OSAllocatedUnfairLock(initialState:Set<String>())
    static func isRemote(_ id:String)->Bool {initial.contains(id) || remote.withLock {$0.contains(id)}}
    static func setStoreIDs(_ ids:Set<String>){remote.withLock {$0=ids}}
}
