import Foundation
import simd

// Camera motion belongs to the display clock. Calculator samples establish
// angular velocity and correct slow drift; they are not animation endpoints.
struct Host3DCamera {
    private var orientation:simd_quatf?
    private var velocity=SIMD3<Float>.zero,targetVelocity=SIMD3<Float>.zero
    private var previousNative:simd_quatf?
    private var history=[(stamp:Double,q:simd_quatf)]()
    private var nativeStamp=0.0,clock=0.0,lastReference=0.0
    private var allowed=true
    private var heldArrow:Int?,pressTime=0.0,inputTime=0.0
    // Preserve the displayed angle when stopping. Later discrete calculator
    // steps are applied relative to it instead of snapping back to its clock.
    private var inputOffset:simd_quatf?
    private var parameters=[Float]()
    var permitsMotion:Bool {allowed}
    private(set) var moving=false
    private(set) var integratedFrames=0

    mutating func reset() {self=Host3DCamera()}
    mutating func key(_ key:Int,pressed:Bool,now:Double) {
        advance(to:now)
        if (0...3).contains(key) {
            if pressed {
                heldArrow=key;pressTime=now;inputTime=now
                if let q=previousNative,let displayed=orientation {inputOffset=simd_normalize(q.inverse*displayed)}
                allowed=false
                previousNative=nil;history=[];velocity = .zero;targetVelocity = .zero;moving=false
            }else if heldArrow==key {
                allowed=now-pressTime>=0.35;heldArrow=nil
            }
        }else if pressed {
            heldArrow=nil;inputTime=now
            if let q=previousNative,let displayed=orientation {inputOffset=simd_normalize(q.inverse*displayed)}
            allowed=false;velocity = .zero;targetVelocity = .zero;moving=false
        }
    }
    private func quaternion(_ p:[Float])->simd_quatf? {
        guard p.count==10,p.allSatisfy({$0.isFinite}) else {return nil}
        var a=SIMD3<Float>(p[0],p[1],p[2]),b=SIMD3<Float>(p[3],p[4],p[5])
        guard simd_length_squared(a)>1e-10 else {return nil}
        a=simd_normalize(a);b-=simd_dot(a,b)*a
        guard simd_length_squared(b)>1e-10 else {return nil}
        b=simd_normalize(b)
        let c=simd_cross(a,b)
        return simd_normalize(simd_quatf(simd_float3x3(columns:(SIMD3(a.x,b.x,c.x),SIMD3(a.y,b.y,c.y),SIMD3(a.z,b.z,c.z)))))
    }
    private func rotationVector(_ delta:simd_quatf)->SIMD3<Float> {
        var d=simd_normalize(delta)
        if d.real<0 {d=simd_quatf(vector:-d.vector)}
        let sine=simd_length(d.imag)
        return sine>1e-7 ? d.imag/sine*(2*atan2(sine,d.real)):.zero
    }
    mutating func observe(_ pose:[Float],stamp:Double,animated:Bool,now:Double,referenceAge:Double=0) {
        guard let native=quaternion(pose),stamp>=nativeStamp else {return}
        // A snapshot can already be in flight when the user stops rotation.
        // Absorb its old angle into the offset; never replay it as a new step.
        if inputTime>0 && now-referenceAge<inputTime {
            if let displayed=orientation {inputOffset=simd_normalize(native.inverse*displayed)}
            previousNative=native;nativeStamp=stamp
            return
        }
        if let _=heldArrow,now-pressTime>=0.35 {allowed=true}
        let q=inputOffset.map {simd_normalize(native*$0)} ?? native
        advance(to:now)
        parameters=pose
        if !animated || !allowed {
            orientation=q;velocity = .zero;targetVelocity = .zero;moving=false
            previousNative=native;nativeStamp=stamp;history=[];lastReference=now
            return
        }
        // Full snapshots can repeat the same completed calculator projection.
        // Such a sample must never reset an already advancing host camera.
        if previousNative != nil && stamp==nativeStamp {return}
        lastReference=now
        history.append((stamp,q))
        // Average several native steps so normal-speed CPU scheduling bursts
        // do not modulate the display's rotation rate. Keep the arc below pi.
        let window=min(0.4,2.5/Double(max(0.1,simd_length(velocity))))
        while history.count>2 && stamp-history[0].stamp>window {history.removeFirst()}
        if let first=history.first,stamp>first.stamp,stamp-first.stamp<0.6 {
            let measured=rotationVector(q*first.q.inverse)/Float(stamp-first.stamp)
            let speed=simd_length(measured)
            if speed>1e-6 && speed<15 {
                if !moving {orientation=q;velocity=measured}
                // Correct phase through a bounded angular velocity, never an
                // instantaneous position jump. Account for sample delivery age
                // and a display target already slightly ahead of the callback.
                let age=Float(min(0.2,max(0,referenceAge)+max(0,clock-now)))
                let predicted=simd_quatf(angle:speed*age,axis:measured/speed)*q
                var correction=orientation.map {rotationVector(predicted*$0.inverse)*0.3} ?? .zero
                let magnitude=simd_length(correction),limit=speed*0.1
                if magnitude>limit {correction *= limit/magnitude}
                targetVelocity=measured+correction;moving=true
            }
        }else if orientation==nil {orientation=q}
        previousNative=native;nativeStamp=stamp
    }
    private mutating func advance(to now:Double) {
        guard now>clock else {return}
        let dt=clock>0 ? now-clock:0;clock=now
        guard moving,let q=orientation else {return}
        // A background/lifecycle stall must not cause a giant camera jump.
        guard dt<0.25,now-lastReference<1 else {moving=false;velocity = .zero;targetVelocity = .zero;return}
        if dt>0 {
            // Exact integral of a first-order velocity filter. Unlike a fixed
            // per-frame blend, the response does not depend on display Hz.
            let tau:Float=0.35,d=Float(dt),decay=exp(-d/tau)
            let average=targetVelocity+(velocity-targetVelocity)*(tau*(1-decay)/d)
            velocity=targetVelocity+(velocity-targetVelocity)*decay
            let speed=simd_length(average)
            if speed>1e-6 {orientation=simd_normalize(simd_quatf(angle:speed*d,axis:average/speed)*q);integratedFrames+=1}
        }
    }
    mutating func camera(at now:Double)->[Float]? {
        advance(to:now)
        guard let q=orientation,parameters.count==10 else {return nil}
        let m=simd_float3x3(q)
        var result=parameters
        result[0]=m[0].x;result[1]=m[1].x;result[2]=m[2].x
        result[3]=m[0].y;result[4]=m[1].y;result[5]=m[2].y
        return result
    }
}
