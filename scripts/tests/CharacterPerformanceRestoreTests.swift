import Foundation

@main struct CharacterPerformanceRestoreTests {
    static func main() throws {
        let path="ios/CharacterHost/Resources/CharacterCatalog.json"
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))) as! [String:Any]
        var tested=0
        for row in root["characters"] as! [[String:Any]] {
            guard let raw=row["performance"] as? [String:Any] else {continue}
            let profile=try JSONDecoder().decode(CharacterPerformanceProfile.self,from:JSONSerialization.data(withJSONObject:raw))
            if let smile=profile.options.first(where:{$0.id=="gesture-left-2"}) {
                let original:Set<String>=[smile.id,"gesture-right-0"]
                let restore=profile.restoring(smile.group,baseline:original)
                precondition(Set(restore.map(\.id))==original,"unselected shared enum must not erase smile")
                precondition(profile.restoring(smile.group,baseline:[]).isEmpty,"reset already handles portable defaults")
            } else {
                for group in profile.groups {
                    let defaults=Set(profile.options.filter{$0.group==group.id && $0.defaultOn==true}.map(\.id))
                    let replay=profile.restoring(group.id,baseline:defaults)
                    precondition(Set(replay.filter{!$0.isToggle}.map(\.id)).isSubset(of:defaults))
                    precondition(profile.options.filter{$0.group==group.id && $0.isToggle}.allSatisfy{o in replay.contains{$0.id==o.id}},"legacy independent toggles must retain OFF restore")
                }
            }
            tested+=1
        }
        precondition(tested>=4);print("PERFORMANCE_RESTORE_PASS characters=\(tested)")
    }
}
