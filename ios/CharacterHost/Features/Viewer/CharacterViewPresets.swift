import Foundation
import Observation

struct CharacterViewPose: Codable, Equatable, Sendable {
    var yaw = 0.0
    var pitch = 0.0
    var scale = 1.0
    var x = 0.0
    var y = 0.0
    static let original = Self()
    static let maximumPitch = 80.0
    var normalized: Self {
        func bounded(_ value:Double,_ range:ClosedRange<Double>,_ fallback:Double = 0) -> Double {
            value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : fallback
        }
        // Retain equivalent multi-turn yaw; migrate old overhead/inverted pitch
        // into the same expanded envelope enforced by Unity revision 10.
        func angle(_ value:Double) -> Double { value.isFinite ? value.remainder(dividingBy:360) : 0 }
        let vertical = angle(pitch)
        return Self(yaw:angle(yaw),pitch:bounded(vertical == -180 ? 180 : vertical,-Self.maximumPitch...Self.maximumPitch),
            scale:bounded(scale,0.4...1.28,1),x:bounded(x,-0.45...0.45),y:bounded(y,-0.45...0.45))
    }
    func matches(_ other:Self) -> Bool {
        abs((yaw-other.yaw).remainder(dividingBy:360))<0.1 && abs((pitch-other.pitch).remainder(dividingBy:360))<0.1 && abs(scale-other.scale)<0.002 && abs(x-other.x)<0.002 && abs(y-other.y)<0.002
    }
    var payload:[String:Any] { ["yaw":yaw,"pitch":pitch,"scale":scale,"x":x,"y":y] }
    init(yaw:Double = 0,pitch:Double = 0,scale:Double = 1,x:Double = 0,y:Double = 0) {
        self.yaw=yaw;self.pitch=pitch;self.scale=scale;self.x=x;self.y=y
    }
    init?(event:[String:Any]) {
        guard let p=event["inspectionPose"] as? [String:Any],
              let yaw=p["yaw"] as? Double,let pitch=p["pitch"] as? Double,
              let scale=p["scale"] as? Double,let x=p["x"] as? Double,let y=p["y"] as? Double,
              [yaw,pitch,scale,x,y].allSatisfy(\.isFinite) else { return nil }
        self=Self(yaw:yaw,pitch:pitch,scale:scale,x:x,y:y).normalized
    }
}
struct CharacterViewPreset: Codable, Identifiable, Sendable {
    var id = UUID()
    var name:String
    var pose:CharacterViewPose
}
struct CharacterViewLibrary: Codable, Sendable {
    var schemaVersion = 1
    var presets:[CharacterViewPreset] = []
    var selectedID:UUID?
    var selected:CharacterViewPose { presets.first { $0.id == selectedID }?.pose.normalized ?? .original }
}

// Legacy library is decoded only to migrate the last selected view from v0.43.
@Observable @MainActor final class CharacterViewEditor {
    var pose = CharacterViewPose.original
    var moving = false
    var isOpen = false
    var status = ""
}
