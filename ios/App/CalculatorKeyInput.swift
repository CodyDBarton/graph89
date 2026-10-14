// Key transitions must survive rapid taps and span native keyboard scans.
// Accessed only on CalculatorEngine's serial queue; time is emulated CPU work.
struct CalculatorKeyInput {
    struct Event {
        let key: Int
        let pressed: Bool
    }
    private var events: [Event] = []
    private var requested = Set<Int>()
    private var scanRemaining = 0
    // Verified with repeated input, Home menus, and the equation list in AMS 3.10.
    static let scanInstructions = 400_000
    static let releaseInstructions = 400_000
    var hasPending: Bool { !events.isEmpty }

    mutating func enqueue(_ key: Int, pressed: Bool) {
        guard requested.contains(key) != pressed else { return }
        if pressed { requested.insert(key) } else { requested.remove(key) }
        events.append(Event(key: key, pressed: pressed))
    }
    mutating func takeReady() -> [Event] {
        guard scanRemaining == 0, !events.isEmpty else { return [] }
        let event = events.removeFirst()
        scanRemaining = event.pressed ? Self.scanInstructions : Self.releaseInstructions
        return [event]
    }
    func runLimit(_ instructions: Int) -> Int {
        scanRemaining > 0 ? min(instructions, scanRemaining) : instructions
    }
    mutating func advance(_ instructions: Int) {
        scanRemaining = max(0, scanRemaining - instructions)
    }
    mutating func reset() {
        events.removeAll()
        requested.removeAll()
        scanRemaining = 0
    }
}
