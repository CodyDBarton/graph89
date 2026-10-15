import Foundation
import simd

@main struct CameraChecks {
    static func pose(_ angle:Float)->[Float] {
        let m=simd_float3x3(simd_quatf(angle:angle,axis:SIMD3(0,0,1)))
        return [m[0].x,m[1].x,m[2].x,m[0].y,m[1].y,m[2].y,79,54,45,21]
    }
    static func calibrated()->Host3DCamera {
        var h=Host3DCamera()
        h.observe(pose(0),stamp:10,animated:true,now:10)
        h.observe(pose(0.1),stamp:10.1,animated:true,now:10.1)
        return h
    }
    static func main() {
        var h=calibrated(),last=h.camera(at:10.1)!,changes=0
        for i in 1...60 {
            let p=h.camera(at:10.1+Double(i)/120)!
            if p != last {changes+=1};last=p
        }
        assert(changes==60,"Host must advance without any new native samples")
        assert(abs(last[0]-cos(0.6))<0.0001 && abs(last[1]+sin(0.6))<0.0001)
        var clockCheck=calibrated(),reference=calibrated()
        _=clockCheck.camera(at:10.12)
        _=clockCheck.camera(at:10.11) // A main-thread sample can arrive after a future display target.
        let monotonic=clockCheck.camera(at:10.13)!
        _=reference.camera(at:10.12)
        let expected=reference.camera(at:10.13)!
        assert(zip(monotonic,expected).allSatisfy {abs($0-$1)<0.00001},"Older timestamps must not integrate the same time twice")
        var slower=calibrated()
        for i in 1...15 {_=slower.camera(at:10.1+Double(i)/30)}
        assert(zip(last,slower.camera(at:10.6)!).allSatisfy {abs($0-$1)<0.0001},"Angular speed must not depend on display Hz")
        h.key(63,pressed:true,now:10.6)
        let stopped=h.camera(at:10.6)!
        assert(stopped==h.camera(at:10.7)!,"A calculator command must stop local motion immediately")
        h.observe(pose(0.8),stamp:10.8,animated:true,now:10.8)
        assert(!h.moving,"Late native frames must not restart motion after a command")
        // Short taps must remain discrete even when successive native poses
        // arrive less than half a second apart (the old animation heuristic).
        var taps=calibrated()
        let beforeTap=taps.camera(at:10.2)!
        taps.key(1,pressed:true,now:10.2)
        taps.key(1,pressed:false,now:10.25)
        taps.observe(pose(0.1),stamp:10.3,animated:true,now:10.3)
        assert(zip(beforeTap,taps.camera(at:10.3)!).allSatisfy {abs($0-$1)<0.00001},"Stopping must not snap to the old native angle")
        for i in 0..<6 {
            let time=10.4+Double(i)*0.1
            taps.key(1,pressed:true,now:time)
            taps.key(1,pressed:false,now:time+0.02)
            taps.observe(pose(Float(i+2)*0.1),stamp:time+0.03,animated:true,now:time+0.03)
            assert(!taps.moving && !taps.permitsMotion,"Rapid taps must never start extrapolated rotation")
            let step=taps.camera(at:time+0.03)!
            assert(step==taps.camera(at:time+0.08)!,"A released tap must not drift between calculator steps")
        }
        var delayed=calibrated()
        let frozen=delayed.camera(at:10.2)!
        delayed.key(1,pressed:true,now:10.2)
        delayed.observe(pose(0.15),stamp:10.15,animated:true,now:10.23,referenceAge:0.08)
        assert(frozen==delayed.camera(at:10.23)!,"An in-flight pre-stop sample must not move the stopped camera")
        delayed.key(1,pressed:false,now:10.25)
        delayed.observe(pose(0.15),stamp:10.3,animated:true,now:10.3)
        assert(zip(frozen,delayed.camera(at:10.3)!).allSatisfy {abs($0-$1)<0.00001})
        taps.key(1,pressed:true,now:11.1)
        taps.observe(pose(0.8),stamp:11.5,animated:true,now:11.5)
        taps.observe(pose(0.9),stamp:11.6,animated:true,now:11.6)
        taps.key(1,pressed:false,now:11.65)
        assert(taps.moving && taps.permitsMotion,"A genuine hold must still permit continuous rotation after release")
        h.reset();assert(h.camera(at:11)==nil)
        var wrap=Host3DCamera()
        wrap.observe(pose(359 * .pi/180),stamp:10,animated:true,now:10)
        wrap.observe(pose(1 * .pi/180),stamp:10.1,animated:true,now:10.1)
        assert(wrap.moving,"Rotation must cross 360 degrees along the short arc")
        var stalled=calibrated();_=stalled.camera(at:12);assert(!stalled.moving)
        print("Host camera: independent motion, display-rate invariance, stop, late samples, reset, wrap and lifecycle checks passed")
    }
}
