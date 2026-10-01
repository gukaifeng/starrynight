import Foundation

@main enum AtmosphereBlendTests {
    static func main() {
        var assertions=0
        func check(_ ok:Bool,_ message:String) {assertions+=1;precondition(ok,message)}
        for from in 0...4 {for to in 0...4 {
            var blend=AtmosphereBlend(level:from)
            blend.retarget(level:to,at:100)
            let start=Double(from)*0.5,end=Double(to)*0.5
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
        print("Atmosphere blend PASS: \(assertions) assertions; 25 level pairs, 120 Hz sampling, continuous retarget and particle fade")
    }
}
