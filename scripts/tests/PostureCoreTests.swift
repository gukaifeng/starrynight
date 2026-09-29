import Foundation
@main struct PostureCoreTests {
    static func main() throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let human=try JSONDecoder().decode(ModelDescriptor.self,from:Data(contentsOf:root.appendingPathComponent("character-packages/builtins/real-woman/character.json")))
        let old=try JSONDecoder().decode(ModelDescriptor.self,from:Data(contentsOf:root.appendingPathComponent("character-packages/builtins/studio-robot/character.json")))
        var checks=0
        func check(_ ok:Bool){precondition(ok);checks+=1}
        func parse(_ text:String,_ current:PosturePreferences=PosturePreferences()) -> PostureDialogue.Result? { PostureDialogue.parse(text,model:human,current:current) }
        let sit=parse("你坐下陪我聊吧")!.preferences!
        check(sit.id=="sit")
        var tuning=parse("上身前倾6度，把腿收一点",sit)!.preferences!
        check(tuning.values["sit"]?["lean"]==6)
        check(abs((tuning.values["sit"]?["legRoom"] ?? 0)-0.35)<0.0001)
        let extreme=parse("前倾90度",sit)!
        check(extreme.preferences!.values["sit"]?["lean"]==10 && extreme.text.contains("范围内"))
        check(parse("不要坐下")!.preferences==nil)
        check(parse("我坐下了，今天有点累")==nil)
        check(parse("我想让你蹲下")!.preferences?.id=="crouch")
        check(parse("先坐下然后躺下")!.preferences==nil)
        check(parse("躺在床上") == nil) // Not an explicit supported posture phrase.
        check(parse("在床上躺下")!.preferences==nil)
        check(PostureDialogue.parse("坐下",model:old,current:PosturePreferences())!.preferences==nil)
        check(parse("你好")==nil)
        check(parse("朝左转10度",sit)!.preferences!.values["sit"]?["turn"] == -10)
        check(parse("手臂舒展70%",sit)!.preferences!.values["sit"]?["armRoom"] == 0.7)
        tuning.id="stand";tuning=parse("坐下",tuning)!.preferences!
        check(tuning.values["sit"]?["lean"]==6)
        let data=try JSONEncoder().encode(tuning)
        check(try JSONDecoder().decode(PosturePreferences.self,from:data)==tuning)
        var studio=CharacterStudio();studio.posture=tuning;studio.room="garden";studio.resetAppearance()
        check(studio.posture==tuning && studio.room=="garden")
        let previous=Data("{\"parameters\":null,\"faceWidth\":0.5,\"jawShape\":0.5,\"eyeSize\":0.5,\"mouthShape\":0.5,\"noseWidth\":0.5,\"bodyBuild\":0.5,\"bodyCurve\":0.5,\"height\":0.5,\"skin\":\"natural\",\"eyes\":\"brown\",\"hair\":\"long\",\"hairColor\":\"espresso\",\"clothing\":\"ivory\",\"room\":\"sunroom\",\"lightAngle\":-35,\"lightHeight\":48,\"lightIntensity\":1,\"shadow\":0.75}".utf8)
        check(try JSONDecoder().decode(CharacterStudio.self,from:previous).posture==nil)
        print("PASS: \(checks) posture parser, range, refusal, persistence and migration checks")
    }
}
