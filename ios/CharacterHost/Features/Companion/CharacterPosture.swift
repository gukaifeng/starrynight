import Foundation

struct PostureParameter: Decodable, Identifiable, Sendable {
    let id, label, unit: String
    let min, max, initial: Double
}
struct PostureDefinition: Decodable, Identifiable, Sendable {
    struct Action: Decodable, Sendable { let action: String }
    let id, label, symbol, support: String
    let parameters: [PostureParameter]
    let actions: [Action]
}
struct PostureProfile: Decodable, Sendable { let poses: [PostureDefinition] }
struct PosturePreferences: Codable, Equatable, Sendable {
    var id = "stand"
    var values: [String:[String:Double]] = [:]
    func value(_ parameter: PostureParameter) -> Double { values[id]?[parameter.id] ?? parameter.initial }
    mutating func set(_ parameter: PostureParameter, _ value: Double) {
        if values[id] == nil { values[id] = [:] }
        values[id]?[parameter.id] = value.isFinite ? Swift.min(parameter.max,Swift.max(parameter.min,value)) : parameter.initial
    }
    func payload(_ model: ModelDescriptor) -> [String:Any] {
        let p = model.posture?.poses.first { $0.id == id }
        return ["id":id,"parameters":p?.parameters.map { ["id":$0.id,"value":value($0)] as [String:Any] } ?? []]
    }
    func normalized(_ model: ModelDescriptor) -> Self {
        var result = self
        guard let poses = model.posture?.poses, !poses.isEmpty else { return Self() }
        if !poses.contains(where:{ $0.id == id }) { result.id = "stand" }
        for pose in poses {
            for p in pose.parameters {
                if let v = result.values[pose.id]?[p.id] {
                    result.values[pose.id]?[p.id] = v.isFinite ? Swift.min(p.max,Swift.max(p.min,v)) : p.initial
                }
            }
        }
        return result
    }
}

// Bounded local command interpretation. A later dialogue provider may produce the same
// typed intent; neither raw model text nor bone paths are executed by the engine.
enum PostureDialogue {
    struct Result: Sendable { var preferences: PosturePreferences?; var text: String }
    static func parse(_ text: String, model: ModelDescriptor, current: PosturePreferences) -> Result? {
        let q = text.replacingOccurrences(of:" ",with:"").lowercased()
        let poseWords: [(String,[String])] = [("stand",["站起来","站起","站着","站立","站直"]),("sit",["坐下","坐着","坐姿"]),("crouch",["蹲下","蹲着","蹲姿"]),("lie",["躺下","躺着","躺姿","侧躺"])]
        let declared = (model.posture?.poses ?? []).filter { $0.label.count >= 2 && q.contains($0.label) }.map(\.id)
        let matches = Array(Set(poseWords.filter { row in row.1.contains { q.contains($0) } }.map(\.0) + declared))
        var parameterWords: [(String,[String])] = [("lean",["前倾","后仰","挺直"]),("turn",["向左转","向右转","朝左","朝右","转正"]),("legRoom",["腿收","腿并","双腿间距","腿分开"]),("armRoom",["手臂舒展","手臂放松","手臂收"])]
        for p in (model.posture?.poses ?? []).flatMap(\.parameters) where p.label.count >= 2 {
            if let i = parameterWords.firstIndex(where:{$0.0 == p.id}) { if !parameterWords[i].1.contains(p.label) { parameterWords[i].1.append(p.label) } }
            else { parameterWords.append((p.id,[p.label])) }
        }
        let changes = parameterWords.filter { row in row.1.contains { q.contains($0) } }.map(\.0)
        guard !matches.isEmpty || !changes.isEmpty else { return nil }
        if q.hasPrefix("我") && !q.contains("让你") && !q.contains("你能") { return nil }
        if ["不要","不用","别","不想"].contains(where:{ q.contains($0) }) {
            return Result(text:"好，保持现在的姿势。你想换的时候再告诉我。")
        }
        guard matches.count <= 1 else { return Result(text:"一次可以设置一种姿势。你希望我先站着、坐下、蹲下，还是侧躺？") }
        if ["椅子","沙发","床上","床边","桌上"].contains(where:{q.contains($0)}) {
            return Result(text:"我现在支持在地面上坐下、蹲下或侧躺，还不能自动贴合椅子、沙发和床。你可以说“坐下”。")
        }
        var value = current.normalized(model)
        value.id = matches.first ?? value.id
        guard let pose = model.posture?.poses.first(where:{ $0.id == value.id }) else {
            return Result(text:"这个角色还没有制作这种可保持的姿势。小夏已经支持站立、坐下、蹲下和侧躺，可以先找她试试。")
        }
        var limited = false
        for id in changes {
            guard let p = pose.parameters.first(where:{$0.id == id}) else { return Result(text:"这个姿势暂时不能调整这项细节。可以在“定制角色 → 姿势”里查看可调范围。") }
            let step = p.unit == "degrees" ? 4.0 : 0.15
            var v = value.value(p)
            let negative = id == "lean" ? q.contains("后仰") : id == "turn" ? q.contains("向左") || q.contains("朝左") : q.contains("收") || q.contains("并") || q.contains("减小") || q.contains("减少")
            v += negative ? -step : step
            if q.contains("挺直") && id == "lean" || q.contains("转正") && id == "turn" { v = 0 }
            let words = parameterWords.first { $0.0 == id }!.1
            let pattern = "(?:" + words.map(NSRegularExpression.escapedPattern).joined(separator:"|") + ")[^0-9，。；]{0,4}([0-9]+(?:\\.[0-9]+)?)(度|%|％)?"
            if let regex = try? NSRegularExpression(pattern:pattern), let match = regex.firstMatch(in:q,range:NSRange(q.startIndex...,in:q)), let range = Range(match.range(at:1),in:q), let number = Double(q[range]) {
                v = p.unit == "normalized" ? number/100 : (negative ? -number : number)
            }
            if v < p.min || v > p.max { limited = true }
            value.set(p,v)
        }
        let details = changes.compactMap { id -> String? in
            guard let p = pose.parameters.first(where:{$0.id == id}) else {return nil}
            return p.label + (p.unit == "degrees" ? String(format:" %.0f°",value.value(p)) : String(format:" %.0f%%",value.value(p)*100))
        }
        var reply = "好，我会保持\(pose.label)的姿势陪你聊。"
        if !details.isEmpty { reply += details.joined(separator:"，") + "。" }
        if limited { reply += "已调整到这个角色制作时设定的范围内。" }
        return Result(preferences:value,text:reply)
    }
}
