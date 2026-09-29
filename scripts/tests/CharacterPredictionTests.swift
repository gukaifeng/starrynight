import Foundation
@main struct CharacterPredictionTests {
    static func main() {
        var model = CharacterPrediction()
        for id in ["a","b","a","b","c","a"] { model.record(id) }
        precondition(model.next(after:"a",candidates:["b","c"],dialogueCounts:["c":99],recent:[:]) == "b", "observed transition beats fallback")
        precondition(model.next(after:"unknown",candidates:["b","c"],dialogueCounts:["c":99],recent:[:]) == "b", "frequency backoff")
        precondition(model.next(after:"a",candidates:["a"],dialogueCounts:[:],recent:[:]) == nil, "no reload of current actor")
        precondition(model.next(after:"a",candidates:["c"],dialogueCounts:[:],recent:[:]) == "c", "resolver enforces eligible candidates")
        let cold = CharacterPrediction()
        precondition(cold.next(after:nil,candidates:["b","c"],dialogueCounts:["c":8],recent:[:]) == "c", "cold history backoff")
        let saved = try! JSONEncoder().encode(model.visits)
        let reloaded = CharacterPrediction(visits:try! JSONDecoder().decode([CharacterPrediction.Visit].self,from:saved))
        precondition(reloaded.next(after:"a",candidates:["b","c"],dialogueCounts:[:],recent:[:]) == "b")
        model.record("expired",now:Date().addingTimeInterval(-31*86400));model.record("fresh")
        precondition(!model.visits.contains { $0.id == "expired" })
        for i in 0..<400 { model.record(String(i)) };precondition(model.visits.count == 256)
        print("PASS: Markov transition, frequency, dialogue backoff, current-role exclusion, visibility filtering, persistence, expiry and bounded history (8 checks)")
    }
}
