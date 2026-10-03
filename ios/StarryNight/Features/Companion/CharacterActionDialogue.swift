import Foundation

// Local dialogue adapter: resolve meanings through this role's declared actions,
// never through another character's clips. An online provider can emit the same
// action.request event later without changing the model package.
enum CharacterActionDialogue {
    struct Request { let actionID:String?; let reply:String }
    static func parse(_ text:String,model:ModelDescriptor,posture:PosturePreferences) -> Request? {
        guard !["不要","不用","别"].contains(where:text.contains) else { return nil }
        let entries:[(keywords:[String],semantic:String,reply:String)] = [
            (["摇摇头","摇头"],"disagreement","好，轻轻摇摇头，像这样。"),
            (["点点头","点头"],"agreement","嗯，我在认真听。"),
            (["侧耳","倾听一下"],"listening","我在这儿，慢慢说给我听吧。"),
            (["想一想","思考一下"],"thinking","让我稍微想一想，我们不用着急。"),
            (["轻声讲述","说话动作"],"speaking","好呀，就这样，轻轻地和你说一会儿话。"),
            (["放松一下","伸懒腰"],"relaxed","一起松一口气，慢一点也很好。"),
            (["抬手","招手","挥手"],"greeting","嗨，我在这里。"),
            (["认真回应"],"gratitude","谢谢你告诉我，我记在心里了。")
        ]
        guard let entry = entries.first(where:{ $0.keywords.contains(where:text.contains) }) else { return nil }
        guard let action = model.availableActions(for:posture).first(where:{ $0.semantic == entry.semantic }) else {
            return Request(actionID:nil,reply:"这个动作我现在还不会，不过我可以继续陪你聊。")
        }
        return Request(actionID:action.id,reply:entry.reply)
    }
}
