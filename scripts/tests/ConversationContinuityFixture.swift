#if DEBUG && targetEnvironment(simulator)
import Foundation

/// A delayed transport, not a replacement session: production turn ownership,
/// storage, reply reveal and tab/window lifecycle all run unmodified in tests.
@MainActor enum ConversationContinuityFixture {
    static var enabled:Bool {
        let args=ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && (args.contains("--conversation-continuity-fixture") || args.contains("--resilient-reply-fixture")) && !args.contains("--live-ai")
    }
    private static var attempts:[String:Int]=[:]
    static func events(characterID:String,body:[String:Any]?,consume:(AIEvent) async throws -> Void) async throws {
        let prompt=body?["text"] as? String ?? ""
        if ProcessInfo.processInfo.arguments.contains("--resilient-reply-fixture"),!prompt.isEmpty {
            let id=body?["request_id"] as? String ?? "missing"
            attempts[id,default:0]+=1
            let failCount=prompt=="111" ? 1 : 3
            if attempts[id,default:0]<=failCount {throw AIConnectionError.remote("SERVER_BUSY")}
        }
        try await Task.sleep(for:.seconds(prompt=="Wait" ? 14 : 2))
        try Task.checkCancellation()
        let id=UUID().uuidString
        let text=prompt=="Wait" ? "切页之后，我把刚才的话接着说完了。" : "这份接话已经收到，我们继续聊。"
        var script=AIScript(messageId:id,characterId:characterID,text:text,beats:[
            AIBeat(beatId:"continuity",dialogue:AIDialogue(text:text),narrations:[],visuals:[],parts:[
                AIReplyPart(kind:"thought",text:"我想接着听你说。",at:0),
                AIReplyPart(kind:"narration",text:"轻轻点头",at:1),
                AIReplyPart(kind:"dialogue",text:text,at:0)
            ],readingDuration:0.4)
        ])
        if prompt=="111" {script.beats[0].parts?.removeAll {$0.kind=="dialogue"}}
        try await consume(AIEvent(type:"reply.narration.ready",script:script))
        try await consume(AIEvent(type:"segment.audio.started",beatId:"continuity"))
        var pcm=Data()
        for frame in 0..<(prompt=="111" ? 96000 : 9600) {
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
