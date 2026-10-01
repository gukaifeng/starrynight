import Foundation

@main enum AtmosphereBlendTests {
    static func main() {
        var assertions=0
        func check(_ ok:Bool,_ message:String) {assertions+=1;precondition(ok,message)}
        check(AtmosphereBlend.amount(for:2)==0.5,"New medium equals previous light")
        check(AtmosphereBlend.amount(for:1)==0.25,"New light halves the previous light")
        check(AtmosphereBlend.amount(for:3)==1 && AtmosphereBlend.amount(for:4)==1.5,"Former strongest level is removed")
        for level in 0...4 {
            check(AtmosphereBlend.amount(forIntensity:Double(level)/4)==AtmosphereBlend.amount(for:level),"Legacy density remains unchanged")
        }
        for step in 1...1000 {
            let value=Double(step)/1000,previous=Double(step-1)/1000
            check(AtmosphereBlend.amount(forIntensity:value)>AtmosphereBlend.amount(forIntensity:previous),"No discrete plateaus")
        }
        var continuous=AtmosphereBlend(intensity:0.37)
        for frame in 1...360 {
            let now=100+Double(frame)/120,intensity=0.5+sin(Double(frame)/41)*0.5
            let before=continuous.value(at:now)
            continuous.retarget(intensity:intensity,at:now)
            check(abs(continuous.value(at:now)-before)<1e-10,"Continuous dragging must never jump")
            check((0...1.5).contains(continuous.value(at:now+0.001)),"Continuous density stays bounded")
        }
        continuous.retarget(intensity:0,at:104)
        check(continuous.value(at:106)==0,"Continuous slider fully turns off")
        for from in 0...4 {for to in 0...4 {
            var blend=AtmosphereBlend(level:from)
            blend.retarget(level:to,at:100)
            let start=AtmosphereBlend.amount(for:from),end=AtmosphereBlend.amount(for:to)
            check(abs(blend.value(at:100)-start)<1e-10,"A new selection must retain the displayed density")
            var previous=start
            for frame in 1...180 {
                let value=blend.value(at:100+Double(frame)/120)
                check(value>=min(start,end)-1e-10 && value<=max(start,end)+1e-10,"No overshoot at any level")
                check(to>=from ? value>=previous-1e-10 : value<=previous+1e-10,"Uninterrupted fades are monotonic")
                previous=value
            }
            check(abs(previous-end)<1e-10,"Fades settle at the requested density, including fully off")
        }}
        var interrupted=AtmosphereBlend(level:0)
        interrupted.retarget(level:4,at:100)
        for (offset,level) in [(0.12,1),(0.27,4),(0.38,0),(0.46,2),(0.62,0)] {
            let now=100+offset,epsilon=0.000001
            let before=interrupted.value(at:now)
            let velocity=(before-interrupted.value(at:now-epsilon))/epsilon
            interrupted.retarget(level:level,at:now)
            check(abs(interrupted.value(at:now)-before)<1e-10,"Rapid retarget must not jump")
            let afterVelocity=(interrupted.value(at:now+epsilon)-before)/epsilon
            check(abs(afterVelocity-velocity)<0.001,"Rapid retarget preserves velocity")
        }
        check(interrupted.value(at:105)==0,"Interrupted fade to off settles exactly at zero")
        for index in 0..<180 {
            check(AtmosphereBlend.visibility(index:index,count:0)==0,"Off must draw no particles")
            let boundary=Double(index)+4
            check(abs(AtmosphereBlend.visibility(index:index,count:boundary+0.00001)-AtmosphereBlend.visibility(index:index,count:boundary-0.00001))<0.00001,"No particle pops at count boundaries")
        }
        print("Atmosphere blend PASS: \(assertions) assertions; legacy migration, continuous density and drag retarget, particle fade")
    }
}
