import Foundation

extension CompanionStore {
    func saveTogether(_ value:TogetherPreferences,id:String) {
        let normalized = value.normalized
        guard normalized != record(id).together.preferences else { return }
        update(id) { record in
            var experience = record.together; experience.preferences = normalized; record.experiences = experience
        }
    }
    func reviewMemory(_ candidateID:UUID,id:String,accept:Bool) {
        guard let suggestion = record(id).together.suggestions.first(where:{ $0.id == candidateID }) else { return }
        update(id) { record in
            var experience = record.together
            if accept && !record.memories.contains(where:{ $0.text == suggestion.text }) {
                record.memories.append(CompanionMemory(text:suggestion.text))
            }
            experience.suggestions.removeAll { $0.id == candidateID }
            experience.reviewedMemorySources = Array((experience.reviewedMemorySources + [suggestion.sourceMessageID]).suffix(1000))
            record.experiences = experience
        }
    }
    func addMoment(id:String,mood:String,text:String) {
        let clean = String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300))
        guard ["平静","开心","有点累","低落"].contains(mood) else { return }
        update(id) { record in
            var experience = record.together
            experience.moments.append(TogetherMoment(kind:"checkin",title:mood,text:clean.isEmpty ? "今天的心情，留在这里。" : clean))
            experience.moments = Array(experience.moments.suffix(200)); record.experiences = experience
        }
    }
    func removeMoment(_ momentID:UUID,id:String) {
        update(id) { record in
            var experience = record.together; experience.moments.removeAll { $0.id == momentID }; record.experiences = experience
        }
    }
    func pauseStory(id:String) {
        update(id) { record in
            var experience = record.together; experience.activeStoryID = nil; record.experiences = experience
        }
    }
}
