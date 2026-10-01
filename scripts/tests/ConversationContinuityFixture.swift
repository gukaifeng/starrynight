#if DEBUG && targetEnvironment(simulator)
import Foundation

/// A delayed transport, not a replacement session: production turn ownership,
/// storage, reply reveal and tab/window lifecycle all run unmodified in tests.
@MainActor enum ConversationContinuityFixture {
    static var enabled:Bool {
        let args=ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--conversation-continuity-fixture") && !args.contains("--live-ai")
    }
    static func events(characterID:String,body:[String:Any]?,consume:(AIEvent) async throws -> Void) async throws {
        let prompt=body?["text"] as? String ?? ""
        try await Task.sleep(for:.seconds(prompt=="Wait" ? 14 : 2))
        try Task.checkCancellation()
        let id=UUID().uuidString
        let text=prompt=="Wait" ? "切页之后，我把刚才的话接着说完了。" : "这份接话已经收到，我们继续聊。"
        let script=AIScript(messageId:id,characterId:characterID,text:text,beats:[
            AIBeat(beatId:"continuity",dialogue:AIDialogue(text:text),narrations:[],visuals:[],readingDuration:0.4)
        ])
        try await consume(AIEvent(type:"reply.narration.ready",script:script))
        try await consume(AIEvent(type:"segment.audio.started",beatId:"continuity"))
        var pcm=Data()
        for frame in 0..<9600 {
            var sample=Int16(sin(Double(frame)*2*Double.pi*220/24000)*800).littleEndian
            withUnsafeBytes(of:&sample) {pcm.append(contentsOf:$0)}
        }
        try await consume(AIEvent(type:"segment.audio.chunk",data:pcm.base64EncodedString()))
        try await consume(AIEvent(type:"segment.audio.ready",beatId:"continuity"))
        try await consume(AIEvent(type:"audio.completed"))
        try await consume(AIEvent(type:"reply.completed"))
    }
}
#endif
