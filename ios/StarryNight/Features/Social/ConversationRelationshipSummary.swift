import Foundation

/// A view of the available journal, never an inferred emotional score.
struct ConversationRelationshipSummary {
    let messageCount:Int
    let userTurns:Int
    let activeDays:Int
    let daysSinceMeeting:Int
    let firstDate:Date?
    let lastMessage:CompanionMessage?
    let memories:[CompanionMemory]
    let relationship:String
    let nickname:String
    let resetPending:Bool
    let goalStage:String?
    var stage:String {
        if let goalStage {return goalStage}
        if userTurns == 0 { return "初次相遇" }
        if userTurns < 5 { return "开始靠近" }
        if userTurns < 20 { return "渐渐熟悉" }
        if activeDays < 7 { return "相伴日常" }
        return "故事渐深"
    }
    init(record:CharacterRecord,nickname:String,now:Date=Date(),calendar:Calendar = .current) {
        let messages=record.messages.filter {
            ["user","assistant"].contains($0.role) && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        }.sorted { $0.date < $1.date }
        messageCount=messages.count
        userTurns=messages.filter { $0.role == "user" }.count
        activeDays=Set(messages.map {calendar.startOfDay(for:$0.date)}).count
        firstDate=messages.first?.date;lastMessage=messages.last
        if let firstDate {
            daysSinceMeeting=max(1,(calendar.dateComponents([.day],from:calendar.startOfDay(for:firstDate),
                to:calendar.startOfDay(for:now)).day ?? 0)+1)
        } else {daysSinceMeeting=0}
        memories=record.memories.sorted {$0.date > $1.date}
        if let goals=record.together.goals {
            let labels=["strangers":"初识","pursuit":"追求","flirting":"暧昧","lovers":"恋人","friends":"朋友","mentor":"师徒","rivals":"宿敌","childhood":"青梅竹马"]
            relationship=goals.config.confirmedCouple ? "恋人" : (labels[goals.config.initialRelation] ?? "朋友")
            goalStage=goals.config.paused ? "慢慢相处" : goals.config.mode=="task" ? "一起成长" :
                goals.config.mode=="sandbox" ? "随心相处" : goals.config.confirmedCouple || goals.config.initialRelation=="lovers" ? "情侣日常" :
                (goals.bond?.affection ?? 0)>=0.45 && goals.config.longTerm=="romance" ? "心意渐近" : "慢慢了解彼此"
        } else {relationship=record.together.preferences.normalized.relationship;goalStage=nil}
        self.nickname=TogetherPreferences.cleanNickname(nickname)
        resetPending=record.pendingDeletionID != nil
    }
}
