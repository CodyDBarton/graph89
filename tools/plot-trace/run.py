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

    for factor in [0,8]:
        run_dir=args.output/('navigation-hd' if factor else 'navigation-original');run_dir.mkdir(exist_ok=True)
        with (run_dir/'run.log').open('w') as log:
            subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),str(factor),'x^2','navigation'],stdout=log,stderr=subprocess.STDOUT,check=True)

    for factor in [0,8]:
        run_dir=args.output/('intersection-hd' if factor else 'intersection-original');run_dir.mkdir(exist_ok=True)
        with (run_dir/'run.log').open('w') as log:
            subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),str(factor),'x^2\n1','intersection'],stdout=log,stderr=subprocess.STDOUT,check=True)

    for mode in ['resume','disable','interrupt']:
        run_dir=args.output/mode;run_dir.mkdir(exist_ok=True)
        with (run_dir/'run.log').open('w') as log:
            subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),'8','sin(x^2)',mode],stdout=log,stderr=subprocess.STDOUT,check=True)

    for factor in [0,8]:
        for speed in [1,3]:
            run_dir=args.output/('held-%d-speed-%d'%(factor,speed));run_dir.mkdir(exist_ok=True)
            with (run_dir/'run.log').open('w') as log:
                subprocess.run([str(exe),str(args.rom.resolve()),str(run_dir),str(factor),'sin(x^2)','held-'+str(speed)],stdout=log,stderr=subprocess.STDOUT,check=True)

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
    assert (hd/'menu.points').read_text()==(hd/'graph.points').read_text(),name+': HD curve disappeared behind menu'
    assert 255 in (hd/'menu.overlay.pgm').read_bytes()[-16000:],name+': menu is not preserved above HD plot'
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
    assert (hd/'menu.axes').read_text()==(hd/'graph.axes').read_text(),name+': axes disappeared behind menu'
    assert not (hd/'disabled.axes').read_text().strip()
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

# Navigation overlays change LCD pixels without changing the plotted function.
nav=args.output/'navigation-hd';original=args.output/'navigation-original'
reference=(nav/'graph.pgm').read_bytes()[-16000:]
for name in ['cursor-right','cursor-up','trace','trace-right','trace-left','trace-up','trace-down','trace-exit','zoom-menu','zoom-return','math-menu','math-return','value-prompt','value-return','graph-return']:
    assert (nav/(name+'.pgm')).read_bytes()==(original/(name+'.pgm')).read_bytes(),name+': native interaction changed'
    assert (nav/(name+'.points')).read_text()==(nav/'graph.points').read_text(),name+': HD curve lost/changed'
    assert (nav/(name+'.axes')).read_text()==(nav/'graph.axes').read_text(),name+': HD axes lost'
    cursor_mask=(nav/(name+'.cursor.pgm')).read_bytes()[-16000:]
    pixels=(nav/(name+'.pgm')).read_bytes()[-16000:];mask=(nav/(name+'.overlay.pgm')).read_bytes()[-16000:]
    for y in range(16,93):
        for x in range(159):
            i=y*160+x
            if pixels[i]!=reference[i]: assert mask[i]==255 or cursor_mask[i]==255,(name,'Navigation overlay erased',x,y)
    assert sum(mask[i]==0 for y in range(16,93) for x in range(159) for i in [y*160+x])>1000,name+': whole graph became raster'
assert not (nav/'y-editor.points').read_text().strip(),'HD graph covered Y= editor'
for name in ['cursor-right','trace-right','trace-up']:
    mask=(nav/(name+'.overlay.pgm')).read_bytes()[-16000:]
    assert sum(mask[i]==255 for y in range(16,83) for x in range(140) for i in [y*160+x])<=169,(name,'Cursor replaced too much graph')
print('Cursor arrows, Trace movement, popup menus and Value prompt retain HD curves/axes and preserve native overlays; Y= remains untouched.')

assert (nav/'zoom-in.pgm').read_bytes()==(original/'zoom-in.pgm').read_bytes(),'Zoom changed native calculation'
assert len((nav/'zoom-in.points').read_text().splitlines())>1200,'Zoomed window did not regenerate HD samples'
assert (nav/'zoom-in.points').read_text()!=(nav/'graph.points').read_text(),'Zoom incorrectly reused old-window vectors'
print('Zoom regenerates HD samples for the changed window; original pixels remain identical.')

for name in ['cursor-right','trace-right','trace-up']:
    mask=(nav/(name+'.cursor.pgm')).read_bytes()[-16000:]
    assert 0<sum(v==255 for v in mask)<=169,(name,'Native cursor needs explicit glyph protection')
