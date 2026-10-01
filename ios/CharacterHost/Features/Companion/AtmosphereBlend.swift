import Foundation

/// Analytic, critically damped density envelope. Retarget from the currently
/// displayed value AND velocity, including rapid reversals and fades to zero.
/// No per-particle timers or per-frame mutations of the conversation store.
struct AtmosphereBlend {
    static let amounts = [0.0,0.25,0.5,1.0,1.5]
    static func amount(for level:Int)->Double {amounts[min(4,max(0,level))]}
    static func normalized(_ intensity:Double)->Double {intensity.isFinite ? min(1,max(0,intensity)) : 0.5}
    /// Preserve the previous midpoint and maximum while allowing every value
    /// between them. Legacy saved detents map exactly to the same density.
    static func amount(forIntensity intensity:Double)->Double {
        let value=normalized(intensity)
        return value<=0.5 ? value : 0.5+(value-0.5)*2
    }
    static let settlingDuration = 1.5
    private(set) var target:Double
    private var origin:Double
    private var velocity = 0.0
    private var started = 0.0
    init(level:Int) {
        target=Self.amount(for:level);origin=target
    }
    init(intensity:Double) {
        target=Self.amount(forIntensity:intensity);origin=target
    }
    private func sample(at time:Double)->(value:Double,velocity:Double) {
        let t=max(0,time-started),omega=9.0
        if t>=Self.settlingDuration {return (target,0)}
        let offset=origin-target,b=velocity+omega*offset,decay=exp(-omega*t)
        let value=target+(offset+b*t)*decay
        if value<0 {return (0,0)}
        if value>Self.amounts[4] {return (Self.amounts[4],0)}
        return (value,(b-omega*(offset+b*t))*decay)
    }
    func value(at time:Double)->Double {sample(at:time).value}
    mutating func retarget(level:Int,at time:Double) {
        retarget(amount:Self.amount(for:level),at:time)
    }
    mutating func retarget(intensity:Double,at time:Double) {
        retarget(amount:Self.amount(forIntensity:intensity),at:time)
    }
    private mutating func retarget(amount next:Double,at time:Double) {
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
