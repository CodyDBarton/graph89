#!/usr/bin/env python3
"""Build and compare traced/untraced standalone TI-89 runs. Never uses app state."""
import argparse
import collections
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('rom', type=Path)
parser.add_argument('--output', type=Path, default=ROOT/'build/drawing-trace')
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
jni = ROOT/'app/src/main/jni'
for mode in ["control", "observe", "retained"]:
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
    command += [str(ROOT/'tools/drawing-trace/trace.c'),str(directory/'libGraph89.a'),'-Wl,-dead_strip','-lz','-liconv','-o',str(exe)]
    subprocess.run(command,check=True)
    run_dir = args.output/(exe.name+'-run')
    run_dir.mkdir(exist_ok=True)
    for pattern in ['*.pgm','*.cells.json']:
        for old_frame in run_dir.glob(pattern): old_frame.unlink()
    with (args.output/(exe.name+'.log')).open('w') as log:
        subprocess.run([str(exe),str(args.rom.resolve()),str(args.output/(exe.name+'-run')),exe.name],stdout=log,stderr=subprocess.STDOUT,check=True)

control=args.output/'control-run'
observe=args.output/'observe-run'
frames=[]
for p in sorted(observe.glob('*.pgm')):
    same=p.read_bytes()==(control/p.name).read_bytes()
    frames.append({'frame':p.name,'identical':same})
events=[json.loads(line) for line in (observe/'events.jsonl').read_text().splitlines()]
checks = {
    'italic_e_input': any(e['phase']=='exponential-input' and e.get('character')==150 for e in events),
    'italic_e_pretty': any(e['phase']=='exponential-pretty' and e.get('character')==150 for e in events),
    'italic_e_catalog': any(e['phase']=='catalog-e' and e.get('character')==150 for e in events),
    'derivative_d': any(e['phase']=='derivative-pretty' and e.get('character')==188 for e in events),
    'shaded_toolbar': any(e['phase']=='history-selected' and e.get('attr')==3 and e['call']=='DrawChar' for e in events),
    'pretty_print_entry': all(any(e['phase']==phase and e['call']=='Print2DExpr' for e in events) for phase in ['pretty-print','integral-pretty','exponential-pretty','derivative-pretty','tall-integral-pretty']),
    'no_error_dialog': not any(e['call']=='DrawStr' and e.get('text_hex')=='4552524f52' for e in events),
    'valid_live_text_font': all(e['font'] in [0,1,2] for e in events if e['call'] in ['DrawChar','DrawClipChar']),
}
phases={}
for event in events:
    stats=phases.setdefault(event['phase'],{'calls':collections.Counter(),'text_samples':[],'character_samples':[]})
    stats['calls'][event['call']]+=1
    if 'text_hex' in event and len(stats['text_samples'])<30:
        stats['text_samples'].append({k:event[k] for k in ['call','x','y','text_hex'] if k in event})
    if event['call']=='DrawClipChar' and len(stats['character_samples'])<20:
        stats['character_samples'].append({k:event[k] for k in ['character','x','y','font','font_hint','attr','clip_hex','port_hint']})
summary={'rom':json.loads((observe/'calls.json').read_text()),'events':len(events),'checks':checks,'phases':phases,'frames':frames,'timing':{name:json.loads((args.output/(name+'-run')/'timing.json').read_text()) for name in ['control','observe']}}
(args.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(f"Captured {len(events)} calls. {sum(f['identical'] for f in frames)}/{len(frames)} screenshots identical to untraced build.")
for phase,stats in phases.items(): print(phase,dict(stats['calls']))
if not frames or not all(f['identical'] for f in frames):raise SystemExit('Trace/control framebuffer comparison failed')

if not all(checks.values()): raise SystemExit('Scenario coverage checks failed: '+str(checks))
print('All scenario coverage checks passed.')

retained=args.output/'retained-run'
retained_frames=[]
for p in sorted(retained.glob('*.pgm')):
    retained_frames.append({'frame':p.name,'identical':p.read_bytes()==(control/p.name).read_bytes(),'captured_characters':len(json.loads(p.with_suffix('.cells.json').read_text()))})
(args.output/'retained-summary.json').write_text(json.dumps(retained_frames,indent=2)+'\n')
if not all(f['identical'] for f in retained_frames):raise SystemExit('Retained layer changed original LCD')
required=['01-home','02-input','03-pretty-print','05-tools-menu','06-catalog','09-integral-pretty','10-exponential-input','11-exponential-pretty','13-derivative-pretty','15-tall-integral-pretty','16-catalog-e','16b-menu-restored']
for name in required:
    cells=json.loads((retained/(name+'.cells.json')).read_text())
    if not cells:raise SystemExit('No retained characters in '+name)
for name,code in [('10-exponential-input',150),('11-exponential-pretty',150),('16-catalog-e',150),('13-derivative-pretty',188)]:
    cells=json.loads((retained/(name+'.cells.json')).read_text())
    if not any(c[3]==code for c in cells):raise SystemExit('Missing retained ROM identity in '+name)
print('Retained identities, cursor, inversion, clear/state invalidation and LCD parity passed.')
for f in retained_frames: print(f['frame'],f['captured_characters'])
