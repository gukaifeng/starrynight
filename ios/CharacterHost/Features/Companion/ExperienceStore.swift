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
    @discardableResult func beginStory(_ story:CompanionStory,model:ModelDescriptor,replay:Bool = false) -> CompanionMessage? {
        guard CompanionStory.available(for:model).contains(where:{ $0.id == story.id }) else { return nil }
        let existing = record(model.id).together.stories[story.id]
        let shouldBegin = existing == nil || replay
        let message = shouldBegin ? CompanionMessage(role:"assistant",text:story.text(story.node(nil),name:model.conversationProfile(preserving:record(model.id).profile).name),storyID:story.id) : nil
        update(model.id) { record in
            var experience = record.together; experience.activeStoryID = story.id
            if shouldBegin { experience.stories[story.id] = StoryProgress(storyID:story.id) }
            if let message { record.messages.append(message) }
            record.experiences = experience
        }
        return error == nil ? message : nil
    }
    func pauseStory(id:String) {
        update(id) { record in
            var experience = record.together; experience.activeStoryID = nil; record.experiences = experience
        }
    }
    @discardableResult func chooseStory(_ choiceID:String,nodeID:String,story:CompanionStory,model:ModelDescriptor) -> CompanionMessage? {
        let current = record(model.id)
        guard CompanionStory.available(for:model).contains(where:{ $0.id == story.id }), current.together.activeStoryID == story.id,
              let progress = current.together.stories[story.id],
              let transition = StoryEngine.choose(choiceID,nodeID:nodeID,story:story,progress:progress,name:model.conversationProfile(preserving:current.profile).name) else { return nil }
        let message = CompanionMessage(role:"assistant",text:transition.reply,storyID:story.id)
        update(model.id,countGuestTurn:true) { record in
            var experience = record.together; experience.stories[story.id] = transition.progress
            record.messages.append(CompanionMessage(role:"user",text:transition.userText,storyID:story.id))
            record.messages.append(message)
            if let ending = transition.ending {
                experience.moments.append(TogetherMoment(kind:"story",title:story.title + " · " + ending,text:transition.reply))
                experience.moments = Array(experience.moments.suffix(200))
            }
            record.experiences = experience
        }
        return error == nil ? message : nil
    }
}
