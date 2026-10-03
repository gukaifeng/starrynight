import Foundation

// Remove the obsolete installation-wide switch. Preview is owned by each
// character collection; complete characters keep their normal conversation.
enum CharacterModelReview {
    static func configure(defaults:UserDefaults = .standard) {
        defaults.removeObject(forKey:"starry.character-model-review.v1")
    }
}
