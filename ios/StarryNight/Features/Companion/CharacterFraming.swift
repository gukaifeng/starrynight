import Foundation

struct CharacterFraming: Codable, Equatable, Sendable {
    var shot = "conversation"
    var size = 1.0
    var angle = 0.0
    static let recommended = CharacterFraming()
    var normalized: Self {
        Self(shot:shot == "full" ? "full" : "conversation",
             size:size.isFinite ? min(1.1,max(0.9,size)) : 1,
             angle:angle.isFinite ? min(20,max(-20,angle)) : 0)
    }
    var summary: String {
        let clean = normalized
        let direction = abs(clean.angle) < 0.5 ? "正面" : String(format:"%@ %.0f°",clean.angle < 0 ? "左" : "右",abs(clean.angle))
        return "\(clean.shot == "full" ? "全身互动" : "对话近景")，\(Int((clean.size*100).rounded()))%，\(direction)"
    }
}
