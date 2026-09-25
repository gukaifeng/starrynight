import Foundation

struct ModelDescriptor: Identifiable {
    let id: String
    let name: String
    let originalName: String
    let description: String
    let thumbnail: String
    static let robot = ModelDescriptor(id: "robot-expressive", name: "示例机器人",
        originalName: "Robot Expressive", description: "会挥手、会跳舞，还会回应你的触碰。", thumbnail: "RobotThumbnail")
}
