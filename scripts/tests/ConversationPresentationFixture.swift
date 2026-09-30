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
            let id=UUID()
            let beat=AIBeat(beatId:"old",thought:"轻唤昵称，延续晨光庭院的宁静氛围，并自然引出书籍或日常话题的分享邀请。",
                            dialogue:AIDialogue(text:"你回来啦。"),narrations:[],visuals:[])
            let script=AIScript(messageId:id.uuidString,characterId:model.id,text:"你回来啦。",beats:[beat])
            record.messages.append(CompanionMessage(id:id,role:"assistant",text:script.text,aiScript:script,source:"cloud-v1"))
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
            HStack {
                Button("开始加载") { session.generating = true }.accessibilityIdentifier("fixtureLoading")
                Button("逐段增长") { growReply() }.accessibilityIdentifier("fixtureGrowth")
            }.font(.caption)
            Text(contentCheck).font(.caption2).accessibilityIdentifier("presentationContentResult")
            Spacer(minLength:0)
            CompanionChatView(session:session).frame(height:400)
        }.padding(.top,24).padding(.bottom,12).background(Theme.background)
            .foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
    private func growReply() {
        session.generating = false
        let id=UUID()
        session.store.update(session.model.id) { $0.messages.append(CompanionMessage(id:id,role:"assistant",text:"逐段回复")) }
        Task { @MainActor in
            for count in 1...8 {
                try? await Task.sleep(for:.milliseconds(220))
                session.store.update(session.model.id) { record in
                    guard let index=record.messages.firstIndex(where:{$0.id==id}) else { return }
                    record.messages[index].text=(1...count).map { "第\($0)段：内容逐渐展开，实际高度变化后也应保持在消息的末尾。" }.joined(separator:"\n")
                }
            }
            contentCheck = "growth-complete"
        }
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
            // Also exercise the native guard's positive and first-person
            // planning cases; old persisted dialogue remains untouched.
            var probe=record.messages[index].aiScript!.beats[0]
            probe.thought="我需要延续宁静的氛围，并自然引出书籍话题。"
            let planningHidden=probe.visibleThought == nil
            probe.thought="我很喜欢你给我的昵称。"
            let feelingPreserved=probe.visibleThought == probe.thought
            contentCheck=audioStable && changed && planningHidden && feelingPreserved ? "PASS: audio metadata stays still; narration triggers following; planning stays hidden" : "FAIL: content presentation"
        }
    }
}
#endif
