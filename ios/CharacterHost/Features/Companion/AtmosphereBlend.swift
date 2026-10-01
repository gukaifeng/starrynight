import Foundation

/// Analytic, critically damped density envelope. Retarget from the currently
/// displayed value AND velocity, including rapid reversals and fades to zero.
/// No per-particle timers or per-frame mutations of the conversation store.
struct AtmosphereBlend {
    static let levelNames = ["关闭","轻盈","适中","浓郁","绚烂"]
    static let settlingDuration = 1.5
    private(set) var target:Double
    private var origin:Double
    private var velocity = 0.0
    private var started = 0.0
    init(level:Int) {
        target=Double(min(4,max(0,level)))*0.5;origin=target
    }
    private func sample(at time:Double)->(value:Double,velocity:Double) {
        let t=max(0,time-started),omega=9.0
        if t>=Self.settlingDuration {return (target,0)}
        let offset=origin-target,b=velocity+omega*offset,decay=exp(-omega*t)
        let value=target+(offset+b*t)*decay
        if value<0 {return (0,0)}
        if value>2 {return (2,0)}
        return (value,(b-omega*(offset+b*t))*decay)
    }
    func value(at time:Double)->Double {sample(at:time).value}
    mutating func retarget(level:Int,at time:Double) {
        let next=Double(min(4,max(0,level)))*0.5
        guard next != target else {return}
        let current=sample(at:time)
        origin=current.value;velocity=current.velocity;started=time;target=next
    }
    /// Stable seeded particles retain their positions. New particles appear
    /// progressively instead of popping when an integer count crosses a level.
    static func visibility(index:Int,count:Double)->Double {
        let t=min(1,max(0,(count-Double(index))/8))
        return t*t*(3-2*t)
    }
}
