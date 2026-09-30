#if DEBUG && targetEnvironment(simulator)
import Foundation

enum ConversationGestureFixture {
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
