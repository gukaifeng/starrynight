#if DEBUG && targetEnvironment(simulator)
import Foundation

enum ConversationGestureFixture {
    @MainActor static func seedPerformance(_ store:CompanionStore) {
        let model=ModelDescriptor.defaultCharacter
        guard let profile=model.performance else {return}
        var visuals:[AIVisual]=[]
        for group in ["expression","hands","ears","tail"] {
            let choices=profile.options.filter {$0.group==group && !$0.isToggle && $0.defaultOn != true && !$0.label.contains("自然") && !$0.label.contains("固定嘴型")}
            for (index,option) in choices.prefix(2).enumerated() {
                visuals.append(AIVisual(assetId:option.id,group:group,durationMs:3500,grounding:"exact",offsetMs:index*2400,active:true))
            }
        }
        let id=UUID(),text="你来啦，今天也想和你多聊一会儿。"
        let beat=AIBeat(beatId:"expressive",thought:"我想让你看见我的小心情。",dialogue:AIDialogue(text:text),
            narrations:[AINarration(text:"露出开心的神情。",mode:"performed",grounding:"exact"),AINarration(text:"她有一双圆圆的眼睛。",mode:"literary",grounding:"none")],visuals:visuals)
        store.update(model.id) {$0.messages=[CompanionMessage(id:id,role:"assistant",text:text,
            aiScript:AIScript(messageId:id.uuidString,characterId:model.id,text:text,beats:[beat]),source:"cloud-v1")]}
    }
    @MainActor static func seed(_ store:CompanionStore) {
        store.update(ModelDescriptor.defaultCharacter.id) { record in
            record.messages=(0..<80).map { index in
                CompanionMessage(role:index.isMultiple(of:2) ? "user" : "assistant",
                    text:index == 78 ? "手势测试：最后一条用户消息" : index == 79 ? "手势测试：最后一条角色消息，可以在这段文字上拖动。" : "手势测试记录 \(index)：沿着文字上下滑动，查看我们的聊天记录。")
            }
        }
    }
}
#endif
