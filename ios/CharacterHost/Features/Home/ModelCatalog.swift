import Foundation

struct ModelDescriptor: Identifiable {
    let id: String
    let name: String
    let originalName: String
    let description: String
    let thumbnail: String
    static let robot = ModelDescriptor(id: "studio-robot", name: "Luma",
        originalName: "Studio Robot", description: "温润陶瓷，微光眼眸。触碰一下，和它打个招呼。", thumbnail: "RobotThumbnail")
}