print('Native cursor patches are explicitly protected from Sharp Text replacement.')

for name in ['cursor-right','cursor-up','trace','trace-right','trace-left','trace-up','trace-down']:
    markers=[list(map(float,line.split())) for line in (nav/(name+'.navigation')).read_text().splitlines()]
    assert any(row[0] in [-1,-2] for row in markers),(name,'Missing verified vector cursor')
    if name.startswith('trace'):
        assert [49,148,18] in markers,(name,'Missing sharp plot number')
for name in ['graph','y-editor','home','disabled']:
    assert not (nav/(name+'.navigation')).read_text().strip(),(name,'Stale graph navigation artwork')
print('Verified circle/cross identity and sharp plot number follow every Trace/arrow movement and disappear outside the graph.')

blink_phases=set()
for index in range(8):
    name='trace-blink-'+str(index)
    markers=[list(map(float,line.split())) for line in (nav/(name+'.navigation')).read_text().splitlines()]
    blink_phases.update(row[0] for row in markers if row[0]<0)
    assert [49,148,18] in markers,(name,'Plot number disappeared during cursor blinking')
assert blink_phases=={-1,-2},('Both native cursor blink phases must remain vector based',blink_phases)
print('Both cursor blink phases use vector metadata; the plot ID remains sharp throughout.')

for factor in [0,8]:
    baseline=args.output/('held-%d-speed-1'%factor);fast=args.output/('held-%d-speed-3'%factor)
    frames=lambda p:[list(map(int,line.split())) for line in (p/'held.txt').read_text().splitlines()]
    original,accelerated=frames(baseline),frames(fast)
    ratio=accelerated[-1][1]/original[-1][1]
    assert 2.7<ratio<3.3,('Trace hold multiplier',factor,ratio)
    assert next(r[0] for r in original if r[1])==next(r[0] for r in accelerated if r[1]),'Initial hold delay changed'
    assert (fast/'scope.txt').read_text()=='released 1\nfree 3\ny 3\n','Held-arrow speed did not apply globally'
    free=lambda p:[list(map(int,line.split())) for line in (p/'free.txt').read_text().splitlines()]
    normal_free,fast_free=free(baseline),free(fast)
    free_ratio=fast_free[-1][1]/normal_free[-1][1]
    assert 2.7<free_ratio<3.3,('Free graph cursor multiplier',factor,free_ratio)
    for directory in [baseline,fast]:
        for file in ['held','free','reheld']:
            rows=[list(map(int,line.split())) for line in (directory/(file+'.txt')).read_text().splitlines()]
            assert all(r[1]<=1 for r in rows if r[0]<35),(file,'Repeated before 0.35s')
            assert all(r[-1]==1 for r in rows if r[0]<35),(file,'Boosted before 0.35s')
        repeated=[list(map(int,line.split())) for line in (directory/'reheld.txt').read_text().splitlines()]
        assert repeated[-1][1]>1,'Repeated hold never resumed movement'
    assert next(r[0] for r in accelerated if r[-1]==3)==35,'Trace speed must begin at 0.35s'
    assert next(r[0] for r in fast_free if r[-1]==3)==35,'Free graph speed must begin at 0.35s'
    if factor:
        assert all(r[5] in [-1,-2,-3,-4] for r in original+accelerated),'Held cursor became raster'
        assert any(r[5]==-3 for r in accelerated),'Large held cursor was never vectorized'
    print('Trace hold, HD=%d: %d -> %d steps (%.2fx); 0.35s global repeat threshold; no raster cursor frames.'%(factor,original[-1][1],accelerated[-1][1],ratio))

intersection=args.output/'intersection-hd'
for name,width in [('first-curve',60),('second-curve',60),('lower-bound',72),('upper-bound',72),('intersection-result',72)]:
    mask=(intersection/(name+'.overlay.pgm')).read_bytes()[-16000:]
    assert all(mask[y*160+x] for y in range(76,84) for x in range(5,5+width)),(name,'Prompt cell clipped by HD plot')
    cursor=(intersection/(name+'.cursor.pgm')).read_bytes()[-16000:]
    assert not any(cursor[y*160+x] for y in range(76,84) for x in range(5,5+width)),(name,'Prompt mistaken for cursor')
    assert len((intersection/(name+'.points')).read_text().splitlines())>2400,(name,'Lost HD curves')
print('All five intersection prompts preserve complete text rectangles and both HD curves.')
closed_mask=(intersection/'intersection-closed.overlay.pgm').read_bytes()[-16000:]
assert not any(closed_mask[76*160:84*160]),'Intersection left a stale prompt mask'
