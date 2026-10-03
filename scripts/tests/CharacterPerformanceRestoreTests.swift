import Foundation

@main struct CharacterPerformanceRestoreTests {
    @MainActor static func main() throws {
        let path="ios/StarryNight/Resources/CharacterCatalog.json"
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))) as! [String:Any]
        var tested=0
        for row in root["characters"] as! [[String:Any]] {
            guard let raw=row["performance"] as? [String:Any] else {continue}
            let profile=try JSONDecoder().decode(CharacterPerformanceProfile.self,from:JSONSerialization.data(withJSONObject:raw))
            let port=CharacterSignalPort()
            for group in profile.groups {
                let options=profile.options.filter{$0.group==group.id}
                let baseline=options.contains(where:{$0.id=="gesture-left-2"}) ? ["gesture-left-2","gesture-right-0"] : options.filter{$0.defaultOn==true}.map(\.id)
                let intent=CharacterIntent(eventName:"performance.replace",target:group.id,selections:baseline)
                let payload=port.payload(intent,actorId:row["id"] as! String)
                let data=try JSONSerialization.data(withJSONObject:payload)
                let actual=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                precondition(actual["selections"] as? [String]==baseline,"restore must preserve complete choices, including neutral hand, in one command")
                precondition(actual["eventName"] as? String=="performance.replace")
                precondition(actual["target"] as? String==group.id)
                let reset=port.payload(CharacterIntent(eventName:"performance.replace",target:group.id,selections:[]),actorId:row["id"] as! String)
                precondition(reset["selections"] as? [String]==[],"explicit empty group must not be omitted")
            }
            tested+=1
        }
        precondition(tested>=4);print("PERFORMANCE_RESTORE_PASS characters=\(tested)")
    }
}
