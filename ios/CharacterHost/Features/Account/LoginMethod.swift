import Foundation

enum LoginMethod: String, CaseIterable, Codable, Identifiable {
    case wechat, email, phone
    var id: String { rawValue }
    var title: String {
        switch self { case .wechat: "微信"; case .email: "邮箱"; case .phone: "手机号" }
    }
    var symbol: String {
        switch self { case .wechat: "bubble.left.and.bubble.right.fill"; case .email: "envelope"; case .phone: "iphone" }
    }
}
