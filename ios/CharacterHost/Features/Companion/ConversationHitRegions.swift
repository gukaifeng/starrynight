import SwiftUI

enum ConversationHitKind: Equatable { case message, control }
struct ConversationHitRegion: Equatable {
    var kind: ConversationHitKind
    var frame: CGRect
}
struct ConversationHitPreference: PreferenceKey {
    static let defaultValue: [String:ConversationHitRegion] = [:]
    static func reduce(value: inout [String:ConversationHitRegion],nextValue: () -> [String:ConversationHitRegion]) {
        value.merge(nextValue(),uniquingKeysWith: { _,new in new })
    }
}
extension View {
    /// Measure before the full-width row wrapper: whitespace next to a short
    /// bubble must stay distinct from the actual message and its audio button.
    func conversationHitRegion(_ kind:ConversationHitKind,id:String,enabled:Bool = true) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key:ConversationHitPreference.self,
                    value:enabled ? [id:ConversationHitRegion(kind:kind,frame:geometry.frame(in:.named("companionPanel")))] : [:])
            }
        }
    }
}
