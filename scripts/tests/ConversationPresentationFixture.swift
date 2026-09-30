#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Isolated UI fixture: real chat view and persistence, no Unity or AI request.
/// This source is included only in the simulator project.
struct ConversationPresentationFixture: View {
    @State private var session: CompanionSession
    @State private var contentCheck = ""
    init() {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("presentation-"+UUID().uuidString)
        let store=CompanionStore(storageURL:folder.appendingPathComponent("journal.json"),arguments:[])
        let model=ModelDescriptor.all.first!
        store.update(model.id) { record in
            record.messages=(0..<80).map { CompanionMessage(role:$0.isMultiple(of:2) ? "assistant" : "user",text:"历史消息 \($0)：这是一段用于检查滚动和渐变的文字。") }
        }
        _session=State(initialValue:CompanionSession(store:store,model:model,soundscape:CompanionSoundscape()))
    }
    var body: some View {
        VStack(spacing:12) {
            Text("对话呈现检查").font(.headline)
            HStack {
                Button("历史开头") { if let first=session.record.messages.first {session.focusMessage(first.id)} }
                    .accessibilityIdentifier("fixtureHistory")
                Button("新增我的消息") {
                    session.store.update(session.model.id) {$0.messages.append(CompanionMessage(role:"user",text:"新发送的消息"))}
                }.accessibilityIdentifier("fixtureUser")
                Button("新增AI回复") { appendAI() }.accessibilityIdentifier("fixtureAI")
            }.font(.caption)
            Button("补充旁白") { enrich() }.accessibilityIdentifier("fixtureNarration")
            Text(contentCheck).font(.caption2).accessibilityIdentifier("presentationContentResult")
            Spacer(minLength:0)
            CompanionChatView(session:session).frame(height:400)
        }.padding(.top,24).padding(.bottom,12).background(Theme.background)
            .foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
    private func appendAI() {
        let id=UUID()
        let beat=AIBeat(beatId:"b",thought:"我也想听听后面的故事。",dialogue:AIDialogue(text:"后来发生了什么？"),narrations:[],visuals:[])
        let script=AIScript(messageId:id.uuidString,characterId:session.model.id,text:"后来发生了什么？",beats:[beat])
        session.store.update(session.model.id) {$0.messages.append(CompanionMessage(id:id,role:"assistant",text:script.text,aiScript:script,source:"cloud-v1"))}
    }
    private func enrich() {
        session.store.update(session.model.id) { record in
            guard let index=record.messages.lastIndex(where:{$0.aiScript != nil}) else {return}
            let before=record.messages[index].visibleContentKey
            record.messages[index].speechDuration=8
            let audioStable=before==record.messages[index].visibleContentKey
            record.messages[index].aiScript?.beats[0].narrations=[AINarration(text:"片刻停顿，让对话柔和下来。",mode:"literary",grounding:"none")]
            let changed=before != record.messages[index].visibleContentKey
            contentCheck=audioStable && changed ? "PASS: audio metadata stays still; narration triggers following" : "FAIL: visible content key"
        }
    }
}
#endif
