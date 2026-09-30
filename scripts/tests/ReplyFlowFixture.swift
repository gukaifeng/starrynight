#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Synthetic audio, real chat renderer and playback-driven reveal; never calls AI.
struct ReplyFlowFixture:View {
    @State private var session:CompanionSession
    @State private var result=""
    private let script:AIScript
    private let id=UUID()
    init() {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("reply-flow-"+UUID().uuidString)
        let store=CompanionStore(storageURL:root.appendingPathComponent("journal.json"),arguments:[])
        let model=ModelDescriptor.all.first!
        let sounds=CompanionSoundscape();sounds.setVolume(0);sounds.setActive(true)
        _session=State(initialValue:CompanionSession(store:store,model:model,soundscape:sounds))
        script=AIScript(messageId:id.uuidString,characterId:model.id,text:"我在听。你愿意接着讲吗？慢慢说就好。",beats:[
            AIBeat(beatId:"flow",dialogue:AIDialogue(text:"我在听。你愿意接着讲吗？慢慢说就好。"),narrations:[],visuals:[],parts:[
                AIReplyPart(kind:"dialogue",text:"我在听。",at:0),
                AIReplyPart(kind:"thought",text:"我有点期待呢。",at:0.33),
                AIReplyPart(kind:"dialogue",text:"你愿意接着讲吗？",at:0.33),
                AIReplyPart(kind:"narration",text:"轻轻微笑。",at:0.67),
                AIReplyPart(kind:"dialogue",text:"慢慢说就好。",at:0.67)
            ],readingDuration:6)])
    }
    var body:some View {
        VStack {
            Button("播放阶段检查") {play()}.accessibilityIdentifier("startReplyFlow")
            Text(result).accessibilityIdentifier("replyFlowResult")
            Spacer()
            CompanionChatView(session:session).frame(height:460)
        }.padding(.top,20).background(Theme.background).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
    private func play() {
        session.store.update(session.model.id) {$0.messages=[CompanionMessage(id:id,role:"assistant",text:script.text,aiScript:script,source:"cloud-v1")]}
        session.replyReveal.begin(id,script:script)
        Task { @MainActor in
            do {
                var pcm=Data()
                for frame in 0..<144000 {
                    var value=Int16(sin(Double(frame)*2*Double.pi*220/24000)*900).littleEndian
                    withUnsafeBytes(of:&value) {pcm.append(contentsOf:$0)}
                }
                session.speech.prepare(id,script:script)
                try await session.speech.accept(AIEvent(type:"segment.audio.started",beatId:"flow"))
                for start in stride(from:0,to:pcm.count,by:12000) {
                    try await session.speech.accept(AIEvent(type:"segment.audio.chunk",data:Data(pcm.dropFirst(start).prefix(12000)).base64EncodedString()))
                }
                try await session.speech.accept(AIEvent(type:"segment.audio.ready",beatId:"flow"))
                let complete=session.replyReveal.count(id,beat:"flow")==5
                session.speech.finish();session.replyReveal.finish()
                result=complete ? "PASS: parts revealed during real PCM playback" : "FAIL: incomplete reveal"
            } catch {result="FAIL: "+error.localizedDescription}
        }
    }
}
#endif
