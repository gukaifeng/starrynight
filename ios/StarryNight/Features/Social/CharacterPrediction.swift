import Foundation

/// First-order Markov next-access prediction (Joseph & Grunwald, ISCA 1997).
/// No trained model or network. A bounded recent history adapts to changing habits;
/// unseen transitions back off to observed access frequency, then conversation history.
struct CharacterPrediction {
    struct Visit: Codable { let id: String; let date: Date }
    var visits: [Visit] = []
    mutating func record(_ id: String, now: Date = Date()) {
        visits.removeAll { now.timeIntervalSince($0.date) > 30*86400 }
        guard visits.last?.id != id else { return }
        visits.append(Visit(id:id,date:now))
        visits = Array(visits.suffix(256))
    }
    func next(after current: String?, candidates: [String], dialogueCounts: [String:Int], recent: [String:Date]) -> String? {
        let allowed = Set(candidates).subtracting(current.map { [$0] } ?? [])
        guard !allowed.isEmpty else { return nil }
        var transitions: [String:Int] = [:], frequency: [String:Int] = [:]
        let fresh = visits.filter { Date().timeIntervalSince($0.date) <= 30*86400 }
        for (index,visit) in fresh.enumerated() {
            frequency[visit.id,default:0] += 1
            if index > 0, fresh[index-1].id == current { transitions[visit.id,default:0] += 1 }
        }
        // Lexicographic backoff, not arbitrary blended weights. The transition counts
        // have a common denominator and therefore rank exactly like P(next|current).
        return allowed.sorted { a,b in
            let lhs = [transitions[a,default:0],frequency[a,default:0],dialogueCounts[a,default:0]]
            let rhs = [transitions[b,default:0],frequency[b,default:0],dialogueCounts[b,default:0]]
            if lhs != rhs { return rhs.lexicographicallyPrecedes(lhs) }
            let da = recent[a] ?? .distantPast, db = recent[b] ?? .distantPast
            if da != db { return da > db }
            return a < b
        }.first
    }
}
