import Foundation
struct EmotionPerformanceCatalog:Decodable,Sendable {
    struct Variant:Decodable,Identifiable,Sendable {let id,label,base,expression:String;let duration:Double;let channels:[String]}
    struct Entry:Decodable,Identifiable,Sendable {let id,kind,label,providerTag:String;let variants:[Variant];var key:String {kind+"."+id}}
    let schemaVersion,revision:Int
    let entries:[Entry]
    static let shared:Self? = {
        guard let url=Bundle.main.url(forResource:"EmotionPerformanceStandard",withExtension:"json"),let data=try? Data(contentsOf:url),
              let value=try? JSONDecoder().decode(Self.self,from:data),value.schemaVersion==1 else{return nil}
        return value
    }()
    static func alternate(_ emotion:String,previous:String)->String {
        guard emotion==previous else{return emotion}
        return ["neutral":"calm","calm":"neutral","happy":"playful","playful":"happy","excited":"happy","sad":"worried","crying":"sad","angry":"serious","worried":"empathetic","fearful":"worried","panicked":"fearful","surprised":"curious","curious":"thoughtful","thoughtful":"curious","serious":"thoughtful","empathetic":"affectionate","affectionate":"shy","shy":"affectionate","sarcastic":"playful","scornful":"serious","reluctant":"worried","bored":"tired","tired":"calm","confident":"hopeful","grateful":"affectionate","jealous":"shy","relieved":"calm","hopeful":"happy"][emotion] ?? "neutral"
    }
}
struct EmotionCharacterMapping:Decodable,Identifiable {
    let id,kind,label:String
    let variants,faces,originalOptions,channels,unavailable:[String]
    var key:String {kind+"."+id}
}
