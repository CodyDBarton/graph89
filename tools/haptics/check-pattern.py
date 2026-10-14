#!/usr/bin/env python3
"""Verify the production Core Haptics factory using Apple's native framework."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "ios/App/Graph89App.swift").read_text()
start = source.index("    static func pattern(milliseconds:")
end = source.index("\n    private func record", start)
checks = r"""
let zero = try Pulse.pattern(milliseconds: 0); assert(zero == nil)
let negative = try Pulse.pattern(milliseconds: -1); assert(negative == nil)
for milliseconds in 1...250 {
    let pattern = try Pulse.pattern(milliseconds: milliseconds)!
    assert(abs(pattern.duration - Double(milliseconds) / 1000) < 0.000001)
    let exported = try pattern.exportDictionary()
    let events = exported[CHHapticPattern.Key.pattern] as! [[CHHapticPattern.Key: Any]]
    assert(events.count == 1)
    let event = events[0][CHHapticPattern.Key.event] as! [CHHapticPattern.Key: Any]
    assert(event[CHHapticPattern.Key.eventType] as! String == CHHapticEvent.EventType.hapticContinuous.rawValue)
}
let clamped = try Pulse.pattern(milliseconds: 1000)!
assert(abs(clamped.duration - 0.25) < 0.000001)
print("PASS: disabled at zero; every 1–250 ms value has one continuous event with matching effective duration; upper bound clamped")
"""
with tempfile.TemporaryDirectory(prefix="graph89-haptic-check-") as folder:
    path = Path(folder) / "check.swift"
    path.write_text("import Foundation\nimport CoreHaptics\nenum Pulse {\n" + source[start:end] + "\n}\n" + checks)
    subprocess.run(["xcrun", "swift", str(path)], check=True)
