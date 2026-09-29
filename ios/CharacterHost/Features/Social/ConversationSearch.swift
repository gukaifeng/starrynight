import Foundation

struct ConversationSearchHit:Identifiable {
    let characterID:String
    let message:CompanionMessage
    let excerpt:String
    var id:String { characterID + ":" + message.id.uuidString }
}

/// Call with the active account's records and currently accessible character IDs.
/// Search saved text, never another identity's archive or just the character's name.
enum ConversationSearch {
    static func find(_ query:String,records:[String:CharacterRecord],visibleIDs:Set<String>) -> [ConversationSearchHit] {
        let words = query.split(whereSeparator:{ $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        let options:String.CompareOptions = [.caseInsensitive,.diacriticInsensitive,.widthInsensitive]
        return records.filter { visibleIDs.contains($0.key) }.flatMap { id,record in
            record.messages.compactMap { message -> ConversationSearchHit? in
                guard words.allSatisfy({ message.text.range(of:$0,options:options) != nil }),
                      let match = message.text.range(of:words[0],options:options) else { return nil }
                let start = message.text.index(match.lowerBound,offsetBy:-18,limitedBy:message.text.startIndex) ?? message.text.startIndex
                let end = message.text.index(match.upperBound,offsetBy:64,limitedBy:message.text.endIndex) ?? message.text.endIndex
                let excerpt = (start > message.text.startIndex ? "…" : "") + message.text[start..<end] + (end < message.text.endIndex ? "…" : "")
                return ConversationSearchHit(characterID:id,message:message,excerpt:excerpt)
            }
        }.sorted {
            $0.message.date == $1.message.date ? $0.id < $1.id : $0.message.date > $1.message.date
        }
    }

    /// Bound layout work even when a search opens a message outside the last 60.
    static func window(_ messages:[CompanionMessage],around id:UUID?) -> [CompanionMessage] {
        guard let id, let index = messages.firstIndex(where:{ $0.id == id }) else { return Array(messages.suffix(60)) }
        let start = max(0,min(index-12,messages.count-60))
        return Array(messages.dropFirst(start).prefix(60))
    }
}
