import Foundation

@main struct CharacterActionMenuTests {
    @MainActor static func main() throws {
        struct Catalog: Decodable { let characters: [ModelDescriptor] }
        let data = try Data(contentsOf:URL(fileURLWithPath:"ios/CharacterHost/Resources/CharacterCatalog.json"))
        let models = try JSONDecoder().decode(Catalog.self,from:data).characters
        var checks = 0
        func check(_ condition:Bool,_ description:String) { precondition(condition,description); checks += 1 }
        func actions(_ id:String,_ pose:String = "stand") -> [String] {
            models.first { $0.id == id }!.availableActions(for:PosturePreferences(id:pose)).map(\.id)
        }
        check(actions("real-woman") == ["Wave","Bow","Greet"],"Standing human offers authored button actions")
        check(actions("real-woman","sit") == ["Wave","Greet"],"Sitting must hide the standing bow")
        check(actions("real-woman","crouch") == ["Wave","Greet"],"Crouching must hide the standing bow")
        check(actions("real-woman","lie").isEmpty,"Lying must not offer unsafe standing clips")
        check(actions("real-woman","removed-pose") == actions("real-woman"),"Stale preferences use normalized standing pose")
        check(actions("studio-robot","sit") == ["Wave","Jump","Dance"],"Legacy packages without postures keep authored actions")
        check(actions("hatsune-miku") == ["Wave","Jump","Dance","Bow","Spin","Greet","Cheer"],"Miku keeps all seven actions")
        check(actions("sample-robot") == ["Wave","Jump","Dance","Yes","ThumbsUp"],"Independent package controls stay data driven")
        check(actions("sample-robot","sit").isEmpty,"Unsupported gestures cannot leak into sitting mode")
        for model in models {
            check(!model.actions.contains { $0.id == "No" || $0.id == "Idle" },"Non-button head interaction and idle remain folded out")
        }
        let port = CharacterSignalPort()
        let payload = port.payload(CharacterIntent(eventName:"action.request",target:"ThumbsUp"),actorId:"sample-robot")
        check(payload["actorId"] as? String == "sample-robot","Manual request targets selected actor")
        check(payload["eventName"] as? String == "action.request" && payload["target"] as? String == "ThumbsUp","Manual request uses the existing semantic contract")
        check(payload["turnId"] as? String == "","Manual action does not cancel or create a conversation turn")
        print("PASS: \(checks) character action menu / posture / signal contract checks")
    }
}
