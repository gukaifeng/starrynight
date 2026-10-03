import Foundation

#if !os(iOS)
@main
#endif
struct CharacterModelReviewTests {
    @MainActor static func main() throws { print(try run()) }
    @MainActor static func run() throws -> String {
        var checks=0
        func check(_ pass:Bool,_ message:String) {precondition(pass,message);checks+=1}
        let suite="starry.model-review-test."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        defaults.set(true,forKey:"starry.character-model-review.v1")
        CharacterModelReview.configure(defaults:defaults)
        check(!defaults.bool(forKey:"starry.character-model-review.v1"),"Obsolete global preview is cleared")
        var authenticationCalls=0
        CharacterAI.authenticatedRequest={_,_ in authenticationCalls+=1;return URLRequest(url:URL(string:"https://example.invalid")!)}
        defer {CharacterAI.authenticatedRequest=nil}
        let previews=ModelDescriptor.all.filter(\.isPreviewOnly)
        let full=ModelDescriptor.all.filter {!$0.isPreviewOnly}
        check(!ModelDescriptor.all.contains {$0.id=="anime-kipfel-v111"},"Duplicate new cat preview is retired")
        let expected=["chiffon":"Chiffon","fiona":"Fiona","hikarun":"Hikarun","ichigo":"Ichigo","koharu":"Koharu","lime":"Lime","mafuyu":"Mafuyu","meiyun":"Meiyun","milfy":"Milfy","mao":"Mao","mizuki":"Mizuki","perula":"Perula","plum":"Plum","ramune":"Ramune","shinano":"Shinano","sio":"Sio"]
        check(Set(ModelDescriptor.all.map(\.id))==Set(expected.keys.map {"anime-"+$0}),"Exactly the selected sixteen roles are bundled")
        check(full.count==16 && previews.isEmpty,"All sixteen selected models are complete companions")
        check(ModelDescriptor.defaultCharacter.id=="anime-chiffon","Default character is in the selected roster")
        for model in ModelDescriptor.all {check(model.display.name==expected[String(model.id.dropFirst(6))],"Original character name is used")}
        check(!full.isEmpty,"Complete characters remain available")
        for model in previews {
            let api=CharacterAI(accountID:"review",characterID:model.id)
            for path in ["/v1/status","/v1/reactions/prepare","/v1/tts","/v1/asr"] {
                do {_ = try api.request(path,paid:false);preconditionFailure("Preview unexpectedly constructed a service request")}
                catch AIConnectionError.testingDisabled {checks+=1}
            }
        }
        check(authenticationCalls==0,"Preview requests stop before account/network routing")
        for model in full {
            _ = try CharacterAI(accountID:"review",characterID:model.id).request("/v1/status",paid:false)
        }
        check(authenticationCalls==full.count,"Complete characters retain request routing; no request is sent")
        for model in ModelDescriptor.all {
            check(model.isPreviewOnly == (model.collection.previewOnly == true),"Preview is per character")
            let hasSpeech=model.supports("core.speech.amplitude@1") || model.supports("core.speech.viseme@1")
            check(model.isPreviewOnly ? !hasSpeech : hasSpeech,"Complete speech capabilities are retained")
            var personal=CharacterProfile.initial(model.id)
            personal.name="旧名字"
            personal.autoSpeak=true;personal.audio=CharacterAudioPreferences(trackID:model.collection.defaultMusic)
            personal.audio?.volume=0.7;personal.audio?.speechVolume=0.8
            let profile=model.conversationProfile(preserving:personal)
            check(profile.name==expected[String(model.id.dropFirst(6))],"Stored old names do not replace the current source identity")
            if model.isPreviewOnly {
                check(!profile.autoSpeak && profile.audio?.volume==0 && profile.audio?.speechVolume==0,"Preview silences music and speech")
            } else {
                check(profile.autoSpeak && profile.audio?.volume==0.7 && profile.audio?.speechVolume==0.8,"Complete characters preserve speech and music preferences")
            }
            check(personal.autoSpeak && personal.audio?.volume==0.7,"Normalization preserves original stored preferences")
        }
        return "PASS: \(checks) checks; \(full.count) complete conversation characters, \(previews.count) local previews; preview requests blocked, complete routing retained"
    }
}
