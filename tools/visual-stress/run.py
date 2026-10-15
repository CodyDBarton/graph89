#!/usr/bin/env python3
from pathlib import Path
import argparse, subprocess
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('rom',type=Path);p.add_argument('--output',type=Path,default=root/'build/visual-stress/before');p.add_argument('--native-original',action='store_true');p.add_argument('--scenario',choices=['full','errors','errors-fast','catalog-help','rotation','rotation-format'],default='full');a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
with (out/'build.log').open('w') as f:subprocess.run(['python3',str(root/'ios/tools/build_native.py'),'--sdk','macosx','--draw-trace'],stdout=f,stderr=subprocess.STDOUT,check=True)
j=root/'app/src/main/jni';d=root/'ios/build/macosx-draw-trace'
incs=[d/'include',root/'ios/native',j/'glib',j/'glib/glib',j/'tiemu-3.03/src']+[j/x/'src' for x in ['libticonv-1.1.3','libtifiles2-1.1.5','libticables2-1.3.3','libticalcs2-1.1.7']]+[j/'tiemu-3.03/src'/x for x in ['core','core/uae','core/ti_hw','core/ti_sw','core/dbg','misc','gui']]
cmd=['xcrun','clang','-O2','-std=gnu99','-DHAVE_CONFIG_H','-DNO_GDB','-DNO_SOUND']
for i in incs:cmd+=['-I',str(i)]
cmd+=[str(root/'tools/visual-stress/stress.c'),str(d/'libGraph89.a'),'-Wl,-dead_strip','-lz','-liconv','-o',str(out/'stress')];subprocess.run(cmd,check=True)
with (out/'run.log').open('w') as f:subprocess.run([str(out/'stress'),str(a.rom.resolve()),str(out)]+([a.scenario] if a.scenario!='full' else [])+(['original'] if a.native_original else []),stdout=f,stderr=subprocess.STDOUT,check=True)
print((out/'run.log').read_text().splitlines()[-1])
