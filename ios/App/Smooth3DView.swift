import UIKit
import MetalKit

private final class RotationDisplayTarget: NSObject {
    weak var view: Smooth3DView?
    @objc func tick(_ link: CADisplayLink) {view?.displayTick(link)}
}

private final class RotationPresentationStats {
    private let lock=NSLock()
    private var times=[Double]()
    func record(_ time:Double) {
        guard time>0 else {return}
        lock.lock();defer {lock.unlock()}
        times.append(time);if times.count>240 {times.removeFirst(times.count-240)}
    }
    var summary:String {
        lock.lock();let samples=times;lock.unlock()
        let deltas=zip(samples.dropFirst(),samples).map {$0-$1}.filter {$0>0}
        guard !deltas.isEmpty else {return "presentedFPS:0;presentedP95ms:0"}
        let sorted=deltas.sorted(),p95=sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]
        return "presentedFPS:\(Double(deltas.count)/deltas.reduce(0,+));presentedP95ms:\(p95*1000)"
    }
}

private final class RotationWorkStats {
    private let lock=NSLock()
    private var data=[String:[Double]]()
    func record(_ name:String,_ value:Double) {
        guard value.isFinite,(value>=0 || name=="motionDegS") else {return}
        lock.lock();defer {lock.unlock()}
        var values=data[name] ?? [];values.append(value)
        if values.count>240 {values.removeFirst(values.count-240)}
        data[name]=values
    }
    var summary:String {
        lock.lock();let copy=data;lock.unlock()
        return copy.keys.sorted().map {key in
            let values=copy[key]!,ordered=values.sorted()
            let mean=values.reduce(0,+)/Double(values.count)
            let cv=abs(mean)>1e-9 ? sqrt(values.map {($0-mean)*($0-mean)}.reduce(0,+)/Double(values.count))/abs(mean)*100:0
            let motion=key=="motionDegS" ? ";motionCV:\(cv);motionBackwards:\(values.filter {$0<0}.count)":""
            return "\(key)Mean:\(mean)\(motion);\(key)P95:\(ordered[min(ordered.count-1,Int(Double(ordered.count)*0.95))])"
        }.joined(separator:";")
    }
}

struct MeshFrame {
    let meta: [Double]
    let vertices: [Float]?
    let edges: [UInt32]?
}

