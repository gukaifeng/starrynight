#if DEBUG && targetEnvironment(simulator)
import Foundation

@MainActor enum MessageConversationFixture {
    static var enabled:Bool {
        let args=ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--conversation-card-fixture") && !args.contains("--live-ai")
    }
    static func seed(_ store:CompanionStore) {
        guard enabled,!ProcessInfo.processInfo.arguments.contains("--keep-companion-data") else {return}
        let calendar=Calendar.current
        let today=calendar.startOfDay(for:Date())
        store.update("anime-kipfel") { record in
            record.messages=[]
            for index in 0..<8 {
                let date=calendar.date(byAdding:.day,value:-2+index/3,to:today)!.addingTimeInterval(Double(36000+index*120))
                record.messages.append(CompanionMessage(role:"user",text:"这是我们聊过的第 \(index+1) 件小事。",date:date,source:"cloud-v1"))
                record.messages.append(CompanionMessage(role:"assistant",text:index==7 ? "今晚还能一起听一会儿风铃吗？" : "我记得你说的这件小事。",date:date.addingTimeInterval(20),source:"cloud-v1"))
            }
            record.memories=[CompanionMemory(text:"你喜欢雨天的风铃声。",date:today),CompanionMemory(text:"你希望我叫你小星。",date:today.addingTimeInterval(10))]
            record.experiences=CompanionExperiences(preferences:TogetherPreferences(nickname:"小星",relationship:"知己"))
        }
        let record=store.record("anime-kipfel")
        let summary=ConversationRelationshipSummary(record:record,nickname:store.effectiveNickname(for:"anime-kipfel"))
        precondition(summary.messageCount==16 && summary.userTurns==8 && summary.activeDays==3 && summary.daysSinceMeeting==3)
        precondition(summary.relationship=="知己" && summary.nickname=="小星" && summary.memories.count==2)
        // Unordered messages and incomplete typing placeholders cannot corrupt
        // the first/last dates or increase the bond's activity counts.
        var unordered=record;unordered.messages.reverse()
        unordered.messages.append(CompanionMessage(role:"assistant",text:"  \n",date:today.addingTimeInterval(90000)))
        let reordered=ConversationRelationshipSummary(record:unordered,nickname:"",now:Date())
        precondition(reordered.userTurns==8 && reordered.messageCount==16 && reordered.lastMessage?.text==summary.lastMessage?.text)
    }
    static func resetReceipt(_ id:String) async throws -> ConversationResetReceipt {
        try await Task.sleep(for:.milliseconds(240))
        if ProcessInfo.processInfo.arguments.contains("--conversation-reset-failure") {throw URLError(.notConnectedToInternet)}
        return ConversationResetReceipt(resetID:id,version:1)
    }
}
#endif
