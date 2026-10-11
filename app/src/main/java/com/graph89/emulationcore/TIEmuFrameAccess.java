package com.graph89.emulationcore;

import java.util.concurrent.locks.ReentrantLock;

/** Short native CPU batches and display snapshots share a fair handoff.
 * A waiting frame reader runs before the CPU starts another batch. Java
 * text recognition and Canvas drawing never hold this gate. */
final class TIEmuFrameAccess {
    static final ReentrantLock lock = new ReentrantLock(true);
    private TIEmuFrameAccess() {}
    static void runEngine(boolean turbo) {
        lock.lock();
        try {
            if(turbo) EmulatorActivity.nativeTiEmuRunTurboChunk();
            else EmulatorActivity.nativeTiEmuRunEngine();
        } finally { lock.unlock(); }
    }
}
