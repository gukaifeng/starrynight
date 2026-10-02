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
    var stage:String {
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
        relationship=record.together.preferences.normalized.relationship
        self.nickname=TogetherPreferences.cleanNickname(nickname)
        resetPending=record.pendingDeletionID != nil
    }
}
