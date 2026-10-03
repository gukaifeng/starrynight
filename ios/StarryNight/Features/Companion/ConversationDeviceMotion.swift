import Foundation
import CoreMotion

/// Gravity-free acceleration + rotation, with two opposing impulses. A single
/// pickup, walking noise or an orientation change must not interrupt a chat.
struct DeviceShakeDetector {
    private var peak:(time:Double,x:Double,y:Double,z:Double)?
    private var armed=true
    private var lastTrigger = -Double.infinity
    mutating func sample(time:Double,x:Double,y:Double,z:Double,rotation:Double)->Double? {
        guard [time,x,y,z,rotation].allSatisfy(\.isFinite) else {return nil}
        let energy=sqrt(x*x+y*y+z*z)
        if energy < 0.30 {armed=true}
        guard time-lastTrigger >= 12,armed,energy >= 0.85,rotation >= 1.7 else {return nil}
        armed=false
        if let previous=peak {
            let dt=time-previous.time
            let dot=x*previous.x+y*previous.y+z*previous.z
            if dt>=0.10 && dt<=0.85 && dot < -0.20 {
                lastTrigger=time;peak=nil;return min(1,max(0.35,energy/2.3))
            }
        }
        peak=(time,x,y,z);return nil
    }
}

@MainActor final class ConversationDeviceMotion {
    private let manager=CMMotionManager()
    private var detector=DeviceShakeDetector()
    var onShake:((Double)->Void)?
    func setActive(_ active:Bool) {
        if !active {manager.stopDeviceMotionUpdates();return}
        guard manager.isDeviceMotionAvailable,!manager.isDeviceMotionActive else {return}
        manager.deviceMotionUpdateInterval=1/40
        manager.startDeviceMotionUpdates(using:.xArbitraryZVertical,to:.main) { [weak self] motion,_ in
            MainActor.assumeIsolated {
                guard let self,let motion else {return}
                let a=motion.userAcceleration,r=motion.rotationRate
                if let intensity=self.detector.sample(time:motion.timestamp,x:a.x,y:a.y,z:a.z,rotation:sqrt(r.x*r.x+r.y*r.y+r.z*r.z)) {self.onShake?(intensity)}
            }
        }
    }
}
