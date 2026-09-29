import Foundation

// These public fixtures belong only to the local demo. They are not credentials or OAuth tokens.
enum DemoAccount {
    static let id = "XB-000001"
    static let alternateID = "XY-000002"
    static let name = "星夜体验者"
    static let email = "hello@xiaoban.example"
    static let phone = "13800000000"
    static let code = "123456"
}

struct DemoAccountSession: Codable, Equatable {
    let accountID: String
    let method: LoginMethod
}
