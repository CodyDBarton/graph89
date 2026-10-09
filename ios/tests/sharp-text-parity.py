#!/usr/bin/env python3
"""Compare Swift against Android using private, locally captured original LCD fixtures.
Usage: python3 ios/tests/sharp-text-parity.py FONT_TEMPLATES FRAME_DIRECTORY
No firmware or original screen bytes are included in the repository.
"""
from pathlib import Path
import subprocess,sys,os
root=Path(__file__).resolve().parents[2];os.chdir(root)
fonts=Path(sys.argv[1]);folder=Path(sys.argv[2]);out=root/'build/ios-sharp-parity';out.mkdir(parents=True,exist_ok=True)
java=Path('/opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home/bin')
subprocess.run([str(java/'javac'),'-d',str(out),'app/src/main/java/com/graph89/emulationcore/SharpTextRecognizer.java','ios/tests/SharpTextParity.java'],check=True)
subprocess.run(['xcrun','swiftc','-O','ios/App/SharpTextRecognizer.swift','ios/tests/SharpTextParity.swift','-o',str(out/'swift-parity')],check=True)
frames=[p for p in sorted(folder.glob('*.bin')) if p.stat().st_size==16000 and set(p.read_bytes())<=set([0,1])]
if not frames:raise SystemExit('No original 160 × 100 binary LCD fixtures')
args=[str(fonts)]+[str(p) for p in frames]
a=subprocess.check_output([str(java/'java'),'-cp',str(out),'SharpTextParity',*args],text=True).splitlines()
b=subprocess.check_output([str(out/'swift-parity'),*args],text=True).splitlines()
assert len(a)==len(b)
for i,(aa,bb) in enumerate(zip(a,b)):
 if aa!=bb:
  (out/'android.txt').write_text('\n'.join(a));(out/'swift.txt').write_text('\n'.join(b))
  print('Mismatch:',frames[i//2], 'fresh' if i%2==0 else 'stable');print('Android only:',set(aa.split(';'))-set(bb.split(';')));print('Swift only:',set(bb.split(';'))-set(aa.split(';')));raise SystemExit(1)
print(f'{len(frames)} actual-ROM screens: fresh and cached Swift/Android recognition identical.')
