import SwiftUI
import Observation
import os

struct CharacterAtmosphere:Decodable,Sendable {
    let id:String
    let title:String
    let effect:String
    let palette:[String]
    let density:Double
    private struct Catalog:Decodable {let schemaVersion:Int;let characters:[CharacterAtmosphere]}
    private static let installed=OSAllocatedUnfairLock(initialState:[String:Self]())
    static func register(_ recipe:Self) {installed.withLock {$0[recipe.id]=recipe}}
    static func clearInstalled() {installed.withLock {$0.removeAll()}}
    static func unregister(_ id:String) {installed.withLock {$0[id]=nil}}
    static var all:[Self] {
        let downloaded=installed.withLock {Array($0.values)}
        return bundled.filter {r in !downloaded.contains(where:{$0.id==r.id})} + downloaded
    }
    private static let bundled:[CharacterAtmosphere] = {
        guard let url=Bundle.main.url(forResource:"CharacterAtmospheres",withExtension:"json"),
              let data=try? Data(contentsOf:url),let catalog=try? JSONDecoder().decode(Catalog.self,from:data),catalog.schemaVersion==1 else {return []}
        return catalog.characters
    }()
    var colors:[Color] {palette.map {hex in
        let number=UInt32(hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0xD6E1EF
        return Color(red:Double((number>>16)&255)/255,green:Double((number>>8)&255)/255,blue:Double(number&255)/255)
    }}
}

@MainActor @Observable final class AtmosphereActivity {var active=false}

/// A bounded screen-space foreground layer, independent of rig/gesture rotation.
/// Analytic motion avoids particle allocation, timers per mote and per-frame chat updates.
struct CharacterAtmosphereView:View {
    let session:CompanionSession
    let activity:AtmosphereActivity
    @State private var blend:AtmosphereBlend
    @State private var settled=true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var recipe:CharacterAtmosphere? {CharacterAtmosphere.all.first {$0.id==session.model.runtimeID}}
    init(session:CompanionSession,activity:AtmosphereActivity) {
        self.session=session;self.activity=activity
        _blend=State(initialValue:AtmosphereBlend(intensity:session.atmosphereIntensity))
    }
    var body:some View {
        if let recipe {
            TimelineView(.animation(minimumInterval:ProcessInfo.processInfo.isLowPowerModeEnabled ? 1/20 : 1/30,
                paused:!activity.active || (settled && (reduceMotion || blend.target==0)))) {timeline in
                Canvas(rendersAsynchronously:true) {context,size in
                    let now=timeline.date.timeIntervalSinceReferenceDate
                    draw(context:context,size:size,time:reduceMotion ? 12 : now,recipe:recipe,amount:blend.value(at:now))
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
                .onChange(of:session.atmosphereIntensity) {_,intensity in
                    blend.retarget(intensity:intensity,at:Date.timeIntervalSinceReferenceDate);settled=false
                }
                .task(id:session.atmosphereIntensity) {
                    // SwiftUI cancels this single settling task on retarget/disappear.
                    do {try await Task.sleep(for:.seconds(AtmosphereBlend.settlingDuration))}
                    catch {return}
                    settled=true
                }
        }
    }
    private func draw(context:GraphicsContext,size:CGSize,time:Double,recipe:CharacterAtmosphere,amount:Double) {
        let colors=recipe.colors
        guard !colors.isEmpty,amount>0.0001 else {return}
        // Medium is roughly three times the previous density. Bound the budget
        // on large screens and low-power devices; never allocate per-particle timers.
        let area=min(1.65,max(0.85,sqrt(size.width*size.height/(402*874))))
        let budget=ProcessInfo.processInfo.isLowPowerModeEnabled ? 96 : 180
        let count=reduceMotion ? 12*amount : min(Double(budget),110*min(1.2,max(0.4,recipe.density))*amount*area)
        for index in 0..<(reduceMotion ? 24 : budget) {
            let visibility=AtmosphereBlend.visibility(index:index,count:count)
            guard visibility>0.0001 else {continue}
            let seed=Double(index)*2.39996323
            let depth=Double(index%3+1)/3
            let duration=24+Double(index%7)*4
            let phase=(time/duration+seed).truncatingRemainder(dividingBy:1)
            let x=(sin(seed*4.12)*0.5+0.5)*size.width+sin(time*0.12+seed)*size.width*0.055*depth
            let y=(phase*1.16-0.08)*size.height
            // Suppress the lower chat strip and soften points passing a face.
            let face=abs(x/size.width-0.5)<0.19 && y/size.height<0.55
            let alpha=(0.3+depth*0.35)*(face ? 0.48 : 1)*min(1,max(0,(0.88-y/size.height)*4))
            let color=colors[index%colors.count]
            var layer=context;layer.opacity=alpha*visibility
            layer.translateBy(x:x,y:y)
            if recipe.effect=="petal" && index%3 != 0 {
                layer.rotate(by:.radians(time*0.3+seed))
                let radius=4+depth*6
                var petal=Path();petal.move(to:CGPoint(x:-radius,y:0))
                petal.addQuadCurve(to:CGPoint(x:radius,y:0),control:CGPoint(x:0,y:-radius*1.1))
                petal.addQuadCurve(to:CGPoint(x:-radius,y:0),control:CGPoint(x:radius*0.1,y:radius*0.9))
                layer.scaleBy(x:0.45+abs(sin(time*0.32+seed))*0.55,y:1)
                layer.fill(petal,with:.linearGradient(Gradient(colors:[color,.white.opacity(0.7)]),startPoint:CGPoint(x:-radius,y:-radius),endPoint:CGPoint(x:radius,y:radius)))
            } else {
                let radius=(recipe.effect=="firefly" ? 2.0 : 1.5)+depth*2.5
                var glow=layer;glow.blendMode = .plusLighter;glow.addFilter(.blur(radius:3+depth*3))
                glow.fill(Path(ellipseIn:CGRect(x:-radius*2,y:-radius*2,width:radius*4,height:radius*4)),with:.color(color))
                layer.opacity *= 0.6+0.4*sin(time*0.7+seed)*sin(time*0.7+seed)
                layer.fill(Path(ellipseIn:CGRect(x:-radius/2,y:-radius/2,width:radius,height:radius)),with:.color(color.opacity(0.8)))
                if recipe.effect=="stardust" && index%5==0 {
                    var star=Path();star.move(to:CGPoint(x:-radius*2,y:0));star.addLine(to:CGPoint(x:radius*2,y:0));star.move(to:CGPoint(x:0,y:-radius*2));star.addLine(to:CGPoint(x:0,y:radius*2))
                    layer.stroke(star,with:.color(color),lineWidth:0.6)
                }
            }
        }
        // Long, almost transparent currents bind the small particles into an
        // atmosphere. They stay near the edges instead of masking the avatar.
        for index in 0..<2 {
            var ribbon=Path();let shift=sin(time*0.07+Double(index))*size.width*0.025
            ribbon.move(to:CGPoint(x:Double(index)*size.width+shift,y:-20))
            ribbon.addCurve(to:CGPoint(x:size.width*(index==0 ? 0.17 : 0.85)+shift,y:size.height*0.78),
                control1:CGPoint(x:size.width*0.35+shift,y:size.height*0.17),control2:CGPoint(x:size.width*0.05+Double(index)*size.width*0.82,y:size.height*0.45))
            var haze=context;haze.addFilter(.blur(radius:recipe.effect=="sunbeam" ? 14 : 5))
            haze.stroke(ribbon,with:.linearGradient(Gradient(colors:[colors[index%colors.count].opacity(0.12*min(1.6,amount)),.clear]),startPoint:.zero,endPoint:CGPoint(x:0,y:size.height*0.8)),lineWidth:recipe.effect=="sunbeam" ? 24 : 3)
        }
    }
}
