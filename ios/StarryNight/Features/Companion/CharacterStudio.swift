import Foundation

// Optional on CharacterProfile so existing archives keep all their conversation data.
struct CharacterStudio: Codable, Equatable, Sendable {
    var environments: [String:EnvironmentCustomization]? = nil
    var parameters: [String:Double]? = nil
    var posture: PosturePreferences? = nil
    var faceWidth = 0.5
    var jawShape = 0.5
    var eyeSize = 0.5
    var mouthShape = 0.5
    var noseWidth = 0.5
    var bodyBuild = 0.5
    var bodyCurve = 0.5
    var height = 0.5
    var skin = "natural"
    var eyes = "brown"
    var hair = "long"
    var hairColor = "espresso"
    var clothing = "ivory"
    var room = "sunroom"
    var lightAngle = -35.0
    var lightHeight = 48.0
    var lightIntensity = 1.0
    var shadow = 0.75
    static let recommended = Self()
    var normalized: Self {
        var result = self
        func bounded(_ value: Double, _ min: Double = 0, _ max: Double = 1, fallback: Double = 0.5) -> Double {
            value.isFinite ? Swift.min(max,Swift.max(min,value)) : fallback
        }
        result.faceWidth = bounded(faceWidth); result.jawShape = bounded(jawShape)
        result.eyeSize = bounded(eyeSize); result.mouthShape = bounded(mouthShape)
        result.noseWidth = bounded(noseWidth); result.bodyBuild = bounded(bodyBuild)
        result.bodyCurve = bounded(bodyCurve); result.height = bounded(height)
        if !["fair","natural","warm","deep"].contains(skin) { result.skin = "natural" }
        if !["brown","hazel","green"].contains(eyes) { result.eyes = "brown" }
        if !["long","bob"].contains(hair) { result.hair = "long" }
        if !["espresso","chestnut","black"].contains(hairColor) { result.hairColor = "espresso" }
        if !["ivory","sage","rose"].contains(clothing) { result.clothing = "ivory" }
        if !EnvironmentDescriptor.all.contains(where:{ $0.id == room }) { result.room = "sunroom" }
        result.lightAngle = bounded(lightAngle,-90,90,fallback:-35)
        result.lightHeight = bounded(lightHeight,20,75,fallback:48)
        result.lightIntensity = bounded(lightIntensity,0.6,1.5,fallback:1)
        result.shadow = bounded(shadow,0.15,1,fallback:0.75)
        var tuning = result.resolvedEnvironment
        let scene = EnvironmentDescriptor.find(result.room)
        if !scene.palettes.contains(where:{ $0.id == tuning.palette }) { tuning.palette = scene.palettes[0].id }
        tuning.angle = bounded(tuning.angle,-25,25,fallback:0)
        result.setEnvironment(tuning)
        return result
    }
    var resolvedEnvironment: EnvironmentCustomization {
        var value = environments?[room] ?? EnvironmentCustomization()
        value.lightAngle = lightAngle; value.lightHeight = lightHeight
        value.lightIntensity = lightIntensity; value.shadow = shadow
        return value
    }
    mutating func setEnvironment(_ value: EnvironmentCustomization) {
        if environments == nil { environments = [:] }
        environments?[room] = value
        lightAngle = value.lightAngle; lightHeight = value.lightHeight
        lightIntensity = value.lightIntensity; shadow = value.shadow
    }
    mutating func selectEnvironment(_ id: String) {
        setEnvironment(resolvedEnvironment)
        room = EnvironmentDescriptor.find(id).id
        setEnvironment(environments?[room] ?? EnvironmentCustomization())
    }
    mutating func resetAppearance() {
        var result = Self.recommended
        result.environments = environments; result.room = room
        result.posture = posture
        result.lightAngle = lightAngle; result.lightHeight = lightHeight
        result.lightIntensity = lightIntensity; result.shadow = shadow
        self = result
    }
    mutating func resetEnvironment() { setEnvironment(EnvironmentCustomization()) }
    var payload: [String:Any] {
        guard let data = try? JSONEncoder().encode(normalized),
              var dictionary = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        if let settings = try? JSONEncoder().encode(normalized.resolvedEnvironment),
           let object = try? JSONSerialization.jsonObject(with:settings) { dictionary["environment"] = object }
        return dictionary
    }
}
