import Foundation

#if !os(iOS)
@main
#endif
struct CompanionExperienceTests {
    @MainActor static func main() throws { print(try run()) }
    @MainActor static func run() throws -> String {
        var checks = 0
        func check(_ condition:@autoclosure ()->Bool,_ name:String) {
            precondition(condition(),name);checks += 1
        }
        let old = CharacterRecord(profile:CharacterProfile(name:"旧伙伴"))
        let encoded = try JSONEncoder().encode(old)
        check(!String(decoding:encoded,as:UTF8.self).contains("experiences"),"old archive shape")
        let decoded = try JSONDecoder().decode(CharacterRecord.self,from:encoded)
        check(decoded.experiences == nil && decoded.together.stories.isEmpty,"old archive compatibility")
        for story in CompanionStory.all {
            func walk(_ nodeID:String,_ path:Set<String>) {
                check(!path.contains(nodeID),"acyclic story")
                guard let node = story.nodes[nodeID] else { preconditionFailure("missing node") }
                check(!node.text.isEmpty,"real chapter text")
                for choice in node.choices {
                    var p=StoryProgress(storyID:story.id);p.nodeID=nodeID
                    let next=StoryEngine.choose(choice.id,nodeID:nodeID,story:story,progress:p,name:"小夏")!
                    check(next.progress.nodeID == choice.next,"choice goes to authored branch")
                    check(next.progress.completed == story.nodes[choice.next]!.choices.isEmpty,"completion state")
                    check(StoryEngine.choose(choice.id,nodeID:nodeID,story:story,progress:next.progress,name:"小夏") == nil,"stale double tap rejected")
                    walk(choice.next,path.union([nodeID]))
                }
            }
            walk("start",[])
        }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("starry-experience-\(UUID())/state.json")
        defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
        let store=CompanionStore(storageURL:url),model=ModelDescriptor.human
        store.activateAccount("experience-A")
        var prefs=TogetherPreferences();prefs.nickname="  小北  ";prefs.responseStyle="一起想办法";prefs.avoidedTopics="加班,前任";prefs.aboutMe="喜欢散步"
        store.saveTogether(prefs,id:model.id)
        check(store.record(model.id).together.preferences.nickname == "小北","preferences normalized")
        check(store.record(ModelDescriptor.miku.id).together.preferences.nickname.isEmpty,"role isolation")
        store.activateAccount("experience-B")
        check(store.record(model.id).together.preferences.nickname.isEmpty,"account isolation")
        store.activateAccount("experience-A")
        let story=CompanionStory.available(for:model)[0]
        check(store.beginStory(story,model:model) != nil,"opening saved")
        check(store.beginStory(story,model:model) == nil && store.record(model.id).messages.count == 1,"resume doesn't duplicate opening")
        check(store.chooseStory("read",nodeID:"start",story:story,model:model) != nil,"first choice")
        check(store.chooseStory("read",nodeID:"start",story:story,model:model) == nil,"duplicate choice not committed")
        let reopened=CompanionStore(storageURL:url);reopened.activateAccount("experience-A")
        check(reopened.record(model.id).together.stories[story.id]?.nodeID == "read","restart retains branch")
        check(reopened.chooseStory("reply",nodeID:"read",story:story,model:model) != nil,"ending committed")
        check(reopened.record(model.id).together.moments.count == 1,"ending creates one journal entry")
        check(reopened.record(model.id).messages.count == 5,"opening plus two real choice/reply pairs")
        reopened.pauseStory(id:model.id)
        check(reopened.record(model.id).together.activeStoryID == nil,"pause retains state")
        check(reopened.record(model.id).together.stories[story.id]?.completed == true,"pause preserves completion")
        let user=CompanionMessage(role:"user",text:"我喜欢安静的海边")
        let candidate=MemoryCandidates.extract(user,record:reopened.record(model.id))!
        reopened.update(model.id) { record in var e=record.together;e.suggestions=[candidate];record.experiences=e }
        check(CompanionContextV1(characterID:model.id,record:reopened.record(model.id)).confirmedMemories.isEmpty,"pending memory excluded from context")
        reopened.reviewMemory(candidate.id,id:model.id,accept:true)
        reopened.reviewMemory(candidate.id,id:model.id,accept:true)
        check(reopened.record(model.id).memories.count == 1,"memory confirmation idempotent")
        check(CompanionContextV1(characterID:model.id,record:reopened.record(model.id)).confirmedMemories == [user.text],"confirmed memory in context")
        check(MemoryCandidates.extract(user,record:reopened.record(model.id)) == nil,"duplicate candidate suppressed")
        check(MemoryCandidates.extract(CompanionMessage(role:"user",text:"我喜欢剧情里的晚霞",storyID:story.id),record:old) == nil,"fiction not inferred as fact")
        check(MemoryCandidates.extract(CompanionMessage(role:"assistant",text:"我喜欢海边"),record:old) == nil,"assistant not a memory source")
        check(MemoryCandidates.extract(CompanionMessage(role:"user",text:"我喜欢加班吗？"),record:old) == nil,"question is not fact")
        let ignoredUser=CompanionMessage(role:"user",text:"我的爱好是看书")
        let ignored=MemoryCandidates.extract(ignoredUser,record:old)!
        reopened.update(model.id) { record in var e=record.together;e.suggestions=[ignored];record.experiences=e }
        reopened.reviewMemory(ignored.id,id:model.id,accept:false)
        check(MemoryCandidates.extract(ignoredUser,record:reopened.record(model.id)) == nil,"ignored source stays ignored")
        let record=reopened.record(model.id)
        check(reopened.dialogue.reply(to:"我不想加班",record:record,variant:0).text.contains("暂时不聊"),"avoid keywords honored")
        check(reopened.dialogue.reply(to:"今天有点累",record:record,variant:0).text.contains("一小步"),"response preference affects reply")
        check(reopened.dialogue.reply(to:"我们的关系",record:record,variant:0).text.hasPrefix("小北"),"nickname affects reply")
        reopened.addMoment(id:model.id,mood:"开心",text:"终于完成今天的画")
        check(reopened.record(model.id).together.moments.count == 2,"journal saved")
        reopened.activateAccount("guest")
        _=reopened.beginStory(story,model:model)
        check(reopened.guestTurns == 0,"story opening doesn't spend guest turn")
        _=reopened.chooseStory("read",nodeID:"start",story:story,model:model)
        check(reopened.guestTurns == 1,"story choice uses existing guest policy")
        check(reopened.record(model.id).memories.isEmpty,"guest isolation")
        return "PASS: \(checks) experience checks (branch graph, migration, persistence, isolation, memory consent, actual replies, guest policy)"
    }
}
