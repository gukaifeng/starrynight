import Foundation

enum LoginMethod: String, CaseIterable, Codable, Identifiable {
    case wechat, email, phone, password, testGuest
    // Legacy demo fixtures keep their original three choices. Real sign-in uses
    // the server's password flow; unavailable providers are not simulated.
    static let allCases: [Self] = [.wechat,.email,.phone]
    var id: String { rawValue }
    var title: String {
        switch self { case .wechat: "微信"; case .email: "邮箱"; case .phone: "手机号";case .password:"账号密码";case .testGuest:"测试体验" }
    }
    var symbol: String {
        switch self { case .wechat: "bubble.left.and.bubble.right.fill"; case .email: "envelope"; case .phone: "iphone";case .password:"key";case .testGuest:"sparkles" }
    }
}
