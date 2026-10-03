import Foundation

#if !os(iOS)
@main
#endif
struct CharacterAudioUpgradeTests {
    @MainActor static func main() throws {print(try run())}
    @MainActor static func run() throws -> String {
        var checks=0
        func check(_ result:Bool,_ message:String) {precondition(result,message);checks+=1}
        check(ModelDescriptor.all.count == 16,"The active roster has sixteen full companions")
        for model in ModelDescriptor.all {
            check(!model.isPreviewOnly,"Every active character supports conversation")
            let initial=model.conversationProfile(preserving:nil)
            check(initial.autoSpeak && initial.audio?.speechVolume == 1,"New companions start with an audible voice")
            check(initial.audio?.volume == 0.28 && initial.audio?.volumeControlsVersion == 2,"New companions have the current sound defaults")
            var preview=initial
            preview.autoSpeak=false
            preview.audio=CharacterAudioPreferences(trackID:"",volume:0,speechVolume:0,volumeControlsVersion:1)
            let upgraded=model.conversationProfile(preserving:preview)
            check(upgraded.autoSpeak && upgraded.audio?.speechVolume == 1 && upgraded.audio?.volume == 0.28,"Forced legacy preview silence is removed")
            check(upgraded.audio?.trackID == model.collection.defaultMusic,"The restored track belongs to this character")
            check(model.conversationProfile(preserving:upgraded)==upgraded,"Upgrade is idempotent")
            var partiallyRaised=preview;partiallyRaised.audio?.speechVolume=0.56
            let partial=model.conversationProfile(preserving:partiallyRaised)
            check(partial.audio?.speechVolume == 0.56 && partial.audio?.volume == 0.28,"An old preview with manually raised voice keeps that choice and recovers its forced-silent music")
            var legacy=initial
            legacy.audio=CharacterAudioPreferences(trackID:model.collection.defaultMusic,volume:0.19,speechVolume:0,volumeControlsVersion:1)
            let migrated=model.conversationProfile(preserving:legacy)
            check(migrated.audio?.speechVolume == 1 && migrated.audio?.volume == 0.19,"One-time legacy zero repair preserves the music volume")
            var muted=upgraded;muted.audio?.speechVolume=0;muted.audio?.volume=0
            let data=try JSONEncoder().encode(muted)
            let reloaded=try JSONDecoder().decode(CharacterProfile.self,from:data)
            let kept=model.conversationProfile(preserving:reloaded)
            check(kept.audio?.speechVolume == 0 && kept.audio?.volume == 0,"A deliberate current mute persists through normalization and restart")
            var forced=muted;forced.audio?.previewSilenced=true
            check(model.conversationProfile(preserving:forced).audio?.speechVolume == 1,"Explicit preview provenance can activate a future full companion")
            // Simulate the old cached collection rather than mutating source assets.
            var wire=try JSONSerialization.jsonObject(with:JSONEncoder().encode(model.collection)) as! [String:Any]
            wire["previewOnly"]=true;wire["music"]=[];wire["defaultMusic"]="";wire["version"]="1.0.0"
            let old=try JSONDecoder().decode(CharacterCollection.self,from:JSONSerialization.data(withJSONObject:wire))
            var cached=model;cached.collectionSnapshot=old
            check(!cached.isPreviewOnly && cached.collection.voices==model.collection.voices,"An obsolete store snapshot cannot downgrade a full companion")
            let instance=cached.instance(id:"private-"+model.id,collection:old)
            check(!instance.isPreviewOnly && instance.collection.voices.allSatisfy {$0.id.hasPrefix(instance.id+"/")},"Created-role upgrades preserve their private option namespace")
        }
        return "PASS: \(checks) checks; 16 audible defaults, legacy preview activation, one-time mute repair, persistent explicit mute, cached and scoped upgrades"
    }
}
