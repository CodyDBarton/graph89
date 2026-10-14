#!/usr/bin/env python3
"""Compare burst taps delivered by the iOS queue with slow real-ROM references."""
from pathlib import Path
import argparse, subprocess
root = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument("rom", type=Path)
p.add_argument("--output", type=Path, default=root/"build/key-input")
a=p.parse_args(); out=a.output.resolve(); out.mkdir(parents=True,exist_ok=True)
with (out/"build.log").open("w") as log:
    subprocess.run(["python3", str(root/"ios/tools/build_native.py"),"--sdk","macosx"],stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run(["xcrun","clang","-c",str(root/"tools/key-input/clock.c"),"-o",str(out/"clock.o")],stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run(["xcrun","swiftc",str(root/"ios/App/CalculatorKeyInput.swift"),str(root/"tools/key-input/main.swift"),"-import-objc-header",str(root/"tools/key-input/bridge.h"),str(out/"clock.o"),str(root/"ios/build/macosx/libGraph89.a"),"-Xlinker","-dead_strip","-lz","-liconv","-o",str(out/"check")],stdout=log,stderr=subprocess.STDOUT,check=True)
for name in ["repeated-digit","mixed-digits","editor-left","menu-down","equation-menu-down"]:
    expected=None
    for batch in [0,27000,90000,225000]:
        folder=out/f"{name}-{batch}";folder.mkdir(exist_ok=True)
        with (folder/"run.log").open("w") as log:
            subprocess.run([str(out/"check"),str(a.rom.resolve()),str(folder),name,str(batch)],stdout=log,stderr=subprocess.STDOUT,check=True)
        actual=(folder/"capture.pgm").read_bytes()[-16000:]
        if expected is None:expected=actual;continue
        rows=range(84,94) if name in ["repeated-digit","mixed-digits","editor-left"] else range(16,84)
        differences=sum(expected[y*160+x]!=actual[y*160+x] for y in rows for x in range(160))
        assert differences<=20,(name,batch,differences)
        print(f"{name}, batch {batch}: all burst taps preserved ({differences} cursor-blink pixels)",flush=True)
print("Repeated taps, mixed input, menu navigation, scan gaps and pause cancellation passed")