// The emulator supplies geometry/camera at its normal snapshot cadence.
// Metal projects the cached mesh at display cadence, without emulator reads.
final class Smooth3DView: MTKView, MTKViewDelegate {
    private var wire: MTLRenderPipelineState!
    private var backdrop: MTLRenderPipelineState!
    private var commands: MTLCommandQueue!
    private var vertexBuffer: MTLBuffer?
    private var edgeBuffer: MTLBuffer?
    private var axisBuffer: MTLBuffer?
    private var axisEdges: MTLBuffer?
    private var maskTexture: MTLTexture?
    private var displayLink:CADisplayLink?
    private let displayTarget=RotationDisplayTarget()
    private let presentation=RotationPresentationStats()
    private let workStats=RotationWorkStats()
    private let profiling=ProcessInfo.processInfo.arguments.contains("--ui-test-rotation")
    private var lastTick=0.0,screenHz=0.0
    private let hostEnabled = !ProcessInfo.processInfo.arguments.contains("--ui-test-intermediate-camera")
    private var hostCamera=Host3DCamera()
    var hostFrames:Int {hostCamera.integratedFrames}
    var ownsCamera:Bool {hostEnabled && rotating}
    private var fromCamera=[Float](),targetCamera=[Float]()
    private var cameraStart=0.0,cameraDuration=0.0,lastCameraSample=0.0
    private var targetTimestamp=0.0
    private var lastPose=[Float]()
    private var motionOrientation:simd_quatf?
    private var motionTime=0.0,motionAxis=SIMD3<Float>.zero
    private(set) var changedPoses=0
    var presentationDiagnostics:String {presentation.summary+";screenHz:\(screenHz);"+workStats.summary}
    var apdPrevented:Int {meta.count>58 ? Int(meta[58]):0}
    var requestCamera:(()->Void)?
    private(set) var fastCameraSamples=0
    private var meta: [Double]=[]
    private var edgeCount=0
    private var clip=SIMD4<Float>(0,16,159,93)
    private var labels=[CAShapeLayer]()
    private(set) var valid=false
    private(set) var drawnFrames=0
    private var firstDrawTime=0.0
    private(set) var drawSeconds=0.0
    private var guestRotating:Bool {meta.count>=46 && meta[26]>0 && CACurrentMediaTime()<meta[27]+max(0.5,meta[26])}
    var rotating: Bool {valid && (hostEnabled ? hostCamera.moving || (hostCamera.permitsMotion && guestRotating):guestRotating)}
    func key(_ key:Int,pressed:Bool) {
        guard hostEnabled,valid else {return}
        hostCamera.key(key,pressed:pressed,now:CACurrentMediaTime())
        displayLink?.isPaused = !rotating
        draw()
    }
    var labelCount: Int {valid && meta[3]>0 && meta[4]>0 ? 3:0}
    private struct Uniforms { var x:SIMD4<Float>;var y:SIMD4<Float>;var screen:SIMD4<Float>;var clip:SIMD4<Float> }
    static func make() -> Smooth3DView? {
        guard let device=MTLCreateSystemDefaultDevice() else {return nil}
        let view=Smooth3DView(frame:.zero,device:device)
        do {
            let library=try device.makeLibrary(source:shader,options:nil)
            func pipeline(_ vertex:String,_ fragment:String)throws->MTLRenderPipelineState {
                let d=MTLRenderPipelineDescriptor();d.vertexFunction=library.makeFunction(name:vertex);d.fragmentFunction=library.makeFunction(name:fragment)
                d.rasterSampleCount=4
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                d.colorAttachments[0].isBlendingEnabled=true
                d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha;d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor:d)
            }
            view.wire=try pipeline("lines","ink");view.backdrop=try pipeline("backgroundQuad","paper");view.commands=device.makeCommandQueue()
        }catch {
            if let folder=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first {try? String(describing:error).write(to:folder.appendingPathComponent("metal-error.txt"),atomically:true,encoding:.utf8)}
            return nil
        }
        view.sampleCount=4;view.delegate=view;view.isOpaque=false;view.backgroundColor = .clear;view.clearColor=MTLClearColorMake(0,0,0,0)
        // Keep MTKView's own timer stopped. One display link owns all draws.
        view.framebufferOnly=true;view.isPaused=true;view.enableSetNeedsDisplay=false
        view.isUserInteractionEnabled=false
        view.displayTarget.view=view
        let indices:[UInt32]=[0,1,2,3,4,5]
        view.axisEdges=indices.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count)}
        for _ in 0..<3 {let layer=CAShapeLayer();layer.fillColor=UIColor(white:30/255,alpha:1).cgColor;view.layer.addSublayer(layer);view.labels.append(layer)}
        return view
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate();displayLink=nil
        if let screen=window?.windowScene?.screen {
            let link=CADisplayLink(target:displayTarget,selector:#selector(RotationDisplayTarget.tick(_:)))
            let hz=Float(screen.maximumFramesPerSecond);screenHz=Double(hz)
            link.preferredFrameRateRange=CAFrameRateRange(minimum:hz,maximum:hz,preferred:hz)
            link.add(to:.main,forMode:.common);displayLink=link
            link.isPaused = !rotating
        }
    }
    deinit {displayLink?.invalidate()}
    fileprivate func displayTick(_ link:CADisplayLink) {
        guard valid else {link.isPaused=true;return}
        if profiling {
            let now=CACurrentMediaTime()
            if lastTick>0 {workStats.record("callbackMs",(now-lastTick)*1000)}
            workStats.record("targetMs",(link.targetTimestamp-link.timestamp)*1000);lastTick=now
        }
        if !hostEnabled {requestCamera?()}
        targetTimestamp=link.targetTimestamp;draw();targetTimestamp=0
        if !rotating {link.isPaused=true}
    }
    func configureLabels(_ paths:[CGPath?]) {for (i,path) in paths.enumerated() where i<3 {labels[i].path=path}}
    func update(_ frame:MeshFrame?,background:Data,bounds:[Float]) {
        guard let frame,frame.meta.count>=46,background.count==16000,bounds.count>=4 else {
            valid=false;isHidden=true;displayLink?.isPaused=true;labels.forEach {$0.isHidden=true};return
        }
        let next=frame.meta
        if meta.isEmpty || next[0] != meta[0] {meta=[];targetCamera=[];fromCamera=[];lastCameraSample=0;hostCamera.reset()}
        acceptCamera(next)
        edgeCount=Int(next[2]);clip=SIMD4<Float>(bounds[0],bounds[1],bounds[2],bounds[3])
        if let values=frame.vertices {vertexBuffer=values.withUnsafeBytes {device!.makeBuffer(bytes:$0.baseAddress!,length:$0.count)}}
        if let values=frame.edges {edgeBuffer=values.withUnsafeBytes {device!.makeBuffer(bytes:$0.baseAddress!,length:$0.count)}}
        guard vertexBuffer != nil,edgeBuffer != nil else {valid=false;isHidden=true;return}
        // Never replace storage still being sampled by an in-flight GPU frame.
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r8Uint,width:160,height:100,mipmapped:false)
        descriptor.usage = .shaderRead;maskTexture=device!.makeTexture(descriptor:descriptor)
        // Native axis lettering belongs to the previous camera; the GPU owns it.
        var cleaned=[UInt8](background)
        for y in 16..<93 {for x in 0..<159 {cleaned[y*160+x] &= ~UInt8(1)}}
        cleaned.withUnsafeBytes {maskTexture?.replace(region:MTLRegionMake2D(0,0,160,100),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:160)}
        valid=true;isHidden=false;displayLink?.isPaused = !rotating
        if !rotating {draw()}
    }
    func updateCamera(_ next:[Double]) {
        guard valid,next.count>=64,next[0]==meta[0] else {return}
        fastCameraSamples+=1
        acceptCamera(next)
    }
    private func acceptCamera(_ next:[Double]) {
        // A completed 30 Hz full snapshot may arrive after a newer fast sample.
        // Compare the unchanged native stamp rather than converted host epochs.
        guard next.count>=64,meta.isEmpty || next[47]>=meta[47] else {return}
        let now=CACurrentMediaTime(),pose=(15..<25).map {Float(next[$0])}
        guard pose.allSatisfy({$0.isFinite}),next[1]>0,next[2]>0 else {return}
        if pose != targetCamera {
            let current=camera(at:now)
            let interval=lastCameraSample>0 ? now-lastCameraSample:0
            fromCamera=current.isEmpty ? pose:current;targetCamera=pose;cameraStart=now
            cameraDuration=next[26]>0 && interval>0 && interval<0.5 ? min(0.1,max(1.0/120,interval)):0
            lastCameraSample=now
        }
        if hostEnabled {hostCamera.observe(pose,stamp:next[47],animated:next[26]>0 && now<next[27]+0.5,now:now,referenceAge:max(0,now-next[27]))}
        meta=next
        let axes=meta[28..<46].map(Float.init)
        axisBuffer=axes.withUnsafeBytes {device!.makeBuffer(bytes:$0.baseAddress!,length:$0.count)}
    }
    private func camera(at now:Double)->[Float] {
        if hostEnabled,let pose=hostCamera.camera(at:now) {return pose}
        guard targetCamera.count==10 else {return []}
        let t=Float(cameraDuration>0 ? min(1,max(0,(now-cameraStart)/cameraDuration)):1)
        var c=zip(fromCamera,targetCamera).map {$0+t*($1-$0)}
        if t>0 && t<1 {
            var a=SIMD3<Float>(c[0],c[1],c[2]),b=SIMD3<Float>(c[3],c[4],c[5])
            guard simd_length_squared(a)>1e-12 else {return targetCamera}
            a=simd_normalize(a);b=b-simd_dot(a,b)*a
            guard simd_length_squared(b)>1e-12 else {return targetCamera}
            b=simd_normalize(b)
            c[0]=a.x;c[1]=a.y;c[2]=a.z;c[3]=b.x;c[4]=b.y;c[5]=b.z
        }
        return c.allSatisfy({$0.isFinite}) ? c:targetCamera
    }
    func draw(in view:MTKView) {
        let cpuStart=CACurrentMediaTime()
        defer {if profiling {workStats.record("drawCPUMs",(CACurrentMediaTime()-cpuStart)*1000)}}
        guard valid,let render=currentRenderPassDescriptor,let drawable=currentDrawable,let command=commands.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:render) else {return}
        if profiling {workStats.record("drawableWaitMs",(CACurrentMediaTime()-cpuStart)*1000)}
        let c=camera(at:targetTimestamp>0 ? targetTimestamp:CACurrentMediaTime())
        guard c.count==10 else {encoder.endEncoding();return}
        if c != lastPose {changedPoses+=1;lastPose=c}
        if profiling {
            let a=SIMD3<Float>(c[0],c[1],c[2]),b=SIMD3<Float>(c[3],c[4],c[5]),z=simd_cross(a,b)
            let q=simd_normalize(simd_quatf(simd_float3x3(columns:(SIMD3(a.x,b.x,z.x),SIMD3(a.y,b.y,z.y),SIMD3(a.z,b.z,z.z)))))
            let time=targetTimestamp>0 ? targetTimestamp:CACurrentMediaTime()
            if let before=motionOrientation,time>motionTime,time-motionTime<0.1,rotating {
                var d=simd_normalize(q*before.inverse)
                if d.real<0 {d=simd_quatf(vector:-d.vector)}
                let sine=simd_length(d.imag),sign:Double=simd_dot(d.imag,motionAxis)<0 ? -1:1
                let speed=Double(2*atan2(sine,d.real))*180/Double.pi/(time-motionTime)*sign
                workStats.record("motionDegS",speed)
                if sine>1e-7 && sign>0 {motionAxis=d.imag/sine}
            }
            motionOrientation=q;motionTime=time
        }
        var u=Uniforms(x:SIMD4<Float>(c[0],c[1],c[2],c[8]),y:SIMD4<Float>(c[3],c[4],c[5],c[9]),screen:SIMD4<Float>(c[6],c[7],Float(drawableSize.width),Float(drawableSize.height)),clip:clip)
        encoder.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:2);encoder.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:2)
        encoder.setFragmentTexture(maskTexture,index:0);encoder.setRenderPipelineState(backdrop);encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4)
        encoder.setRenderPipelineState(wire);encoder.setVertexBuffer(vertexBuffer,offset:0,index:0);encoder.setVertexBuffer(edgeBuffer,offset:0,index:1)
        encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4,instanceCount:edgeCount)
        if meta[4]>0 {
            encoder.setVertexBuffer(axisBuffer,offset:0,index:0);encoder.setVertexBuffer(axisEdges,offset:0,index:1)
            encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4,instanceCount:3)
        }
        encoder.endEncoding()
        let stats=presentation
        #if !targetEnvironment(simulator)
        drawable.addPresentedHandler {stats.record($0.presentedTime)}
        #endif
        if profiling {
            let work=workStats
            command.addCompletedHandler {buffer in
                if buffer.gpuEndTime>buffer.gpuStartTime {work.record("gpuMs",(buffer.gpuEndTime-buffer.gpuStartTime)*1000)}
            }
        }
        command.present(drawable);command.commit();drawnFrames+=1
        let now=CACurrentMediaTime();if firstDrawTime==0 {firstDrawTime=now};drawSeconds=now-firstDrawTime
        CATransaction.begin();CATransaction.setDisableActions(true)
        for k in 0..<3 {
            let start=28+k*6,positive=meta[start+k]>meta[start+3+k] ? start:start+3
            let v=SIMD3<Float>(Float(meta[positive]),Float(meta[positive+1]),Float(meta[positive+2]))
            let x=c[6]+c[8]*simd_dot(SIMD3<Float>(c[0],c[1],c[2]),v)+2
            let y=c[7]+c[9]*simd_dot(SIMD3<Float>(c[3],c[4],c[5]),v)+1
            labels[k].isHidden=meta[3]==0 || meta[4]==0 || x<clip.x || x+6>clip.z || y<clip.y || y+8>clip.w
            labels[k].setAffineTransform(CGAffineTransform(a:bounds.width/160,b:0,c:0,d:bounds.height/100,tx:CGFloat(x)*bounds.width/160,ty:CGFloat(y)*bounds.height/100))
        }
        CATransaction.commit()
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    private static let shader="""
    #include <metal_stdlib>
    using namespace metal;
    struct U {float4 x,y,screen,clip;};
    struct V {float4 position [[position]];float2 lcd;};
    float2 project(float3 p,constant U& u){return u.screen.xy+float2(dot(p,u.x.xyz)*u.x.w,dot(p,u.y.xyz)*u.y.w);}
    V output(float2 p){V v;v.lcd=p;v.position=float4(p.x/80-1,1-p.y/50,0,1);return v;}
    vertex V backgroundQuad(uint id [[vertex_id]]){return output(float2((id&1)?160:0,(id&2)?100:0));}
    vertex V lines(uint id [[vertex_id]],uint instance [[instance_id]],const device packed_float3* points [[buffer(0)]],const device uint2* edges [[buffer(1)]],constant U& u [[buffer(2)]]){
        uint2 edge=edges[instance];float2 a=project(points[edge.x],u),b=project(points[edge.y],u);
        float2 delta=(b-a)*u.screen.zw/float2(160,100);float len=length(delta);
        float2 normal=len>0.0001?float2(-delta.y,delta.x)/len:float2(0,1);
        float2 offset=normal*1.2*float2(160,100)/u.screen.zw;
        return output(((id&2)?b:a)+((id&1)?offset:-offset));
    }
    bool hidden(V v,constant U& u,texture2d<uint> maskTexture){return v.lcd.x<u.clip.x||v.lcd.y<u.clip.y||v.lcd.x>=u.clip.z||v.lcd.y>=u.clip.w||(maskTexture.read(uint2(clamp(v.lcd,float2(0),float2(159,99)))).r&6)!=0;}
    fragment float4 ink(V v [[stage_in]],constant U& u [[buffer(2)]],texture2d<uint> maskTexture [[texture(0)]]){if(hidden(v,u,maskTexture))discard_fragment();return float4(float3(30.0/255),1);}
    fragment float4 paper(V v [[stage_in]],constant U& u [[buffer(2)]],texture2d<uint> maskTexture [[texture(0)]]){if(hidden(v,u,maskTexture))discard_fragment();uint bit=maskTexture.read(uint2(clamp(v.lcd,float2(0),float2(159,99)))).r&1;return float4(float3(bit?30.0/255:210.0/255),1);}
    """
}
