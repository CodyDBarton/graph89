#!/usr/bin/env python3
"""Verify ROM-backed HD plotting in isolated calculator sessions."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('rom', type=Path)
parser.add_argument('--output', type=Path, default=ROOT/'build/plot-trace')
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
jni = ROOT/'app/src/main/jni'
for mode in ["observe"]:
    tracing = mode in ["observe", "retained"]
    command = ['python3',str(ROOT/'ios/tools/build_native.py'),'--sdk','macosx']
    if tracing: command += ['--draw-trace']
    with (args.output/('build-'+mode+'.log')).open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    directory = ROOT/'ios/build'/('macosx-draw-trace' if tracing else 'macosx')
    cc = subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
    includes = [directory/'include', ROOT/'ios/native', jni/'glib',jni/'glib/glib',jni/'tiemu-3.03/src']
    includes += [jni/x/'src' for x in ['libticonv-1.1.3','libtifiles2-1.1.5','libticables2-1.3.3','libticalcs2-1.1.7']]
    includes += [jni/'tiemu-3.03/src'/x for x in ['core','core/uae','core/ti_hw','core/ti_sw','core/dbg','misc','gui']]
    exe = args.output/mode
    sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    command=[cc,'-isysroot',sdk,'-arch','arm64','-std=gnu99','-O2','-DHAVE_CONFIG_H','-DNO_GDB','-DNO_SOUND']
    if tracing: command+=['-DGRAPH89_DRAW_TRACE']
    for inc in includes:command+=['-I',str(inc)]
    command += [str(ROOT/'tools/plot-trace/trace.c'),str(directory/'libGraph89.a'),'-Wl,-dead_strip','-lz','-liconv','-o',str(exe)]
    subprocess.run(command,check=True)
    run_dir = args.output/(exe.name+'-run')
    run_dir.mkdir(exist_ok=True)
    for pattern in ['*.pgm','*.cells.json']:
        for old_frame in run_dir.glob(pattern): old_frame.unlink()
    for name,equation in [('empty',''),('oscillating','sin(x^2)'),('pole','1/x'),('domain','x^(1/2)'),('tangent','tan(x)'),('polynomial','x^2')]:
        for factor in [0,8]:
            run_dir=args.output/(name+('-hd' if factor else '-original'));run_dir.mkdir(exist_ok=True)
            with (run_dir/'run.log').open('w') as log:
                subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),str(factor),equation],stdout=log,stderr=subprocess.STDOUT,check=True)

    for factor in [0,8]:
        run_dir=args.output/('multiple-hd' if factor else 'multiple-original');run_dir.mkdir(exist_ok=True)
        with (run_dir/'run.log').open('w') as log:
            subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),str(factor),'sin(x^2)\ncos(x)'],stdout=log,stderr=subprocess.STDOUT,check=True)

    for mode in ['style','window','coarse','grid','axes-off','box','labels']:
        for factor in [0,8]:
            run_dir=args.output/(mode+('-hd' if factor else '-original'));run_dir.mkdir(exist_ok=True)
            with (run_dir/'run.log').open('w') as log:
                subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),str(factor),'sin(x^2)',mode],stdout=log,stderr=subprocess.STDOUT,check=True)

    for mode in ['progress','incremental','incremental-restored']:
        for factor in [0,8]:
            run_dir=args.output/(mode+('-hd' if factor else '-original'));run_dir.mkdir(exist_ok=True)
            with (run_dir/'run.log').open('w') as log:
                subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),str(factor),'sin(x^2)',mode],stdout=log,stderr=subprocess.STDOUT,check=True)

    for mode in ['resume','disable','interrupt']:
        run_dir=args.output/mode;run_dir.mkdir(exist_ok=True)
        with (run_dir/'run.log').open('w') as log:
            subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),'8','sin(x^2)',mode],stdout=log,stderr=subprocess.STDOUT,check=True)

import math
functions={'oscillating':lambda x:math.sin(x*x),'pole':lambda x:1/x,'domain':lambda x:math.sqrt(x),'tangent':math.tan,'polynomial':lambda x:x*x}
for name,fn in functions.items():
    original=args.output/(name+'-original');hd=args.output/(name+'-hd')
    assert (original/'graph.pgm').read_bytes()==(hd/'graph.pgm').read_bytes(),name+': original LCD changed'
    rows=[list(map(float,s.split())) for s in (hd/'graph.points').read_text().splitlines()]
    assert len(rows)>1200,name+': missing dense evaluations'
    assert rows[:2]==[[0,16],[159,93]],name+': unexpected graph bounds'
    good=0
    for px,py in rows[2:]:
        if not math.isfinite(px) or not math.isfinite(py):continue
        x=-10+px/158*20;y=10-(py-16)/76*20
        if abs(x)<0.001 or abs(y)>100:continue
        if name=='domain' and x<0:continue
        expected=fn(x)
        assert abs(y-expected)<max(0.0001,abs(expected)*0.00005),(name,x,y,expected)
        good+=1
    assert good>100,name+': inadequate numerical coverage'
    assert (hd/'restored.points').read_text()==(hd/'graph.points').read_text(),name+': completed HD graph lost after restore'
    assert (hd/'restored.background.pgm').read_bytes()==(hd/'graph.background.pgm').read_bytes(),name+': saved axes changed after restore'
    assert (hd/'regraph.points').read_text()==(hd/'graph.points').read_text(),name+': regraph changed vectors'
    assert (hd/'regraph.background.pgm').read_bytes()==(hd/'graph.background.pgm').read_bytes(),name+': regraph retained old curves in background'
    assert not (hd/'menu.points').read_text().strip(),name+': graph overlay leaked into menu'
    assert (hd/'returned.points').read_text()==(hd/'graph.points').read_text(),name+': graph did not survive menu close'
    assert not (hd/'disabled.points').read_text().strip(),name+': original toggle failed'
    assert not (hd/'home.points').read_text().strip(),name+': graph overlay leaked into Home'
    print(name,': dense ROM values verified; original LCD, menu and toggle unchanged')
assert (args.output/'multiple-hd'/'graph.pgm').read_bytes()==(args.output/'multiple-original'/'graph.pgm').read_bytes(),'Multiple functions changed original LCD'
multiple=[list(map(float,s.split())) for s in (args.output/'multiple-hd'/'graph.points').read_text().splitlines()]
assert len(multiple)>2500,'Both functions must receive extra samples'
assert sum(math.isnan(x) and math.isnan(y) for x,y in multiple)==2,'Functions must remain separate paths'
print('Multiple selected functions retain independent dense paths and identical original LCD pixels.')
for mode in ['resume','disable']:
    assert (args.output/mode/'graph.pgm').read_bytes()==(args.output/'oscillating-original/graph.pgm').read_bytes(),mode+': original execution did not resume correctly'
    assert not (args.output/mode/'graph.points').read_text().strip(),mode+': stale vectors survived'
assert not (args.output/'interrupt'/'graph.points').read_text().strip(),'Interrupted graph must not publish incomplete vectors'
print('In-flight save/restore, disabling, and ON interruption scenarios completed.')

for mode in ['style','window','coarse']:
    original=args.output/(mode+'-original');hd=args.output/(mode+'-hd')
    assert (original/'graph.pgm').read_bytes()==(hd/'graph.pgm').read_bytes(),mode+': native graph changed'
    rows=[list(map(float,s.split())) for s in (hd/'graph.points').read_text().splitlines()]
    if mode=='style':
        assert not rows,'Nonstandard graph style must stay original'
        assert (hd/'run.log').read_text().split('Initial plot style ')[1][0]!='0','Style fixture did not change style'
    else:
        assert len(rows)>1200,mode+': dense samples missing'
        for px,py in rows[2:]:
            if not math.isfinite(px) or not math.isfinite(py):continue
            x=-5+px/158*10;y=10-(py-16)/76*20
            assert abs(y-math.sin(x*x))<0.0001,(mode,x,y)
    print(mode,': window coordinates, density and style preservation verified')

for name in ['oscillating','polynomial','window','coarse','grid','axes-off','box','labels']:
    hd=args.output/(name+'-hd')
    geometry=[list(map(float,s.split())) for s in (hd/'graph.axes').read_text().splitlines()]
    if name in ['grid','axes-off','box','labels']:
        assert (hd/'graph.pgm').read_bytes()==(args.output/(name+'-original')/'graph.pgm').read_bytes(),name+': axis capture changed LCD'
    if name=='axes-off': assert not geometry,'Axes off still draws axes'
    else: assert geometry,name+': missing vector axis geometry'
    assert (hd/'regraph.axes').read_text()==(hd/'graph.axes').read_text(),name+': ReGraph changed decorations'
    if name in ['oscillating','polynomial']:
        assert (hd/'restored.axes').read_text()==(hd/'graph.axes').read_text(),name+': state did not retain axis vectors'
        assert len(geometry)==44,(name,len(geometry))
        assert [79.5,16.5,79.5,92.5] in geometry and [0.5,54.5,158.5,54.5] in geometry
        assert any(abs(x-8.4)<0.0001 for x,y,u,v in geometry),'Tick coordinates were rounded to LCD columns'
        assert not any((hd/'graph.background.pgm').read_bytes()[-16000:][y*160+x]==30 for y in range(16,93) for x in range(159)),'Raster axis pixels survived'
    assert not (hd/'menu.axes').read_text().strip() and not (hd/'disabled.axes').read_text().strip()
    print(name,': vector axes/grid captured, original LCD and cache preserved; segments=',len(geometry))

empty=args.output/'empty-hd'
assert (empty/'graph.pgm').read_bytes()==(args.output/'empty-original'/'graph.pgm').read_bytes(),'Empty graph changed original LCD'
assert len((empty/'graph.axes').read_text().splitlines())==44,'Empty graphs need HD axes too'
assert (empty/'restored.axes').read_text()==(empty/'graph.axes').read_text(),'Empty graph cache did not survive restore'
assert (empty/'regraph.axes').read_text()==(empty/'graph.axes').read_text(),'Empty graph ReGraph lost axes'
assert not (empty/'disabled.axes').read_text().strip(),'Empty graph toggle failed'
print('Empty graph: vector axes without selected functions; native LCD, state and toggle verified.')

for mode in ['progress','incremental','incremental-restored']:
    hd=args.output/(mode+'-hd');original=args.output/(mode+'-original')
    frames,missing,ink=map(int,(hd/'progress.txt').read_text().split())
    assert frames>30,(mode,'No progressive HD display',frames)
    assert missing==0,(mode,'Partial native raster leaked through',missing)
    assert ink==0,(mode,'Native curves leaked into HD background',ink)
    label='incremental' if mode.startswith('incremental') else 'graph'
    assert (hd/(label+'.pgm')).read_bytes()==(original/(label+'.pgm')).read_bytes(),mode+': original LCD changed'
    if mode.startswith('incremental'):
        rows=[list(map(float,s.split())) for s in (hd/'incremental.points').read_text().splitlines()]
        assert len(rows)>2500,('Incremental graph lost an HD function',len(rows))
        assert sum(math.isnan(x) and math.isnan(y) for x,y in rows)==2,'Incremental functions merged/lost paths'
        paths=[]
        for px,py in rows[2:]:
            if not math.isfinite(px) or not math.isfinite(py):paths.append([])
            else:paths[-1].append((px,py))
        for path,fn in zip(paths,[lambda x:math.sin(x*x),math.cos]):
            assert len(path)==1265,'Incremental graph lost evaluated samples'
            for px,py in path:
                x=-10+px/158*20;y=10-(py-16)/76*20
                assert abs(y-fn(x))<0.0001,(mode,x,y)

    print(mode,': progressive HD frames=',frames,'no raster fallback or native curves in background')
