import Foundation
import simd

@main struct MotionChecks {
    static func pose(_ a:Double)->[Float] {
        let c=Float(cos(a)),s=Float(sin(a))
        return [c,-s,0,s,c,0,79,54,45,21]
    }
    static func run(_ rate:Double,check:Bool) {
        var h=Host3DCamera()
        h.observe(pose(0),stamp:10,animated:true,now:10)
        h.observe(pose(0.1),stamp:10.1,animated:true,now:10.1)
        var previous=0.1,speeds=[Double](),maxCorrection=0.0,backward=0
        for i in 1...240 {
            let now=10.1+Double(i)/120
            if i%4==0 {
                let before=h.camera(at:now)!,angleBefore=Double(atan2(before[3],before[0]))
                let stamp=10+floor((now-10)*rate+1e-8)/rate
                h.observe(pose(stamp-10),stamp:stamp,animated:true,now:now)
                let after=h.camera(at:now)!,angleAfter=Double(atan2(after[3],after[0]))
                maxCorrection=max(maxCorrection,abs(angleAfter-angleBefore))
            }
            let p=h.camera(at:now)!,angle=Double(atan2(p[3],p[0])),speed=(angle-previous)*120
            speeds.append(speed);if speed<0 {backward+=1};previous=angle
        }
        let mean=speeds.reduce(0,+)/Double(speeds.count)
        let cv=sqrt(speeds.map {pow($0-mean,2)}.reduce(0,+)/Double(speeds.count))/abs(mean)*100
        print("Native \(rate) Hz: mean \(mean) rad/s, speed variation \(cv)%, backward frames \(backward), instantaneous correction \(maxCorrection) rad")
        if check {
            assert(backward==0,"Repeated native samples must never move the camera backward")
            assert(maxCorrection<0.00001,"Samples must not teleport the displayed orientation")
            assert(cv<5,"Evenly rotating native motion must remain smooth despite sparse samples")
            assert(abs(mean-1)<0.05,"Keep original average rotation speed")
        }
    }
    static func main() {
        let check=CommandLine.arguments.contains("--check")
        run(10,check:check);run(25,check:check)
    }
}
