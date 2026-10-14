import Foundation

func run(_ count: Int) { graph89_run(Int32(count)) }
func tap(_ key: Int) { graph89_key(Int32(key), 1); run(400_000); graph89_key(Int32(key), 0); run(400_000) }
func screen() -> [UInt8] { var p = [UInt8](repeating: 0, count: 16000); graph89_copy_screen(&p); return p }
func queued(_ keys: [Int], batch: Int) {
    var input = CalculatorKeyInput()
    for k in keys { input.enqueue(k, pressed: true); input.enqueue(k, pressed: false) }
    var frames = 0
    while input.hasPending || frames < 4 {
        var n = batch
        while n > 0 {
            for e in input.takeReady() { graph89_key(Int32(e.key), e.pressed ? 1 : 0) }
            let count = input.runLimit(n)
            run(count); input.advance(count); n -= count
        }
        for e in input.takeReady() { graph89_key(Int32(e.key), e.pressed ? 1 : 0) }
        frames += 1
        precondition(frames < 1000)
    }
    run(2_000_000)
}
freeze_input_clock()
let args = CommandLine.arguments
precondition(args.count == 5, "ROM, output folder, scenario, and batch required")
precondition(graph89_start(args[1], args[2] + "/tap.img") == 0)
graph89_retained_text_enable(1)
run(30_000_000); tap(82); tap(56)
let name = args[3], batch = Int(args[4])!
var keys: [Int] = []
switch name {
case "repeated-digit": keys = Array(repeating:10,count:12)
case "mixed-digits": keys = [10,9,8,10,9,8,10,9,8]
case "editor-left":
    for k in [10,9,8,10,9,8,10,9,8,10,9,8] { tap(k) }
    keys = Array(repeating:3,count:8)
case "menu-down": tap(49); keys = Array(repeating:0,count:5)
case "equation-menu-down": tap(6); tap(49); keys = Array(repeating:0,count:6)
default: fatalError("Unknown scenario")
}
run(1_000_000)
if batch == 0 { for k in keys { tap(k) }; run(2_000_000) }
else { queued(keys,batch:batch) }
try! Data("P5\n160 100\n255\n".utf8 + screen()).write(to: URL(fileURLWithPath: args[2]+"/capture.pgm"))
graph89_stop()

// No scan gap can be cancelled by a later touch; holds produce only one edge.
var input = CalculatorKeyInput()
input.enqueue(0, pressed: true)
precondition(input.takeReady().count == 1)
input.enqueue(0, pressed: true)
precondition(!input.hasPending)
input.enqueue(0, pressed: false); input.enqueue(0, pressed: true)
precondition(input.takeReady().isEmpty)
input.advance(CalculatorKeyInput.scanInstructions)
precondition(input.takeReady().first?.pressed == false)
precondition(input.takeReady().isEmpty)
input.advance(CalculatorKeyInput.releaseInstructions)
precondition(input.takeReady().first?.pressed == true)
input.reset(); precondition(!input.hasPending)
print("Hold, release gap, and pause cancellation passed")
